# frozen_string_literal: true

module EmeraldCascade
  # Base class for the engine's own background jobs. Inherits ActiveJob::Base directly
  # (rather than the host's top-level ApplicationJob) so the engine stays self-contained;
  # a host that wants its own job conventions enqueues its own job instead.
  class ApplicationJob < ActiveJob::Base
  end
end
