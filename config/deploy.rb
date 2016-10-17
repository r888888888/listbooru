set :application, "listbooru"
set :repo_url, "git://github.com/r888888888/listbooru.git"
set :deploy_to, "/var/www/listbooru"
set :scm, :git
set :rbenv_type, :user
set :rbenv_ruby, "2.3.1"
set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp/pids', 'tmp/sockets')
set :linked_files, fetch(:linked_files, []).push("config/application.yml")
