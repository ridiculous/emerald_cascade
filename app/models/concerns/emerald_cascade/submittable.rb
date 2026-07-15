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
      # superset in order, while the navigation helpers below skip hidden pages.
      def emerald_cascade_form(definition)
        self.emerald_cascade_definition = definition
        pages = definition.all_step_keys
        raise ArgumentError, 'EmeraldCascade form definition has no steps' if pages.empty?

        states = ['not_started', *pages, 'complete', 'locked'].map(&:to_sym)

        state_machine :state, initial: :not_started do
          state(*states)

          event :start do
            transition not_started: pages.first.to_sym
          end

          event :advance do
            pages.each_cons(2) { |from, to| transition from.to_sym => to.to_sym }
          end

          event :back do
            pages.each_cons(2) { |from, to| transition to.to_sym => from.to_sym }
          end

          event :submit do
            transition pages.last.to_sym => :complete
          end

          event :reopen do
            transition complete: pages.first.to_sym
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
    # `state` names a page in the full superset; these helpers translate to the
    # per-record *visible* subset so links and advance/back reflect what's shown.

    def visible_page_keys
      emerald_cascade_definition.for(self).map(&:key)
    end

    def visible_steps
      emerald_cascade_definition.for(self)
    end

    def current_step
      emerald_cascade_definition.step_for(state)
    end

    def page_visible?(key)
      visible_page_keys.include?(key.to_s)
    end

    def first_page
      visible_page_keys.first
    end

    def next_page
      next_page_of(state)
    end

    def prev_page
      prev_page_of(state)
    end

    # Neighboring visible pages relative to an arbitrary page (not the persisted
    # state), so navigation links reflect the page actually being viewed.
    def next_page_of(key)
      keys = visible_page_keys
      i = keys.index(key.to_s)
      i && keys[i + 1]
    end

    def prev_page_of(key)
      keys = visible_page_keys
      i = keys.index(key.to_s)
      i&.positive? ? keys[i - 1] : nil
    end

    def advance_page!
      target = next_page
      return unless target

      advance! until state == target
    end

    def back_page!
      target = prev_page
      return unless target

      back! until state == target
    end

    # Advance to the page after `step_key` (relative to the viewed page, not the
    # persisted state) so Continue works even when the user navigated back.
    def advance_from!(step_key)
      goto_page!(next_page_of(step_key))
    end

    # Walk the sequential state machine to any visible target page, in either
    # direction, looping over omitted superset pages.
    def goto_page!(target)
      return unless target

      target = target.to_s
      return unless page_visible?(target)

      order = all_step_keys
      ti = order.index(target)
      advance! while order.index(state) < ti
      back! while order.index(state) > ti
    end

    def begin_flow!
      start!
      skip_to_first_visible_page!
    end

    def reopen_flow!
      reopen!
      skip_to_first_visible_page!
    end

    def skip_to_first_visible_page!
      advance! until page_visible?(state)
    end

    # --- lifecycle completion hooks (host overrides) ----------------------------
    # Host-specific work on completion (snapshots, child recompute, etc.) lives on
    # the host model by overriding these no-ops.

    def emerald_cascade_before_complete; end

    def emerald_cascade_after_complete; end
  end
end
