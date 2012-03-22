# -*- mode: ruby; tab-width: 2; indent-tabs-mode: nil -*-

eval(File.read(".guard_private")) if File.exist?('.guard_private')

guard 'rspec', :version => 2, :cli => '--color' do
  watch(/^spec\/(.*)_spec.rb/)
  watch(/^lib\/(.*)\.rb/)         { |m| "spec/#{m[1]}_spec.rb" }
  watch(/^spec\/spec_helper.rb/)  { "spec" }
end

guard 'bundler' do
  watch('Gemfile')
end
