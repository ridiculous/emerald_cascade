# frozen_string_literal: true

require_relative 'lib/emerald_cascade/version'

Gem::Specification.new do |spec|
  spec.name        = 'emerald_cascade'
  spec.version     = EmeraldCascade::VERSION
  spec.authors     = ['Lish']
  spec.summary     = 'Generic, storage-agnostic multi-step form engine.'
  spec.description = 'EmeraldCascade is a behavior-only Rails engine for multi-step forms: ' \
                     'a definition DSL, a submission lifecycle/state machine, step navigation, ' \
                     'rendering, and attachments. The host app owns the tables, admin, and integrations.'
  spec.homepage    = 'https://lishfood.com'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['{app,config,db,lib}/**/*', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '>= 7.1'
  # State machine DSL behind EmeraldCascade::Submittable. Often already present in a host
  # (e.g. pulled in by Solidus); declared explicitly so the engine resolves on its own.
  spec.add_dependency 'state_machines-activerecord', '>= 0.6'
end
