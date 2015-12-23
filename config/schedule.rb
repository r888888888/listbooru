every 3.hours do
  command "flock /tmp/listbooru_processor.lock -c 'cd /var/www/listbooru/current && bundle exec ruby listbooru_processor.rb'"
end

every 1.hour do
  command "flock /tmp/listbooru_sqs_processor.lock -c 'cd /var/www/listbooru/current && bundle exec ruby listbooru_sqs_processor.rb'"
end
