require 'uri'

LISTBOORU_SERVER = URI.parse("http://miura.donmai.us/searches")
LISTBOORU_KEY = ENV["LISTBOORU_AUTH_KEY"]

SavedSearch.find_each do |ss|
  Net::HTTP.post_form(LISTBOORU_KEY, {"user_id" => ss.user_id, "query" => ss.query, "key" => LISTBOORU_KEY})
end
