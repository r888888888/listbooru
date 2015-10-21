require "date"
require "digest/md5"
require "redis"
require "logger"
require "configatron"
require "httparty"
require "./config/config"

REDIS = Redis.new
LOGGER = Logger.new(STDOUT)

def initialize_searches
  LOGGER.info "Initializing searches"

  configatron.processor_iterations.times do
    query = REDIS.spop("searches/initial")
    break if query.nil?

    if REDIS.zcard("searches:#{query}") == 0
      resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: query, limit: 100)

      if resp.code == 200
        posts = JSON.parse(resp.body)
        data = []
        posts.each do |post|
          data << post['id']
        end
        REDIS.zadd "searches:#{query}", data
        REDIS.zremrangebyrank "searches:#{query}", 0, -configatron.max_posts_per_search
        REDIS.expire "searches:#{query}", configatron.cache_expiry
      end
    end
  end
end

def update_searches
  LOGGER.info "Updating searches"

  cursor = 0
  min_date = (Date.today - 3).strftime("%Y-%m-%d")

  configatron.processor_iterations.times do
    hit = REDIS.scan cursor, match: "searches:*"

    if hit[0] == "0"
      break
    else
      cursor = hit[0]
      keys = hit[1]
      keys.each do |key|
        LOGGER.info "  Searching #{key}"
        key =~ /^searches:(.+)/
        query = $1
        resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: "#{query} date:>#{min_date}", limit: 100)

        if resp.code == 200
          posts = JSON.parse(resp.body)
          data = []
          posts.each do |post|
            data << post['id']
          end
          REDIS.pipelined do
            REDIS.zadd "searches:#{query}", data
            REDIS.expire "searches:#{query}", configatrong.cache_expiry
            REDIS.zremrangebyrank "searches:#{query}", 0, -configatron.max_posts_per_search
          end
        end
      end
    end
  end
end

def clean_searches
  LOGGER.info "Cleaning searches"

  configatron.processor_iterations.times do
    item = REDIS.lpop("searches/clean")
    break if item.nil?
    
    item =~ /^(\d+):(.+)/
    user_id = $1
    query = $2

    if REDIS.scard("searches:#{query}") == 0
      REDIS.sadd "searches/initial", query
    else
      REDIS.expire("searches:#{query}", configatron.cache_expiry)
    end

    REDIS.zremrangebyrank "searches/user:#{user_id}", 0, -configatron.max_posts_per_search
  end
end

initialize_searches
update_searches
clean_searches