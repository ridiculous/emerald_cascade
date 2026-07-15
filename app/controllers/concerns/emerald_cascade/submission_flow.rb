# frozen_string_literal: true

module EmeraldCascade
  # Welcome-screen lifecycle: show (welcome/resume/done), create (Start), reopen (Edit) and
  # reset (discard). Include in the host's submissions controller (which supplies the record +
  # URLs via Flow, and the new record via #build_submission). GETs never create -- a submission
  # is only built on Start (POST).
  module SubmissionFlow
    extend ActiveSupport::Concern
    include EmeraldCascade::Flow

    # The view branches on @submission (none -> Start, in progress -> Resume, complete+editable
    # -> Edit/Reset, locked -> read-only).
    def show; end

    def create
      return redirect_to(submission_url) if @submission

      @submission = build_submission
      @submission.save!(validate: false)
      @submission.begin_flow!
      redirect_to step_url_for(@submission.state), status: :see_other
    end

    def reopen
      require_editable!
      return if performed?

      @submission.reopen_flow! if @submission.complete?
      redirect_to step_url_for(@submission.state), status: :see_other
    end

    # Discard the whole submission (answers, items, attachments) and return to the welcome page,
    # where the operator can Start fresh.
    def reset
      require_editable!
      return if performed?

      @submission.destroy
      redirect_to submission_url, status: :see_other
    end

    private

    # Build (don't save) the new submission for Start. The host sets its source/type/defaults.
    def build_submission
      raise NotImplementedError, "#{self.class} must define #build_submission"
    end
  end
end
