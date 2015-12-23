#!/home/danbooru/.rbenv/shims/ruby

require "redis"
require "configatron"
require "./config/config"
require "logger"
require "aws-sdk"
require 'optparse'

Process.daemon

LOGGER = Logger.new(STDOUT)
REDIS = Redis.new
Aws.config.update(
  region: "us-west-2",
  credentials: Aws::Credentials.new(
    configatron.amazon_key,
    configatron.amazon_secret
  )
)
SQS = Aws::SQS::Client.new
QUEUE = Aws::SQS::QueuePoller.new(configatron.sqs_url, client: SQS)
$running = true
$options = {
  pidfile: "/var/run/listbooru/ruby-service.pid"
}

OptionParser.new do |opts|
  opts.on("--pidfile") do |pidfile|
    $options[:pidfile] = pidfile
  end
end

File.open($options[:pidfile], "w") do |f|
  f.write(Process.pid)
end

Signal.trap("TERM") do
  $running = false
end

def process_queue(poller)
  poller.before_request do
    unless $running
      throw :stop_polling
    end
  end

  poller.poll do |msg|
    tokens = msg.body.split(/\n/)

    case tokens[0]
    when "delete"
      process_delete(tokens)

    when "create"
      process_create(tokens)

    when "refresh"
      process_refresh(tokens)

    when "update"
      process_update(tokens)
    end
  end
end

def normalize_query(query)
  tokens = query.downcase.scan(/\S+/)
  return "no-matches" if tokens.size == 0
  return "no-matches" if tokens.any? {|x| x =~ /\*/}
  return "no-matches" if tokens.all? {|x| x =~ /^-/}
  tokens.join(" ")
end

def process_delete(tokens)
  LOGGER.info "delete " + tokens.join(" ")

  user_id = tokens[1]
  category = tokens[2]
  query = tokens[3]

  if category == "all"
    REDIS.del("users:#{user_id}")
    REDIS.scan_each(match: "users:#{user_id}:*") do |key|
      REDIS.del(key)
    end
    REDIS.del("searches/user:#{user_id}")
  else
    query = normalize_query(query)
    REDIS.srem("users:#{user_id}", query)
    REDIS.srem("users:#{user_id}:#{category}", query) if category
  end
end

def process_create(tokens)
  LOGGER.info "create " + tokens.join(" ")

  user_id = tokens[1]
  category = tokens[2]
  query = normalize_query(tokens[3])

  if REDIS.scard("users:#{user_id}") < configatron.max_searches_per_user
    REDIS.sadd("searches/initial", query) if REDIS.zcard("searches:#{query}") == 0
    REDIS.sadd("users:#{user_id}:#{category}", query) if category
    REDIS.sadd("users:#{user_id}", query)
  end
end

def process_refresh(tokens)
  LOGGER.info "refresh " + tokens.join(" ")

  user_id = tokens[1]
  REDIS.expire("searches/user:#{user_id}", 60 * 60)
end

def process_update(tokens)
  LOGGER.info "update " + tokens.join(" ")

  user_id = tokens[1]
  old_category = tokens[2]
  old_query = normalize_query(tokens[3])
  new_category = tokens[4]
  new_query = normalize_query(tokens[5])

  if old_query
    REDIS.srem("users:#{user_id}", old_query)
    REDIS.sadd("users:#{user_id}", new_query)
  end

  if old_category
    REDIS.srem("users:#{user_id}:#{old_category}", old_query || new_query)
    REDIS.sadd("users:#{user_id}:#{new_category}", new_query)
  end

  REDIS.sadd("searches/initial", new_query) if REDIS.zcard("searches:#{new_query}") == 0
end

process_queue(QUEUE)