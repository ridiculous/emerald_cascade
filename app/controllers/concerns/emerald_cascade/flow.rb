# frozen_string_literal: true

module EmeraldCascade
  # Shared plumbing for the two controllers that drive a submission: the welcome/lifecycle
  # controller (SubmissionFlow) and the per-page controller (StepFlow). It reads `@submission`
  # (set by a host before_action) and steps it through the Submittable state machine. The host
  # supplies its own record lookup and the two URL builders declared at the bottom.
  module Flow
    extend ActiveSupport::Concern

    private

    # Lock a submitted form once its edit window has passed. Idempotent, so a plain GET can
    # trigger it (see #editable? on the host model for the window).
    def lazy_lock
      return unless @submission&.complete?
      return if @submission.editable?

      @submission.lock! if @submission.can_lock?
    end

    # The visible step named by the :step param (nil when it isn't a page for this record).
    def current_step
      @submission.visible_steps.find { |s| s.key == params[:step] }
    end

    def require_submission
      redirect_to submission_url unless @submission
    end

    def require_editable!
      redirect_to submission_url unless @submission&.editable?
    end

    # --- host contract --------------------------------------------------------
    # Routes belong to the host, so it defines these (and typically exposes them to views
    # via `helper_method`).
    def submission_url
      raise NotImplementedError, "#{self.class} must define #submission_url"
    end

    def step_url_for(_step)
      raise NotImplementedError, "#{self.class} must define #step_url_for"
    end
  end
end
