every 30.minutes do
  command "cd /var/www/listbooru/current && bundle exec ruby listbooru_processor.rb"
end
