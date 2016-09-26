require "date"
require "digest/md5"
require "redis"
require "configatron"
require "httparty"
require "logger"
require 'optparse'
require "./config/config"

$options = {
  logfile: "/var/log/listbooru/processor.log"
}

OptionParser.new do |opts|
  opts.on("--logfile=LOGFILE") do |logfile|
    $options[:logfile] = logfile
  end
end.parse!

REDIS = Redis.new
LOGFILE = File.open($options[:logfile], "a")
LOGFILE.sync = true
LOGGER = Logger.new(LOGFILE, 0)

min_date = (Date.today - 3).strftime("%Y-%m-%d")

REDIS.scan_each(match: "searches:*") do |key|
  key =~ /^searches:(.+)/
  query = $1
  LOGGER.info "updating #{query}"
  resp = HTTParty.get("#{configatron.danbooru_server}/posts.json", query: {login: configatron.danbooru_user, api_key: configatron.danbooru_api_key, tags: "#{query} date:>#{min_date}", limit: configatron.max_posts_per_search, ro: true})

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
    end
    REDIS.zremrangebyrank "searches:#{query}", 0, -configatron.max_posts_per_search
  end
  sleep 1
end
