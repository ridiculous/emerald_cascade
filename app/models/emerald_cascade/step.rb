# frozen_string_literal: true

module EmeraldCascade
  # One step (one page) of a multi-step form. `key` doubles as the state-machine state name,
  # so the definition order drives advance/back and `state` always names a real step.
  #
  # `visible_when` is an optional predicate (called with the submission record) that
  # omits the step for some records without reordering; the state machine walks the
  # full superset and the navigation helpers skip hidden steps.
  #
  # `own_form: true` marks a step that renders its own form(s) (e.g. a file-upload step)
  # rather than the standard single PATCH form the field-based steps share; the host's show
  # template reads `renders_own_form?` to decide how to wrap the step.
  class Step
    attr_reader :key, :fields, :title, :subtitle

    def initialize(key, fields: [], title: nil, subtitle: nil, visible_when: nil, partial: nil, own_form: false)
      @key = key.to_s
      @fields = fields
      @title = title
      @subtitle = subtitle
      @visible_when = visible_when
      @partial = partial
      @own_form = own_form
    end

    def field(name)
      fields.find { |f| f.key == name.to_sym }
    end

    # Strong-params shape for this step's fields (arrays permit a list).
    def param_keys
      fields.map { |f| f.array? ? { f.key => [] } : f.key }
    end

    # Bespoke partial name when given, otherwise the generic field-rendering partial.
    def partial
      @partial || 'fields'
    end

    def custom?
      !@partial.nil?
    end

    # True when the host's show template should let this step render its own form(s) instead
    # of wrapping it in the shared PATCH form (declared with `own_form: true`).
    def renders_own_form?
      @own_form
    end

    def visible_for?(record)
      @visible_when.nil? || @visible_when.call(record)
    end
  end
end
