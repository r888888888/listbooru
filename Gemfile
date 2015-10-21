source "https://rubygems.org"

gem "sinatra", github: "sinatra/sinatra"
gem "json"
gem "redis"
gem "capistrano"
gem "httparty"
gem "configatron"
gem "whenever"

group :production do
  gem 'unicorn', :platforms => :ruby
  gem 'capistrano-rbenv'
  gem 'capistrano3-unicorn', :require => false
  gem 'capistrano-bundler'
end
