require "date"
require "digest/md5"
require "redis"
require "configatron"
require "httparty"
require "logger"
require 'optparse'
require "./config/config"

$options = {
  logfile: "/var/log/listbooru/processor.log",
  init: false,
  update: false,
  clean: false
}

OptionParser.new do |opts|
  opts.on("--logfile=LOGFILE") do |logfile|
    $options[:logfile] = logfile
  end

  opts.on("--action=ACTION", ["all", "init", "update", "clean"]) do |action|
    case action
    when "all"
      $options[:init] = true
      $options[:update] = true
      $options[:clean] = true

    when "init"
      $options[:init] = true

    when "update"
      $options[:update] = true

    when "clean"
      $options[:clean] = true
    end
  end
end.parse!

REDIS = Redis.new
LOGGER = Logger.new(File.open($options[:logfile], "a"))

class Processor
  def initialize_searches
    while true
      query = REDIS.spop("searches/initial")
      break if query.nil?

      if REDIS.zcard("searches:#{query}") == 0
        LOGGER.info "initializing #{query}"
        resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", query: {login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: query, limit: configatron.max_posts_per_search})

        if resp.code == 200
          posts = JSON.parse(resp.body)
          data = []
          LOGGER.info "  results #{posts.size}"
          posts.each do |post|
            data << post['id']
            data << post['id']
          end
          if data.any?
            REDIS.zadd "searches:#{query}", data
            REDIS.zremrangebyrank "searches:#{query}", 0, -configatron.max_posts_per_search
            REDIS.expire "searches:#{query}", configatron.cache_expiry
          end
        end
      end
    end
  end

  def update_searches
    cursor = 0
    min_date = (Date.today - 3).strftime("%Y-%m-%d")

    REDIS.scan_each(match: "searches:*") do |key|
      key =~ /^searches:(.+)/
      query = $1
      LOGGER.info "updating #{query}"
      resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", query: {login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: "#{query} date:>#{min_date}", limit: configatron.max_posts_per_search})

      if resp.code == 200
        posts = JSON.parse(resp.body)
        data = []
        LOGGER.info "  results #{posts.size}"
        posts.each do |post|
          data << post['id']
          data << post['id']
        end
        if data.any?
          REDIS.zadd "searches:#{query}", data
        end
        REDIS.zremrangebyrank "searches:#{query}", 0, -configatron.max_posts_per_search
      end
    end
  end

  def clean_searches
    while true
      item = REDIS.lpop("searches/clean")
      break if item.nil?

      if item =~ /^g:(\d+):(.+)/
        user_id = $1
        name = nil
        query = $2
      elsif item =~ /^n:(\d+):(.+?)\x1f(.+)/
        user_id = $1
        name = $2
        query = $3
      else
        next
      end

      LOGGER.info "cleaning #{user_id} #{query}"

      REDIS.zremrangebyrank "searches/user:#{user_id}", 0, -configatron.max_posts_per_search
      REDIS.expire("searches/user:#{user_id}", 60 * 60)

      if name
        REDIS.zremrangebyrank "searches/user:#{user_id}:#{name}", 0, -configatron.max_posts_per_search
        REDIS.expire("searches/user:#{user_id}:name", 60 * 60)
      end

      if REDIS.zcard("searches:#{query}") == 0
        REDIS.sadd "searches/initial", query
      else
        REDIS.expire("searches:#{query}", configatron.cache_expiry)
      end
    end
  end
end

processor = Processor.new
processor.initialize_searches if $options[:init]
processor.update_searches if $options[:update]
processor.clean_searches if $options[:clean]
