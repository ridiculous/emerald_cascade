# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'spec_helper'
require_relative 'dummy/config/environment'
require 'rspec/rails'

# The engine owns no tables; the dummy app provides a throwaway one just so the specs can
# exercise the submission lifecycle against a real ActiveRecord model.
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :feedbacks, force: true do |t|
    t.string :state
    t.datetime :completed_at
    t.string :attendee_name
    t.integer :rating
    t.boolean :catered, default: false
    t.boolean :finalized, default: false
    t.timestamps
  end
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
end
