# frozen_string_literal: true

module EmeraldCascade
  # One page of a multi-step form. `key` doubles as the state-machine state name, so
  # the definition order drives advance/back and `state` always names a real page.
  #
  # `visible_when` is an optional predicate (called with the submission record) that
  # omits the page for some records without reordering; the state machine walks the
  # full superset and the navigation helpers skip hidden pages.
  class Step
    attr_reader :key, :fields, :title, :subtitle

    def initialize(key, fields: [], title: nil, subtitle: nil, visible_when: nil, partial: nil)
      @key = key.to_s
      @fields = fields
      @title = title
      @subtitle = subtitle
      @visible_when = visible_when
      @partial = partial
    end

    def field(name)
      fields.find { |f| f.key == name.to_sym }
    end

    # Strong-params shape for this page's fields (arrays permit a list).
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

    def visible_for?(record)
      @visible_when.nil? || @visible_when.call(record)
    end
  end
end
