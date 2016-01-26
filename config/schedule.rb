every 1.hour do
  command "flock -n -E 0 /tmp/listbooru_updater-init.lock -c 'cd /var/www/listbooru/current && bundle exec ruby listbooru_updater.rb --action=init'"
end

every 4.hours do
  command "flock -n -E 0 /tmp/listbooru_updater-update.lock -c 'cd /var/www/listbooru/current && bundle exec ruby listbooru_updater.rb --action=update'"
end
