require 'rails_helper'

# Genericness proof + boundary guard: a second, unrelated multi-step form ("event feedback")
# built ENTIRELY through the engine's public API (Definition + Field + Submittable +
# LineItemGroup), backed by a throwaway table. It deliberately mirrors nothing from the closing
# form; if any engine code were coupled to ClosingForm, this would not work.
RSpec.describe 'EmeraldCascade genericness' do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:event_feedbacks, force: true) do |t|
      t.string :state
      t.datetime :completed_at
      t.string :attendee_name
      t.integer :overall_rating
      t.boolean :had_issues
      t.text :issue_details
      t.string :meal_quality
      t.boolean :catered, default: false
      t.boolean :finalized, default: false
    end

    Object.const_set(:EventFeedbackDefinition, Class.new(EmeraldCascade::Definition))
    EventFeedbackDefinition.class_eval do
      step :attendee, title: 'About you', fields: [
        EmeraldCascade::Field.new(:attendee_name, type: :string, required: true),
        EmeraldCascade::Field.new(:overall_rating, type: :rating, choices: (1..5).to_a, required: true)
      ]
      step :issues, title: 'Any issues?', fields: [
        EmeraldCascade::Field.new(:had_issues, type: :boolean, required: true),
        EmeraldCascade::Field.new(:issue_details, type: :text,
                                  depends_on: { field: :had_issues, equals: true })
      ]
      step :catering, title: 'Catering', visible_when: ->(r) { r.catered? }, fields: [
        EmeraldCascade::Field.new(:meal_quality, type: :enum, choices: %w[poor ok great])
      ]
      step :review, title: 'Review', partial: 'review'
    end

    Object.const_set(:EventFeedback, Class.new(ActiveRecord::Base))
    EventFeedback.class_eval do
      self.table_name = 'event_feedbacks'
      include EmeraldCascade::Submittable
      emerald_cascade_form EventFeedbackDefinition

      def emerald_cascade_after_complete
        update_column(:finalized, true)
      end
    end
  end

  after(:all) do
    Object.send(:remove_const, :EventFeedback) if Object.const_defined?(:EventFeedback)
    Object.send(:remove_const, :EventFeedbackDefinition) if Object.const_defined?(:EventFeedbackDefinition)
    ActiveRecord::Base.connection.drop_table(:event_feedbacks, if_exists: true)
  end

  describe 'definition-driven state machine' do
    it 'builds its states from the full step-key superset' do
      expect(EventFeedback.new.all_step_keys).to eq(%w[attendee issues catering review])
    end

    it 'begins at the first visible page and stamps nothing until submit' do
      feedback = EventFeedback.create!
      feedback.begin_flow!

      expect(feedback.state).to eq('attendee')
      expect(feedback.completed_at).to be_nil
    end

    it 'omits pages whose visible_when is false, and navigation skips them' do
      catered = EventFeedback.create!(catered: true)
      plain   = EventFeedback.create!(catered: false)

      expect(catered.visible_page_keys).to eq(%w[attendee issues catering review])
      expect(plain.visible_page_keys).to eq(%w[attendee issues review])
      expect(plain.next_page_of('issues')).to eq('review')
      expect(catered.next_page_of('issues')).to eq('catering')
    end

    it 'runs the host completion hooks on submit' do
      feedback = EventFeedback.create!(catered: false)
      feedback.begin_flow!
      feedback.goto_page!('review')
      feedback.submit!

      expect(feedback.reload).to have_attributes(state: 'complete', finalized: true, completed_at: be_present)
    end
  end

  describe 'field validation + conditional visibility' do
    def validate_step(record, key)
      EventFeedbackDefinition.step_for(key).fields.each { |f| f.validate(record) }
      record
    end

    it 'flags required fields left blank' do
      record = validate_step(EventFeedback.new, 'attendee')

      expect(record.errors[:attendee_name]).to be_present
      expect(record.errors[:overall_rating]).to be_present
    end

    it 'rejects an out-of-set enum value' do
      record = validate_step(EventFeedback.new(meal_quality: 'terrible'), 'catering')

      expect(record.errors[:meal_quality]).to be_present
    end

    it 'requires a companion field only when its controlling answer is set' do
      hidden = validate_step(EventFeedback.new(had_issues: false), 'issues')
      expect(hidden.errors[:issue_details]).to be_empty

      shown = validate_step(EventFeedback.new(had_issues: true), 'issues')
      expect(shown.errors[:issue_details]).to be_present
    end
  end

  describe 'EmeraldCascade::LineItemGroup on an arbitrary model' do
    it 'derives nested_attributes_params from declared fields, with no host coupling' do
      klass = Class.new do
        include EmeraldCascade::LineItemGroup
        emerald_cascade_line_item :quantity, :notes
      end

      expect(klass.nested_attributes_params).to eq(%i[id quantity notes])
      expect(klass.nested_attributes_params(extra: [:flag], allow_destroy: true))
        .to eq(%i[id _destroy quantity notes flag])
    end
  end
end
