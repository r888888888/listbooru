#!/home/danbooru/.rbenv/shims/ruby

require "redis"
require "configatron"
require "logger"
require "aws-sdk"
require 'optparse'
require "./config/config"

Process.daemon

$running = true
$options = {
  pidfile: "/var/run/listbooru/sqs_processor.pid",
  logfile: "/var/log/listbooru/sqs_processor.log"
}

OptionParser.new do |opts|
  opts.on("--pidfile=PIDFILE") do |pidfile|
    $options[:pidfile] = pidfile
  end

  opts.on("--logfile=LOGFILE") do |logfile|
    $options[:logfile] = logfile
  end
end.parse!

LOGFILE = File.open($options[:logfile], "a")
LOGFILE.sync = true
LOGGER = Logger.new(LOGFILE)
REDIS = Redis.new
Aws.config.update(
  region: configatron.sqs_region,
  credentials: Aws::Credentials.new(
    configatron.amazon_key,
    configatron.amazon_secret
  )
)
SQS = Aws::SQS::Client.new
QUEUE = Aws::SQS::QueuePoller.new(configatron.sqs_url, client: SQS)

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

  while $running
    begin
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

        when "clean global"
          process_global_clean(tokens)

        when "clean named"
          process_named_clean(tokens)

        end
      end
    rescue Exception => e
      LOGGER.error(e.message)
      LOGGER.error(e.backtrace.join("\n"))
      sleep(60)
      retry
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
  LOGGER.info tokens.join(" ")

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
  LOGGER.info tokens.join(" ")

  user_id = tokens[1]
  category = tokens[2]
  query = normalize_query(tokens[3])

  if REDIS.scard("users:#{user_id}") < configatron.max_searches_per_user
    REDIS.sadd("searches/initial", query) unless REDIS.exists("searches:#{query}")
    REDIS.sadd("users:#{user_id}:#{category}", query) if category
    REDIS.sadd("users:#{user_id}", query)
  end
end

def process_refresh(tokens)
  LOGGER.info tokens.join(" ")

  user_id = tokens[1]
  REDIS.sscan_each("users:#{user_id}") do |query|
    REDIS.expire("searches:#{query}", configatron.cache_expiry)
  end
end

def process_update(tokens)
  LOGGER.info tokens.join(" ")

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

  REDIS.sadd("searches/initial", new_query) unless REDIS.exists("searches:#{new_query}")
end

def process_global_clean(tokens)
  LOGGER.info tokens.join(" ")

  user_id = tokens[1]
  query = tokens[2]

  REDIS.zremrangebyrank "searches/user:#{user_id}", 0, -configatron.max_posts_per_search
  REDIS.expire("searches/user:#{user_id}", 60 * 60)

  if REDIS.exists("searches:#{query}")
    REDIS.expire("searches:#{query}", configatron.cache_expiry)
  else
    REDIS.sadd "searches/initial", query
  end
end

def process_named_clean(tokens)
  LOGGER.info tokens.join(" ")

  user_id = tokens[1]
  name = tokens[2]
  query = tokens[3]

  REDIS.zremrangebyrank "searches/user:#{user_id}", 0, -configatron.max_posts_per_search
  REDIS.expire("searches/user:#{user_id}", 60 * 60)
  REDIS.zremrangebyrank "searches/user:#{user_id}:#{name}", 0, -configatron.max_posts_per_search
  REDIS.expire("searches/user:#{user_id}:name", 60 * 60)

  if REDIS.exists("searches:#{query}")
    REDIS.expire("searches:#{query}", configatron.cache_expiry)
  else
    REDIS.sadd "searches/initial", query
  end
end

process_queue(QUEUE)