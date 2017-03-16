require "dotenv"
Dotenv.load

require "sinatra"
require "digest/md5"
require "redis"
require "json"
require "aws-sdk"
require "cityhash"

set :port, ENV["SINATRA_PORT"]

REDIS = Redis.new
SQS = Aws::SQS::Client.new(
  credentials: Aws::Credentials.new(
    ENV["AMAZON_KEY"],
    ENV["AMAZON_SECRET"]
  ),
  region: ENV["AWS_REGION"]
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
        queue_url: ENV["LISTBOORU_SQS_URL"]
      )
    )
  rescue Exception => e
    logger.error(e.to_s)
    logger.error(e.backtrace.join("\n"))
  end

  def send_sqs_messages(strings, options = {})
    in_groups_of(strings, 100) do |batch|
      entries = batch.compact.map do |x| 
        options.merge(message_body: x, id: CityHash.hash64(x).to_s)
      end

      SQS.send_message_batch(queue_url: ENV["LISTBOORU_SQS_URL"], entries: entries)
    end
  rescue Exception => e
    logger.error(e.to_s)
    logger.error(e.backtrace.join("\n"))
  end

  def aggregate_searches(queries)
    send_sqs_messages(queries.map {|x| "initialize\n#{x}"})
    key = "searches-agg:" + CityHash.hash64(queries.join(" ")).to_s(36)

    if !REDIS.exists(key)
      REDIS.zunionstore key, queries.map {|x| "searches:#{x}"}
      REDIS.expire key, 3600
    end

    REDIS.zrevrange(key, 0, ENV["MAX_POSTS_PER_SEARCH"].to_i)
  end
end

get "/" do
  redirect "/index.html"
end

post "/v2/search" do
  request.body.rewind
  json = JSON.parse(request.body.read)
  if json["key"] != ENV["LISTBOORU_AUTH_KEY"]
    halt 401
  else
    queries = json["queries"]
    aggregate_searches(queries).join(" ")
  end
end
