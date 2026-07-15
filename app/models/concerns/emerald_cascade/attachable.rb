# frozen_string_literal: true

module EmeraldCascade
  # Gives a host attachment model (which owns its own table + Paperclip/ActiveStorage
  # declaration) a background "processing" lifecycle: it is uploaded, then a processor
  # reads it and stores a structured result (e.g. OCR of a scanned sheet). The host maps
  # the generic status/result onto its own columns via `emerald_cascade_attachable`, so the
  # table and storage paths stay unchanged.
  module Attachable
    extend ActiveSupport::Concern

    STATUSES = { pending: 'pending', processing: 'processing', complete: 'complete', failed: 'failed' }.freeze

    included do
      class_attribute :emerald_cascade_attachable_config, instance_writer: false, default: {}
    end

    class_methods do
      # @param status [Symbol] host column holding the lifecycle status (string-backed)
      # @param result [Symbol] host column holding the structured result
      # @param processor [String] name of a class exposing `#call(record) => result`
      # @param position_scope [Symbol, nil] FK column to scope append-order `position` within
      # @param rescue_from [Class] processor error treated as a soft failure (else re-raised)
      # @param status_prefix [Symbol] enum method prefix (e.g. `processing_pending?`)
      def emerald_cascade_attachable(status:, result:, processor:, position_scope: nil,
                                     rescue_from: StandardError, status_prefix: :processing)
        self.emerald_cascade_attachable_config = {
          status: status, result: result, processor: processor,
          position_scope: position_scope, rescue_from: rescue_from
        }
        enum status, STATUSES, prefix: status_prefix
        alias_attribute :processing_status, status
        alias_attribute :processing_result, result
        before_create :assign_emerald_cascade_position if position_scope
      end

      # Aggregate lifecycle across a set of records, for a status line:
      #   :reading (some still queued/processing), :failed (some couldn't be read),
      #   :done (all read), or nil (none are tracked).
      def processing_state(records)
        tracked = records.select { |r| r.processing_status.present? }
        return if tracked.empty?
        return :reading if tracked.any? { |r| r.processing_status.in?(%w[pending processing]) }
        return :failed if tracked.any? { |r| r.processing_status == 'failed' }

        :done
      end
    end

    # Mark queued and run the processor in the background via the default engine job.
    def process_async!
      update_column(emerald_cascade_attachable_config[:status], STATUSES[:pending])
      EmeraldCascade::ProcessAttachmentJob.perform_later(self.class.name, id)
    end

    # Run the processor now: mark processing, store its result, mark complete. A configured
    # processor error is logged and marks the record failed; anything else propagates so a
    # genuine bug surfaces via the job runner.
    def emerald_cascade_process!
      cfg = emerald_cascade_attachable_config
      update_column(cfg[:status], STATUSES[:processing])
      result = cfg[:processor].constantize.new.call(self)
      update_columns(cfg[:result] => result, cfg[:status] => STATUSES[:complete])
    rescue cfg[:rescue_from] => e
      Rails.logger.warn "[EmeraldCascade::Attachable] #{self.class}##{id} failed: #{e.message}"
      update_column(cfg[:status], STATUSES[:failed])
    end

    private

    def assign_emerald_cascade_position
      return if position.present?

      scope_col = emerald_cascade_attachable_config[:position_scope]
      max = self.class.where(scope_col => self[scope_col]).maximum(:position) || 0
      self.position = max + 1
    end
  end
end
