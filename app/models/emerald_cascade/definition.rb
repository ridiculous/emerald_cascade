# frozen_string_literal: true

module EmeraldCascade
  # Base class for a form definition: the single source of truth for which steps a
  # form shows and what each step contains. Subclass it and declare steps with `step`.
  #
  #   class ClosingForm::Definition < EmeraldCascade::Definition
  #     step :photos, title: 'Packing sheet photos', partial: 'photos',
  #          visible_when: ->(s) { s.photos_step? }
  #     step :name, title: 'What is your name?', fields: [
  #       EmeraldCascade::Field.new(:full_name, type: :string, required: true)
  #     ]
  #     step :review, title: 'Review & submit', partial: 'review'
  #   end
  #
  # Steps are always kept in declaration order; `visible_when` only omits steps.
  class Definition
    class << self
      def steps
        @steps ||= []
      end

      # Subclasses start from a copy of their parent's steps so a shared base can
      # contribute common steps if desired.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@steps, steps.dup)
      end

      def step(key, **opts)
        steps << EmeraldCascade::Step.new(key, **opts)
      end

      # Ordered superset of every possible step key; drives the state machine states.
      def all_step_keys
        steps.map(&:key)
      end

      # Steps visible for a given record, in declaration order.
      def for(record)
        steps.select { |s| s.visible_for?(record) }
      end

      def visible_step_keys(record)
        self.for(record).map(&:key)
      end

      # Flat strong-params shape for every field across all steps: scalar keys, and
      # `{ key => [] }` for array/checklist fields. The single source of truth for the
      # attributes a submission permits, so a controller's permit list can't drift from
      # the fields.
      def field_param_keys
        steps.flat_map(&:param_keys)
      end

      def step_for(key)
        steps.find { |s| s.key == key.to_s }
      end
    end
  end
end
