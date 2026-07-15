# frozen_string_literal: true

module EmeraldCascade
  # Generic create/destroy for a submission's attachment collection: enforces an optional max
  # count, appends the upload, runs an after-create hook (e.g. enqueue background processing),
  # and redirects back to the same page. The host controller supplies the collection, upload
  # param, limit, redirect and hook by overriding the small methods below.
  module AttachmentUploads
    extend ActiveSupport::Concern

    def create
      return if performed?

      if attachment_limit && attachments.count >= attachment_limit
        return redirect_to(attachments_redirect_url, alert: attachment_limit_message, status: :see_other)
      end

      after_attachment_created(attachments.create!(attachment_params))
      redirect_to attachments_redirect_url, status: :see_other
    end

    def destroy
      attachments.find_by(id: params[:id])&.destroy
      redirect_to attachments_redirect_url, status: :see_other
    end

    private

    # --- host overrides -------------------------------------------------------
    def attachments
      raise NotImplementedError, "#{self.class} must define #attachments"
    end

    def attachments_redirect_url
      raise NotImplementedError, "#{self.class} must define #attachments_redirect_url"
    end

    def attachment_params
      { image: params[:image] }
    end

    def attachment_limit
      nil
    end

    def attachment_limit_message
      'Maximum number of attachments reached'
    end

    def after_attachment_created(_attachment); end
  end
end
