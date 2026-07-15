# frozen_string_literal: true

module EmeraldCascade
  # Renders and saves one page at a time. Saves are validated per page, so partial progress is
  # fine; the final review page re-validates the whole form and submits. Include in the host's
  # steps controller (which supplies the record + URLs via Flow, and the page-specific hooks
  # below).
  module StepFlow
    extend ActiveSupport::Concern
    include EmeraldCascade::Flow

    included do
      before_action :require_active_flow
    end

    def show
      @step = current_step
      return redirect_to(step_url_for(@submission.state)) unless @step

      on_step_show(@step)
    end

    def update
      require_editable!
      return if performed?

      @step = current_step
      return head(:not_found) unless @step
      return submit_review if @step.key == review_step_key

      assign_step_attributes(@step)
      if @submission.valid_page?(@step.key)
        @submission.save!(validate: false)
        @submission.advance_from!(@step.key)
        redirect_to step_url_for(@submission.state), status: :see_other
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def submit_review
      if @submission.valid_for_submit?
        @submission.submit!
        redirect_to submission_url, notice: submit_notice, status: :see_other
      else
        @step = current_step
        render :show, status: :unprocessable_entity
      end
    end

    def require_active_flow
      return redirect_to(submission_url) unless @submission

      redirect_to submission_url if @submission.complete? || @submission.locked? || @submission.not_started?
    end

    # A page of only radios/checkboxes sends no scope param when nothing is picked, so tolerate a
    # missing scope and let valid_page? surface the required-field errors instead of raising.
    def submission_scope
      params.fetch(submission_param_key, ActionController::Parameters.new)
    end

    def page_params
      submission_scope.permit(*@step.param_keys)
    end

    # Nested form scope; defaults to the record's own param key (what `form_with model:` uses).
    def submission_param_key
      @submission.model_name.param_key
    end

    # --- host overrides -------------------------------------------------------

    # Assign the current page's answers to @submission. Override and call `super` to add
    # page-specific params (e.g. nested line items).
    def assign_step_attributes(step)
      @submission.assign_attributes(page_params) if step.fields.any?
    end

    # Per-page setup on GET (e.g. seed nested rows before the page renders).
    def on_step_show(_step); end

    # The page key whose submit finalizes the form.
    def review_step_key
      'review'
    end

    # Flash notice shown after a successful submit (nil for none).
    def submit_notice; end
  end
end
