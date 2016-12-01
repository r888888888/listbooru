require "dotenv"
Dotenv.load

require "date"
require "digest/md5"
require "redis"
require "httparty"
require "logger"
require 'optparse'

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
  resp = HTTParty.get("#{ENV["LISTBOORU_DANBOORU_SERVER"]}/posts.json", query: {login: ENV["LISTBOORU_DANBOORU_USER"], api_key: ENV["LISTBOORU_DANBOORU_API_KEY"], tags: "#{query} date:>#{min_date}", limit: ENV["MAX_POSTS_PER_SEARCH"].to_i, ro: true})

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
    REDIS.zremrangebyrank "searches:#{query}", 0, -ENV["MAX_POSTS_PER_SEARCH"].to_i
  end
  sleep 1
end
