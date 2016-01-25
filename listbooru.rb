require "sinatra"
require "digest/md5"
require "configatron"
require "redis"
require "json"
require "logger"
require "./config/config"

REDIS = Redis.new
LOGGER = Logger.new("/var/log/listbooru/sqs_processor.log", "a"))
SQS = Aws::SQS::Client.new(
  credentials: Aws::Credentials.new(
    configatron.amazon_key,
    configatron.amazon_secret
  ),
  region: configatron.sqs_region
)

helpers do
  def normalize_query(query)
    tokens = query.downcase.scan(/\S+/)
    return "no-matches" if tokens.size == 0
    return "no-matches" if tokens.any? {|x| x =~ /\*/}
    return "no-matches" if tokens.all? {|x| x =~ /^-/}
    tokens.join(" ")
  end

  def send_sqs_message(string, options = {})
    SQS.send_message(
      options.merge(
        message_body: string,
        queue_url: configatron.sqs_url
      )
    )
  rescue Exception => e
    LOGGER.error(e.message)
    LOGGER.error(e.backtrace.join("\n"))
  end

  def send_sqs_messages(strings, options = {})
    strings.in_groups_of(10).each do |batch|
      SQS.batch_send(batch.compact.map {|x| options.merge(message_body: x)})
    end
  rescue Exception => e
    LOGGER.error(e.message)
    LOGGER.error(e.backtrace.join("\n"))
  end

  def aggregate_global(user_id)
    queries = REDIS.smembers("users:#{user_id}")
    limit = configatron.max_posts_per_search

    if queries.any? && REDIS.zcard("searches/user:#{user_id}") == 0
      REDIS.zunionstore "searches/user:#{user_id}", queries.map {|x| "searches:#{x}"}
      send_sqs_messages(queries.map {|x| "clean global\n#{user_id}\n#{x}"})
    end

    REDIS.zrevrange("searches/user:#{user_id}", 0, limit)
  end

  def aggregate_named(user_id, name)
    queries = REDIS.smembers("users:#{user_id}:#{name}")
    limit = configatron.max_posts_per_search

    if queries.any? && REDIS.zcard("searches/user:#{user_id}:#{name}") == 0
      REDIS.zunionstore "searches/user:#{user_id}:#{name}", queries.map {|x| "searches:#{x}"}
      send_sqs_messages(queries.map {|x| "clean named\n#{user_id}\n#{name}\n#{x}"})
    end

    REDIS.zrevrange("searches/user:#{user_id}:#{name}", 0, limit)
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

  if name
    results = aggregate_named(user_id, name)
  else
    results = aggregate_global(user_id)
  end

  results.to_json
end

