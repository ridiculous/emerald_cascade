# frozen_string_literal: true

module EmeraldCascade
  # Mix into a submission model (any ActiveRecord model with a string `state` column)
  # to get a resumable, definition-driven multi-step lifecycle. The concern owns no
  # schema and no answer columns: it reads/writes answers through the host model's
  # normal attribute API, so the host decides how answers are stored.
  #
  #   class ClosingFormSubmission < ApplicationRecord
  #     include EmeraldCascade::Submittable
  #     emerald_cascade_form ClosingForm::Definition
  #   end
  module Submittable
    extend ActiveSupport::Concern

    class_methods do
      # Declares the form and builds the state machine. States are the definition's
      # full step-key superset plus not_started/complete/locked; advance/back walk the
      # superset in order, while the navigation helpers below skip hidden steps.
      def emerald_cascade_form(definition)
        self.emerald_cascade_definition = definition
        steps = definition.all_step_keys
        raise ArgumentError, 'EmeraldCascade form definition has no steps' if steps.empty?

        states = ['not_started', *steps, 'complete', 'locked'].map(&:to_sym)

        state_machine :state, initial: :not_started do
          state(*states)

          event :start do
            transition not_started: steps.first.to_sym
          end

          event :advance do
            steps.each_cons(2) { |from, to| transition from.to_sym => to.to_sym }
          end

          event :back do
            steps.each_cons(2) { |from, to| transition to.to_sym => from.to_sym }
          end

          event :submit do
            transition steps.last.to_sym => :complete
          end

          event :reopen do
            transition complete: steps.first.to_sym
          end

          event :lock do
            transition complete: :locked
          end

          before_transition to: :complete do |record|
            record.completed_at ||= Time.current if record.respond_to?(:completed_at)
            record.emerald_cascade_before_complete
          end

          after_transition to: :complete do |record|
            record.emerald_cascade_after_complete
          end
        end
      end
    end

    included do
      class_attribute :emerald_cascade_definition, instance_writer: false, instance_predicate: false

      # Ordered superset of every possible step key (drives the state machine).
      delegate :all_step_keys, to: :emerald_cascade_definition
    end

    # --- navigation over the visible subset -------------------------------------
    #
    # `state` names a step in the full superset; these helpers translate to the
    # per-record *visible* subset so links and advance/back reflect what's shown.

    def visible_step_keys
      emerald_cascade_definition.for(self).map(&:key)
    end

    def visible_steps
      emerald_cascade_definition.for(self)
    end

    def current_step
      emerald_cascade_definition.step_for(state)
    end

    # Human-friendly label for the persisted state (e.g. an admin status column).
    def display_state
      state.to_s.humanize
    end

    def step_visible?(key)
      visible_step_keys.include?(key.to_s)
    end

    def first_step
      visible_step_keys.first
    end

    def next_step
      next_step_of(state)
    end

    def prev_step
      prev_step_of(state)
    end

    # Neighboring visible steps relative to an arbitrary step (not the persisted
    # state), so navigation links reflect the step actually being viewed.
    def next_step_of(key)
      keys = visible_step_keys
      i = keys.index(key.to_s)
      i && keys[i + 1]
    end

    def prev_step_of(key)
      keys = visible_step_keys
      i = keys.index(key.to_s)
      i&.positive? ? keys[i - 1] : nil
    end

    def advance_step!
      target = next_step
      return unless target

      advance! until state == target
    end

    def back_step!
      target = prev_step
      return unless target

      back! until state == target
    end

    # Advance to the step after `step_key` (relative to the viewed step, not the
    # persisted state) so Continue works even when the user navigated back.
    def advance_from!(step_key)
      goto_step!(next_step_of(step_key))
    end

    # Walk the sequential state machine to any visible target step, in either
    # direction, looping over omitted superset steps.
    def goto_step!(target)
      return unless target

      target = target.to_s
      return unless step_visible?(target)

      order = all_step_keys
      ti = order.index(target)
      advance! while order.index(state) < ti
      back! while order.index(state) > ti
    end

    def begin_flow!
      start!
      skip_to_first_visible_step!
    end

    def reopen_flow!
      reopen!
      skip_to_first_visible_step!
    end

    def skip_to_first_visible_step!
      advance! until step_visible?(state)
    end

    # --- definition-driven validation over the visible subset -------------------
    #
    # `valid_step?` checks one step so partial progress is fine; `valid_for_submit?`
    # checks the whole form (minus the review step) before completing. Both clear
    # errors first and validate through the field declarations. A host whose step
    # validates more than its fields (nested records, uploads) overrides
    # `validate_step` and delegates the rest with `super`.

    def valid_step?(step_key)
      errors.clear
      step = visible_steps.find { |s| s.key == step_key.to_s }
      return true unless step

      validate_step(step)
      errors.empty?
    end

    def valid_for_submit?
      errors.clear
      visible_steps.each do |step|
        next if step.key == review_step_key

        validate_step(step)
      end
      errors.empty?
    end

    # Default per-step validation: run each field's own validation. Override on the
    # host for steps that validate more than their declared fields.
    def validate_step(step)
      step.fields.each { |field| field.validate(self) }
    end

    # The final step: it only reviews and submits, so whole-form validation skips it.
    def review_step_key
      'review'
    end

    # --- lifecycle completion hooks (host overrides) ----------------------------
    # Host-specific work on completion (snapshots, child recompute, etc.) lives on
    # the host model by overriding these no-ops.

    def emerald_cascade_before_complete; end

    def emerald_cascade_after_complete; end
  end
end
