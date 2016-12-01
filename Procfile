web: bundle exec ruby web/listbooru.rb
sqs: RUN=1 bundle exec ruby services/sqs_processor.rb --pidfile=/Users/ayi/Development/.listbooru/tmp/sqs.pid --logfile=stdout
redis: /usr/local/bin/redis-server
