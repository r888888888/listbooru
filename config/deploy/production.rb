set :rails_env, "production"

server "miura.donmai.us", :user => "danbooru", :roles => %w(web app db)
