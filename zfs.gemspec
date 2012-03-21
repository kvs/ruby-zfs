# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rake'

Gem::Specification.new do |s|
	s.name        = "zfs"
	s.version     = "0.1.0"
	s.platform    = Gem::Platform::RUBY
	s.authors     = %w(kvs)
	s.email       = %w(kvs@binarysolutions.dk)
	s.homepage    = "https://github.com/kvs/ruby-zfs"
	s.summary     = "An library for interacting with ZFS"
	s.description = %q{Makes it possible to query and manipulate ZFS filesystems, snapshots, etc.}

	s.files            = `git ls-files`.split("\n")
	s.test_files       = `git ls-files -- {test,spec,features}/*`.split("\n")
	s.executables      = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
	s.require_paths    = ["lib"]

	s.add_development_dependency "rspec", ["~> 2.8.0"]
	s.add_development_dependency "guard-rspec"
	s.add_development_dependency "guard-bundler"
	s.add_development_dependency "rake"
	s.add_development_dependency "vagrant"
	s.add_development_dependency "vagrant-proxyssh"
end
