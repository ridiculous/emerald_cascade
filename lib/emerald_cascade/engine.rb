# frozen_string_literal: true

module EmeraldCascade
  # Behavior-only engine: it ships concerns, POROs, controllers, jobs, and view partials,
  # but owns no database tables, routes, initializers, or assets. It exists as an engine
  # (rather than a plain gem) for exactly one reason: Rails automatically adds its `app/`
  # tree to the host's autoload/eager-load paths and its `app/views` to the view lookup
  # path, so the host can render `emerald_cascade/*` partials with zero wiring. There are
  # no routes or tables, so `isolate_namespace` would be a no-op and is intentionally omitted.
  class Engine < ::Rails::Engine
  end
end
