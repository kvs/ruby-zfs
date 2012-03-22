# -*- mode: ruby; tab-width: 2; indent-tabs-mode: nil -*-

desc "Install gem bundle inside Vagrant VM"
task :bundle do
  exec "ssh", "-t", "vagrant", "source /etc/profile && cd /vagrant && bundle install --path .bundle --without vagrant"
end

desc "Login to Vagrant, and run 'guard'"
task :guard do
  exec "ssh", "-t", "vagrant", 'source /etc/profile && cd /vagrant && bundle exec guard -c'
end
