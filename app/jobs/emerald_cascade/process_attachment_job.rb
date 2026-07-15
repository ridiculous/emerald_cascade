# frozen_string_literal: true

module EmeraldCascade
  # Default background runner for EmeraldCascade::Attachable#process_async!. Hosts may
  # instead enqueue their own named job that calls #emerald_cascade_process! (e.g. to keep a
  # stable job name across a deploy, or to gate enqueueing on host policy); this is the
  # zero-config default. Subclasses the engine's own ApplicationJob, so it never depends on
  # the host defining a top-level ApplicationJob.
  class ProcessAttachmentJob < ApplicationJob
    queue_as :default

    def perform(class_name, id)
      class_name.constantize.find_by(id: id)&.emerald_cascade_process!
    end
  end
end
