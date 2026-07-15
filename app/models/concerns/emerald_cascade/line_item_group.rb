# frozen_string_literal: true

module EmeraldCascade
  # Mixed into a line-item model that belongs to a form submission and is edited as a
  # repeating group through nested attributes. It records the item's operator-editable
  # columns in one place so every place that permits nested params (the public step form and
  # the admin edit form) derives the same shape instead of hand-listing it. The host owns the
  # table, associations and any bespoke rendering of the group.
  module LineItemGroup
    extend ActiveSupport::Concern

    class_methods do
      attr_reader :emerald_cascade_line_item_fields

      # Declare the operator-editable columns for nested editing.
      def emerald_cascade_line_item(*fields)
        @emerald_cascade_line_item_fields = fields.map(&:to_sym)
      end

      # Strong-params shape for accepts_nested_attributes_for on the parent. `extra` adds
      # context-specific columns (e.g. an admin-only derived flag); `allow_destroy` permits
      # row removal.
      def nested_attributes_params(extra: [], allow_destroy: false)
        [:id, (:_destroy if allow_destroy), *emerald_cascade_line_item_fields, *extra].compact
      end
    end
  end
end
