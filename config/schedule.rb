every 1.hour do
  command "flock -n -E 0 /tmp/listbooru_updater.lock -c 'cd /var/www/listbooru/current && bundle exec ruby listbooru_updater.rb'"
end
