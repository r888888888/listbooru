require 'uri'

LISTBOORU_SERVER = URI.parse("http://miura.donmai.us/searches")
LISTBOORU_KEY = ENV["LISTBOORU_AUTH_KEY"]

SavedSearch.find_each do |ss|
  puts "#{ss.user_id}:#{ss.tag_query}:#{ss.category}"
  Net::HTTP.post_form(LISTBOORU_SERVER, {"user_id" => ss.user_id, "query" => ss.tag_query, "key" => LISTBOORU_KEY, "name" => ss.category})
end
