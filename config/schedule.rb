every 3.hours do
  command "flock /tmp/listbooru_processor.lock -n -E 0 -c 'cd /var/www/listbooru/current && bundle exec ruby listbooru_processor.rb'"
end
