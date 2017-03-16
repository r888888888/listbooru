#!/usr/bin/env ruby

require "dotenv"
Dotenv.load

require "redis"
require "logger"
require "aws-sdk"
require 'optparse'
require "httparty"

unless ENV["RUN"]
  Process.daemon
end

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

LOGFILE = $options[:logfile] == "stdout" ? STDOUT : File.open($options[:logfile], "a")
LOGFILE.sync = true
LOGGER = Logger.new(LOGFILE, 0)
REDIS = Redis.new
Aws.config.update(
  region: ENV["LISTBOORU_SQS_REGION"],
  credentials: Aws::Credentials.new(
    ENV["AMAZON_KEY"],
    ENV["AMAZON_SECRET"]
  )
)
SQS = Aws::SQS::Client.new
QUEUE = Aws::SQS::QueuePoller.new(ENV["LISTBOORU_SQS_URL"], client: SQS)

File.open($options[:pidfile], "w") do |f|
  f.write(Process.pid)
end

Signal.trap("TERM") do
  $running = false
end

def send_sqs_message(string, options = {})
  SQS.send_message(
    options.merge(
      message_body: string,
      queue_url: ENV["LISTBOORU_SQS_URL"]
    )
  )
rescue Exception => e
  LOGGER.error(e.message)
  LOGGER.error(e.backtrace.join("\n"))
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
        when "initialize"
          process_initialize(tokens)

        end
      end
    rescue Interrupt
      exit(0)

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

def process_initialize(tokens)
  LOGGER.info tokens.join(" ")

  query = tokens[1]

  if !REDIS.exists("searches:#{query}")
    resp = HTTParty.get("#{ENV['LISTBOORU_DANBOORU_SERVER']}/posts.json", query: {login: ENV["LISTBOORU_DANBOORU_USER"], api_key: ENV["LISTBOORU_DANBOORU_API_KEY"], tags: query, limit: ENV["MAX_POSTS_PER_SEARCH"].to_i, ro: true})
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
        REDIS.zremrangebyrank "searches:#{query}", 0, -ENV["MAX_POSTS_PER_SEARCH"].to_i
        REDIS.expire "searches:#{query}", ENV["CACHE_EXPIRY"].to_i
      end
    end
  end
end

process_queue(QUEUE)