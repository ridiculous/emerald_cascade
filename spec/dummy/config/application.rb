# frozen_string_literal: true

require 'logger'
require 'rails/all'

Bundler.require(*Rails.groups)

# Minimal host application for the engine's test suite. Rails discovers EmeraldCascade::Engine
# (required via the gemspec) and mounts its app/ paths, exactly as a real host would.
module Dummy
  class Application < Rails::Application
    # Pin the root to this dummy app; otherwise Rails walks up and finds the host app,
    # loading its environment config and initializers.
    config.root = File.expand_path('..', __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.secret_key_base = 'emerald_cascade_dummy_secret'
    config.logger = Logger.new(IO::NULL)
    config.active_support.report_deprecations = false
  end
end
