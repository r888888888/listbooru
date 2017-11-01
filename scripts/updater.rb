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

def process_update(key, n = 1)
  key =~ /^searches:(.+)/
  query = $1
  LOGGER.info "updating #{query}"
  resp = HTTParty.get("#{ENV["LISTBOORU_DANBOORU_SERVER"]}/posts.json", query: {login: ENV["LISTBOORU_DANBOORU_USER"], api_key: ENV["LISTBOORU_DANBOORU_API_KEY"], tags: query, limit: ENV["MAX_POSTS_PER_SEARCH"].to_i, ro: true})

  if resp.code == 200
    posts = JSON.parse(resp.body)
    data = []
    LOGGER.info "  results #{posts.size}"
    posts.each do |post|
      data << post['id']
      data << post['id']
    end
    REDIS.del(key)
    if data.any?
      REDIS.zadd key, data
    end
  else
    LOGGER.error "  failed: received #{resp.code}\n  #{resp.body}"
    if n >= 5
      LOGGER.error "  giving up"
    else
      delay = (n ** 2) * 10
      LOGGER.error "  retrying after #{delay}s"
      sleep(delay)
      process_update(key, n + 1)
    end
  end
end

REDIS.scan_each(match: "searches:*") do |key|
  process_update(key)
end
