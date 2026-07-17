# frozen_string_literal: true

module EmeraldCascade
  # A single question on a form step. One declaration drives three things: the
  # rendered input (type/required/choices), the permitted params, and the model
  # validation. `depends_on` gates conditional companion fields (e.g. a description
  # only shown/required when its yes/no toggle is "yes"), driving both the
  # server-side validation and the client-side show/hide toggle.
  class Field
    attr_reader :key, :type, :options, :depends_on

    # @param type [Symbol] :string, :text, :boolean, :enum, :integer, :decimal, :array, :rating
    # @param depends_on [Hash] { field:, equals: value } (exact match) or
    #   { field:, includes: value } (array/checklist contains value).
    def initialize(key, type:, required: nil, show_when: nil, depends_on: nil, **options)
      @key = key.to_sym
      @type = type
      @depends_on = depends_on
      @options = options
      if depends_on
        @show_when = show_when || dependency_predicate(depends_on)
        # companion fields default to required when shown, unless explicitly opted out
        @required = required.nil? || required
      else
        @required = required || false
        @show_when = show_when
      end
    end

    def depends_on_includes?
      depends_on&.key?(:includes) || false
    end

    def depends_on_value
      return unless depends_on

      depends_on_includes? ? depends_on[:includes] : depends_on.fetch(:equals, true)
    end

    def label
      options[:label] || key.to_s.humanize
    end

    def help
      options[:help]
    end

    def choices
      options[:choices]
    end

    # Numeric input step for :decimal (defaults to 'any' in the renderer when unset).
    def step
      options[:step]
    end

    def array?
      type == :array
    end

    def visible?(record)
      @show_when.nil? || @show_when.call(record)
    end

    def required?(record)
      return false unless visible?(record)

      @required.respond_to?(:call) ? @required.call(record) : @required
    end

    def value(record)
      record.public_send(key)
    end

    def validate(record)
      return unless visible?(record)

      val = value(record)
      if required?(record) && blank_value?(val)
        record.errors.add(key, :blank)
        return
      end
      return if blank_value?(val)

      case type
      when :integer
        record.errors.add(key, 'must be a whole number of 0 or more') unless val.is_a?(Integer) && val >= 0
      when :decimal
        record.errors.add(key, 'must be a number of 0 or more') unless val.respond_to?(:>=) && val >= 0
      when :enum, :rating
        record.errors.add(key, 'is not a valid choice') if choices&.exclude?(val)
      end
    end

    private

    def dependency_predicate(depends_on)
      ctrl = depends_on[:field]
      if depends_on_includes?
        ->(r) { Array(r.public_send(ctrl)).include?(depends_on[:includes]) }
      else
        target = depends_on.fetch(:equals, true)
        ->(r) { r.public_send(ctrl) == target }
      end
    end

    def blank_value?(val)
      return val.reject(&:blank?).empty? if val.is_a?(Array)
      return false if val == false # a "no" boolean answer is present, not blank

      val.blank?
    end
  end
end
