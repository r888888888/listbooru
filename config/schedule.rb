every 4.hours do
  command "flock -n -E 0 /tmp/listbooru_updater-update.lock -c 'cd /var/www/listbooru/current && bundle exec ruby scripts/updater.rb'"
end
