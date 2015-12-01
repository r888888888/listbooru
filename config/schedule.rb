every 4.hours do
  command "cd /var/www/listbooru/current && bundle exec ruby listbooru_processor.rb"
end
