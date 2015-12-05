require "date"
require "digest/md5"
require "redis"
require "configatron"
require "httparty"
require "logger"
require "./config/config"

REDIS = Redis.new
LOGGER = Logger.new(STDOUT)

def initialize_searches
  LOGGER.info "Initializing searches"

  while true
    query = REDIS.spop("searches/initial")
    break if query.nil?

    if REDIS.zcard("searches:#{query}") == 0
      resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", query: {login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: query, limit: configatron.max_posts_per_search})

      if resp.code == 200
        posts = JSON.parse(resp.body)
        LOGGER.info "  #{query}: #{posts.size}"
        data = []
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
  LOGGER.info "Updating searches"
  cursor = 0
  min_date = (Date.today - 3).strftime("%Y-%m-%d")

  REDIS.scan_each(match: "searches:*") do |key|
    key =~ /^searches:(.+)/
    query = $1
    resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", query: {login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: "#{query} date:>#{min_date}", limit: configatron.max_posts_per_search})

    if resp.code == 200
      posts = JSON.parse(resp.body)
      data = []
      LOGGER.info "  #{query}: #{posts.size}"
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
  LOGGER.info "Cleaning searches"

  1_000.times do
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

    LOGGER.info "  user_id=#{user_id} name=#{name} query=#{query}"

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

initialize_searches
update_searches
clean_searches