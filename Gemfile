# A sample Gemfile
source "https://rubygems.org"

gemspec

#gem 'travis-support', github: 'travis-ci/travis-support'
gem 'travis-support', github: 'final-ci/travis-support'
#gem 'travis-support', path: '../travis-support'
gem 'travis-config', '~> 0.1.0'
gem 'sinatra'
gem 'sinatra-contrib'
gem 'rack-contrib'     # github: 'rack/rack-contrib'
gem 'rack-parser',     github: 'lksv/rack-parser', branch: 'fix_json_array', require: 'rack/parser'
gem 'multi_json', '~> 1.0'
gem 'activesupport', '~> 4.2.3'

#gem 'celluloid'

gem 'metriks',         '0.9.9.6'
gem 'metriks-librato_metrics', github: 'eric/metriks-librato_metrics'

gem 'nokogiri'
gem 'redis', '~>3.2'

group :test do
  gem 'rspec'
  gem 'faraday'
  gem 'json-schema'
  gem 'factory_girl',     '~> 2.6.0'
  gem 'database_cleaner', '~> 1.4.1'
  gem 'codeclimate-test-reporter', require: nil
end

group :development do
  gem 'racksh'
  gem 'pry'
  gem 'pry-doc',       '~> 0.6.0'
  gem 'method_source', '~> 0.8.2'
end

platform :mri do
  gem 'bunny'
end

platform :jruby do
  gem 'march_hare',     '~> 2.7.0'
end

gem 'puma', '3.0.0'

