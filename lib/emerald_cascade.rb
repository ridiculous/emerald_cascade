# frozen_string_literal: true

require 'emerald_cascade/version'
require 'emerald_cascade/engine'

# EmeraldCascade::Submittable builds an ActiveRecord state machine, so the engine depends on
# this integration directly instead of assuming the host already loaded it (e.g. via Solidus).
# Requiring it here registers the ActiveRecord on-load hook that adds the `state_machine` macro.
require 'state_machines-activerecord'

# EmeraldCascade is a storage-agnostic, behavior-only multi-step form engine
# (named for Seattle's Emerald City and the Cascade Range; a "cascade" of steps).
#
# The host app supplies the tables, the form Definition, and the rendering shell
# (layout + CSS); the engine supplies the definition DSL, submission lifecycle,
# step navigation, and generic field-rendering partials.
module EmeraldCascade
end
