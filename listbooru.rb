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
    return "no-matches" if tokens.size == 0
    return "no-matches" if tokens.any? {|x| x =~ /\*/}
    return "no-matches" if tokens.all? {|x| x =~ /^-/}
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

  def aggregate_global(user_id, start, stop)
    queries = REDIS.smembers("users:#{user_id}")

    if queries.any? && REDIS.zcard("searches/user:#{user_id}") == 0
      REDIS.zunionstore "searches/user:#{user_id}", queries.map {|x| "searches:#{x}"}

      REDIS.pipelined do
        queries.each do |query|
          REDIS.rpush("searches/clean", "g:#{user_id}:#{query}")
        end
      end
    end

    REDIS.zrevrange("searches/user:#{user_id}", start, stop)
  end

  def aggregate_named(user_id, name, start, stop)
    queries = REDIS.smembers("users:#{user_id}:#{name}")

    if queries.any? && REDIS.zcard("searches/user:#{user_id}:#{name}") == 0
      REDIS.zunionstore "searches/user:#{user_id}:#{name}", queries.map {|x| "searches:#{x}"}

      REDIS.pipelined do
        queries.each do |query|
          REDIS.rpush("searches/clean", "n:#{user_id}:#{name}\x1f#{query}")
        end
      end
    end

    REDIS.zrevrange("searches/user:#{user_id}:#{name}", start, stop)
  end
end

before do
  if params["key"] != configatron.auth_key
    halt 401
  end
end

get "/users" do
  user_id = params["user_id"]
  name = params["name"]
  start, stop = extract_start_stop(params)

  if name
    results = aggregate_named(user_id, name, start, stop)
  else
    results = aggregate_global(user_id, start, stop)
  end

  results.to_json
end

delete "/searches" do
  user_id = params["user_id"]
  query = normalize_query(params["query"])
  name = params["name"]

  REDIS.srem("users:#{user_id}", query)
  REDIS.srem("users:#{user_id}:#{name}") if name

  ""
end

post "/searches" do
  user_id = params["user_id"]
  query = normalize_query(params["query"])
  name = params["name"]

  if REDIS.scard("users:#{user_id}") > configatron.max_searches_per_user
    halt 409
  else
    REDIS.sadd("searches/initial", query) if REDIS.zcard("searches:#{query}") == 0
    REDIS.sadd("users:#{user_id}:#{name}", query) if name
    REDIS.sadd("users:#{user_id}", query)
  end

  ""
end

put "/searches" do
  user_id = params["user_id"]
  new_query = normalize_query(params["new_query"])
  new_name = params["new_name"]
  old_query = normalize_query(params["old_query"])
  old_name = params["old_name"]

  if old_query
    REDIS.srem("users:#{user_id}", old_query)
    REDIS.sadd("users:#{user_id}", new_query)
  end

  if old_name
    REDIS.srem("users:#{user_id}:#{old_name}", old_query || new_query)
    REDIS.sadd("users:#{user_id}:#{new_name}", new_query)
  end

  REDIS.sadd("searches/initial", new_query) if REDIS.zcard("searches:#{new_query}") == 0
end
