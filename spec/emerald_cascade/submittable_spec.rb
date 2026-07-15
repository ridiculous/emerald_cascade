# frozen_string_literal: true

require 'rails_helper'

# Standalone proof that the engine boots and works inside a bare host (the dummy app), with
# no coupling to any real application: a tiny multi-step form built entirely through the
# public API (Definition + Field + Submittable) against the dummy app's throwaway table.
#
# The classes are named (not anonymous) because building an ActiveRecord state machine needs
# a class name. The conditional step is keyed `:catering` while the boolean it depends on is
# `catered`, so the state's generated `catering?` predicate doesn't shadow the column reader.
class FeedbackDefinition < EmeraldCascade::Definition
  step :about, title: 'About you', fields: [
    EmeraldCascade::Field.new(:attendee_name, type: :string, required: true),
    EmeraldCascade::Field.new(:rating, type: :rating, choices: (1..5).to_a)
  ]
  step :catering, title: 'Catering', visible_when: ->(r) { r.catered? }
  step :review, title: 'Review', partial: 'review'
end

class Feedback < ActiveRecord::Base
  self.table_name = 'feedbacks'
  include EmeraldCascade::Submittable
  emerald_cascade_form FeedbackDefinition

  def emerald_cascade_after_complete
    update_column(:finalized, true)
  end
end

RSpec.describe EmeraldCascade::Submittable do
  it 'derives its states from the full step-key superset' do
    expect(Feedback.new.all_step_keys).to eq(%w[about catering review])
  end

  it 'begins at the first visible page and stamps nothing until submit' do
    feedback = Feedback.create!
    feedback.begin_flow!

    expect(feedback.state).to eq('about')
    expect(feedback.completed_at).to be_nil
  end

  it 'omits pages whose visible_when is false, and navigation skips them' do
    plain   = Feedback.create!(catered: false)
    catered = Feedback.create!(catered: true)

    expect(plain.visible_page_keys).to eq(%w[about review])
    expect(catered.visible_page_keys).to eq(%w[about catering review])
    expect(plain.next_page_of('about')).to eq('review')
    expect(catered.next_page_of('about')).to eq('catering')
  end

  it 'runs the host completion hook and stamps completed_at on submit' do
    feedback = Feedback.create!(catered: false)
    feedback.begin_flow!
    feedback.goto_page!('review')
    feedback.submit!

    expect(feedback.reload).to have_attributes(state: 'complete', finalized: true, completed_at: be_present)
  end

  it 'validates required fields through the definition' do
    record = Feedback.new
    FeedbackDefinition.step_for('about').fields.each { |f| f.validate(record) }

    expect(record.errors[:attendee_name]).to be_present
  end
end
