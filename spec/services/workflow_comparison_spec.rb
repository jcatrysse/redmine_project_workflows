# frozen_string_literal: true

require_relative '../spec_helper'

# WP6. What a project's own workflow says that the generic one does not, and the
# other way round.
describe RedmineProjectWorkflows::Services::WorkflowComparison do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:s3) { issue_statuses(:issue_statuses_003) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:permissions) { ProjectWorkflowScope::PERMISSIONS }

  before { WorkflowRule.delete_all }

  def compare(rule_type = transitions, for_project: project, for_tracker: tracker, for_role: role)
    described_class.new(project_id: for_project.id, tracker_id: for_tracker.id,
                        role_id: for_role.id, rule_type: rule_type).result
  end

  def transition(project_id, from: s1, to: s2, author: false, assignee: false,
                 for_tracker: tracker, for_role: role)
    WorkflowTransition.create!(tracker_id: for_tracker.id, role_id: for_role.id,
                               old_status_id: from.respond_to?(:id) ? from.id : from,
                               new_status_id: to.id, project_id: project_id,
                               author: author, assignee: assignee)
  end

  def permission(project_id, rule, status: s1, field: 'due_date')
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: status.id, field_name: field,
                               rule: rule, project_id: project_id)
  end

  describe 'transitions' do
    it 'reports nothing when the two agree' do
      transition(nil)
      transition(project.id)

      expect(compare).to be_identical
    end

    it 'reports a transition only the project has' do
      transition(project.id)

      result = compare
      expect(result.differences.map(&:state)).to eq([:project_only])
      difference = result.differences.first
      expect(difference.group).to eq('always')
      expect(difference.old_status).to eq(s1)
      expect(difference.new_status).to eq(s2)
    end

    it 'reports a transition only the generic workflow has' do
      transition(nil)
      # A scope with no rules at all: an own empty workflow, so every generic
      # transition is a difference.
      expect(compare.differences.map(&:state)).to eq([:generic_only])
    end

    # The three grids core draws are the unit of comparison, so the same pair of
    # statuses can differ in one grid and agree in another.
    it 'compares the author and assignee grids separately' do
      transition(nil, author: true)
      transition(project.id, assignee: true)

      result = compare
      expect(result.differences.map { |d| [d.group, d.state] })
        .to eq([['author', :generic_only], ['assignee', :project_only]])
    end

    # A row with both flags set is in two of core's grids at once, which is how
    # core's own matrix renders it, so it must count as present in both.
    it 'treats a row with both flags set as present in both grids' do
      transition(nil, author: true, assignee: true)
      transition(project.id, author: true)
      transition(project.id, assignee: true)

      expect(compare).to be_identical
    end

    it 'names core "new issue" row rather than a status' do
      transition(project.id, from: 0)

      difference = compare.differences.first
      expect(difference.old_status).to be_nil
      expect(difference.old_status_id).to eq(0)
    end

    it 'counts the rules on both sides' do
      transition(nil)
      transition(nil, to: s3)
      transition(project.id)

      result = compare
      expect(result.project_rule_count).to eq(1)
      expect(result.generic_rule_count).to eq(2)
    end

    # INV-4: both populations name a project_id, so a neighbour is never read
    # into either side of the comparison.
    it 'reads neither another project, tracker nor role' do
      transition(other_project.id)
      transition(project.id, for_tracker: other_tracker)
      transition(project.id, for_role: other_role)

      expect(compare).to be_identical
      expect(compare.project_rule_count).to be_zero
      expect(compare.generic_rule_count).to be_zero
    end

    # CI runs on PostgreSQL, MySQL and MariaDB with a random seed; an order that
    # comes out of the database is not an order.
    it 'orders the differences by grid and then by status position' do
      transition(project.id, from: s2, to: s3)
      transition(project.id, from: 0, to: s1)
      transition(project.id, from: s1, to: s2, assignee: true)

      expect(compare.differences.map { |d| [d.group, d.old_status_id] })
        .to eq([['always', 0], ['always', s2.id], ['assignee', s1.id]])
    end
  end

  describe 'field permissions' do
    it 'reports a rule only the project has' do
      permission(project.id, 'readonly')

      difference = compare(permissions).differences.first
      expect(difference.state).to eq(:project_only)
      expect(difference.project_rules).to eq(['readonly'])
      expect(difference.generic_rules).to be_empty
      expect(difference.field_name).to eq('due_date')
    end

    it 'reports a rule only the generic workflow has' do
      permission(nil, 'required')

      difference = compare(permissions).differences.first
      expect(difference.state).to eq(:generic_only)
      expect(difference.generic_rules).to eq(['required'])
      expect(difference.project_rules).to be_empty
    end

    # The state a transitions comparison cannot have: both sides say something
    # about the field and they disagree.
    it 'reports a rule both sides hold with different values' do
      permission(nil, 'required')
      permission(project.id, 'readonly')

      difference = compare(permissions).differences.first
      expect(difference.state).to eq(:changed)
      expect(difference.project_rules).to eq(['readonly'])
      expect(difference.generic_rules).to eq(['required'])
    end

    it 'reports nothing when the two agree' do
      permission(nil, 'readonly')
      permission(project.id, 'readonly')

      expect(compare(permissions)).to be_identical
    end

    it 'does not mix the two kinds of rule' do
      transition(project.id)

      expect(compare(permissions)).to be_identical
      expect(compare(permissions).project_rule_count).to be_zero
    end

    it 'orders the differences by status position and then by field name' do
      permission(project.id, 'readonly', status: s2, field: 'due_date')
      permission(project.id, 'readonly', status: s1, field: 'start_date')
      permission(project.id, 'readonly', status: s1, field: 'assigned_to_id')

      expect(compare(permissions).differences.map { |d| [d.status_id, d.field_name] })
        .to eq([[s1.id, 'assigned_to_id'], [s1.id, 'start_date'], [s2.id, 'due_date']])
    end
  end

  # The one place where this screen's answer could have depended on the order the
  # database returned rows in -- which is a green nine-cell matrix hiding a
  # PostgreSQL/MySQL divergence rather than a red one.
  describe 'two rows for the same field that disagree' do
    it 'shows both rather than picking one' do
      permission(project.id, 'readonly')
      permission(project.id, 'required')
      permission(nil, 'readonly')

      difference = compare(permissions).differences.first
      expect(difference.project_rules).to eq(%w[readonly required].sort)
      expect(difference.generic_rules).to eq(['readonly'])
      expect(difference.state).to eq(:changed)
    end

    it 'reports nothing when both sides hold the same disagreeing pair' do
      %w[readonly required].each do |rule|
        permission(nil, rule)
        permission(project.id, rule)
      end

      expect(compare(permissions)).to be_identical
    end

    # The settings tab and the inventory count rows, so this has to as well or
    # two screens describe the same combination with different numbers.
    it 'counts rows, duplicates included, not distinct rules' do
      permission(project.id, 'readonly')
      permission(project.id, 'readonly')

      expect(compare(permissions).project_rule_count).to eq(2)
    end
  end

  # A transitions comparison counts rows too, and the grids it compares throw
  # duplicates away, so the count cannot come from them.
  it 'counts duplicate transition rows' do
    transition(project.id)
    transition(project.id)

    result = compare
    expect(result.project_rule_count).to eq(2)
    expect(result.differences.size).to eq(1)
  end

  it 'refuses a rule type it does not know' do
    expect do
      described_class.new(project_id: project.id, tracker_id: tracker.id,
                          role_id: role.id, rule_type: 'everything')
    end.to raise_error(ArgumentError)
  end
end
