require 'uri'

LISTBOORU_SERVER = URI.parse("http://miura.donmai.us/searches")
LISTBOORU_KEY = ENV["LISTBOORU_AUTH_KEY"]

TagSubscription.where("last_accessed_at >= ?", 3.months.ago).find_each do |sub|
  user_id = sub.creator_id
  sub.tag_query.split.each do |query|
    puts "#{user_id}:#{sub.name}:#{query}"
    resp = Net::HTTP.post_form(LISTBOORU_SERVER, {"user_id" => user_id, "query" => query, "name" => sub.name, "key" => LISTBOORU_KEY})
  end
end

SavedSearch.find_each do |ss|
  Net::HTTP.post_form(LISTBOORU_KEY, {"user_id" => ss.user_id, "query" => ss.query, "key" => LISTBOORU_KEY})
end
