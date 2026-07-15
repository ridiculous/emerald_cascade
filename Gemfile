# frozen_string_literal: true

source 'https://rubygems.org'

# Runtime dependencies (rails, state_machines-activerecord) come from the gemspec.
gemspec

group :development, :test do
  gem 'rspec-rails', '~> 7.0'
  gem 'sqlite3', '>= 1.4'
end

group :development do
  gem 'rubocop', '~> 1.86', require: false
  gem 'rubocop-rails', '~> 2.34', require: false
end
