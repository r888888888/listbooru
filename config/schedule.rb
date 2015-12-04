every 3.hours do
  command "cd /var/www/listbooru/current && bundle exec ruby listbooru_processor.rb"
end
