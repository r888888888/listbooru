require "sinatra"
require "digest/md5"
require "configatron"
require "redis"
require "json"
require "./config/config"

REDIS = Redis.new

helpers do
  def normalize_query(query)
    tokens = query.downcase.scan(/\S+/)
    tokens.reject! {|x| x =~ /\*/}
    return "no-matches" if tokens.size == 1 && tokens[0] =~ /^-/
    return "no-matches" if tokens.size == 0
    tokens.join(" ")
  end

  def extract_start_stop(params)
    page = (params["page"] || 1).to_i
    page = 1 if page < 1
    page = 10 if page > 10
    per_page = (params["per_page"] || 20).to_i
    per_page = 1 if per_page < 1
    per_page = 100 if per_page > 100
    start = (page - 1) * per_page
    stop = page * per_page
    [start, stop]
  end
end

before do
  if params["key"] != configatron.auth_key
    halt 401
  end
end

get "/users/:user_id/:name" do
  name = params["name"].downcase
  user_id = params["user_id"]
  queries = REDIS.smembers("users:#{user_id}:#{name}")
  start, stop = extract_start_stop(params)

  if queries.any? && REDIS.zcard("searches/user:#{user_id}:#{name}") == 0
    REDIS.zunionstore "searches/user:#{user_id}:#{name}", queries.map {|x| "searches:#{x}"}

    REDIS.pipelined do
      REDIS.expire("searches/user:#{user_id}:#{name}", configatron.cache_expiry)

      queries.each do |query|
        REDIS.rpush("searches/clean", "n:#{user_id}:#{name}\x1f#{query}")
      end
    end
  end

  results = REDIS.zrevrange("searches/user:#{user_id}", start, stop)
  results.to_json
end

get "/users/:user_id" do
  user_id = params["user_id"]
  queries = REDIS.smembers("users:#{user_id}")
  start, stop = extract_start_stop(params)
  results = []

  if queries.any? && REDIS.zcard("searches/user:#{user_id}") == 0
    REDIS.zunionstore "searches/user:#{user_id}", queries.map {|x| "searches:#{x}"}

    REDIS.pipelined do
      REDIS.expire("searches/user:#{user_id}", configatron.cache_expiry)

      queries.each do |query|
        REDIS.rpush("searches/clean", "g:#{user_id}:#{query}")
      end
    end
  end

  results = REDIS.zrevrange("searches/user:#{user_id}", start, stop)
  results.to_json
end

delete "/searches" do
  user_id = params["user_id"]
  query = normalize_query(params["query"])
  REDIS.srem("users:#{user_id}", query)
  ""
end

post "/searches" do
  user_id = params["user_id"]
  query = normalize_query(params["query"])
  name = params["name"]

  if REDIS.scard("users:#{user_id}") > configatron.max_searches_per_user
    halt 409
  else
    if REDIS.zcard("searches:#{query}") == 0
      REDIS.sadd("searches/initial", query)
    end

    REDIS.sadd("users:#{user_id}", query)

    if name
      REDIS.sadd("users:#{user_id}:#{name.downcase}", query)
    end
  end

  ""
end
