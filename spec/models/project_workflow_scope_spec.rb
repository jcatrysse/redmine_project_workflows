# frozen_string_literal: true

require_relative '../spec_helper'

describe ProjectWorkflowScope, type: :model do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:other) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }

  def attributes(overrides = {})
    { project_id: project.id, tracker_id: tracker.id, role_id: role.id,
      rule_type: described_class::TRANSITIONS }.merge(overrides)
  end

  it 'accepts the two rule types and nothing else' do
    expect(described_class.new(attributes)).to be_valid
    expect(described_class.new(attributes(rule_type: described_class::PERMISSIONS))).to be_valid
    expect(described_class.new(attributes(rule_type: 'anything'))).not_to be_valid
    expect(described_class.new(attributes(rule_type: nil))).not_to be_valid
  end

  it 'requires a project, a tracker and a role' do
    %i[project_id tracker_id role_id].each do |attribute|
      expect(described_class.new(attributes(attribute => nil))).not_to be_valid
    end
  end

  it 'is unique per project, tracker, role and rule type' do
    described_class.create!(attributes)

    expect(described_class.new(attributes)).not_to be_valid
    # ... but the other rule type is a different scope entirely.
    expect(described_class.new(attributes(rule_type: described_class::PERMISSIONS))).to be_valid
    expect(described_class.new(attributes(project_id: other.id))).to be_valid
  end

  # The unique index is the one that has to hold: validations lose a race.
  it 'refuses a duplicate at the database level' do
    described_class.create!(attributes)
    duplicate = described_class.new(attributes)

    expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'maps Redmine workflow classes to rule types in both directions' do
    expect(described_class.rule_type_for(WorkflowTransition)).to eq(described_class::TRANSITIONS)
    expect(described_class.rule_type_for(WorkflowPermission)).to eq(described_class::PERMISSIONS)
    expect(described_class.rule_type_for(described_class::TRANSITIONS)).to eq(described_class::TRANSITIONS)
    expect(described_class.rule_model_for(described_class::PERMISSIONS)).to eq(WorkflowPermission)

    expect { described_class.rule_type_for(Project) }.to raise_error(ArgumentError)
    expect { described_class.rule_model_for('nonsense') }.to raise_error(ArgumentError)
  end

  it 'goes when its project goes' do
    scope = described_class.create!(attributes(project_id: other.id))
    other.destroy

    expect(described_class.where(id: scope.id)).to be_empty
  end

  it 'keeps the audit columns when the user who set it is deleted' do
    user = users(:users_002)
    scope = described_class.create!(attributes(created_by_id: user.id, updated_by_id: user.id))
    user.destroy

    scope.reload
    expect(scope.created_by_id).to be_nil
    expect(scope.updated_by_id).to be_nil
  end
end
