set :application, "listbooru"
set :repo_url, "git://github.com/r888888888/listbooru.git"
set :deploy_to, "/var/www/listbooru"
set :scm, :git
set :rbenv_ruby, "2.1.3"
set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp/pids', 'tmp/sockets')
