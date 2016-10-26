require "dotenv"
Dotenv.load

require "sinatra"
require "digest/md5"
require "configatron"
require "redis"
require "json"
require "logger"
require "aws-sdk"
require "./config/config"

REDIS = Redis.new
LOGFILE = ENV["LOG"] || "/var/log/listbooru/listbooru.log"
LOGGER = Logger.new(LOGFILE, 0)
SQS = Aws::SQS::Client.new(
  credentials: Aws::Credentials.new(
    configatron.amazon_key,
    configatron.amazon_secret
  ),
  region: configatron.sqs_region
)

helpers do
  def in_groups_of(array, number, fill_with = nil)
    if number.to_i <= 0
      raise ArgumentError,
        "Group size must be a positive integer, was #{number.inspect}"
    end

    if fill_with == false
      collection = array
    else
      # size % number gives how many extra we have;
      # subtracting from number gives how many to add;
      # modulo number ensures we don't add group of just fill.
      padding = (number - array.size % number) % number
      collection = array.dup.concat(Array.new(padding, fill_with))
    end

    if block_given?
      collection.each_slice(number) { |slice| yield(slice) }
    else
      collection.each_slice(number).to_a
    end
  end

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
    LOGGER.error(e.to_s)
    LOGGER.error(e.backtrace.join("\n"))
  end

  def send_sqs_messages(strings, options = {})
    in_groups_of(strings, 10) do |batch|
      entries = batch.compact.map do |x| 
        options.merge(message_body: x, id: CityHash.hash64(x).to_s)
      end

      SQS.send_message_batch(queue_url: configatron.sqs_url, entries: entries)
    end
  rescue Exception => e
    LOGGER.error(e.to_s)
    LOGGER.error(e.backtrace.join("\n"))
  end

  def aggregate_global(user_id)
    queries = REDIS.smembers("users:#{user_id}")
    limit = configatron.max_posts_per_search

    if queries.any? && !REDIS.exists("searches/user:#{user_id}")
      REDIS.zunionstore "searches/user:#{user_id}", queries.map {|x| "searches:#{x}"}
      send_sqs_messages(queries.map {|x| "clean global\n#{user_id}\n#{x}"})
    end

    REDIS.zrevrange("searches/user:#{user_id}", 0, limit)
  end

  def aggregate_named(user_id, name)
    queries = REDIS.smembers("users:#{user_id}:#{name}")
    limit = configatron.max_posts_per_search

    if queries.any? && !REDIS.exists("searches/user:#{user_id}:#{name}")
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

