# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::TransitionQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user) { users(:users_002) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before do
    member = Member.where(project: project, user: user).first_or_initialize
    member.roles = [role] if member.new_record? || member.roles.empty?
    member.save!
  end

  it 'ignores a project row when the project has no scope' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)
    statuses = described_class.allowed_statuses(
      issue: issue, user: user, initial_status: old_status, author: true, assignee: false
    )

    expect(statuses).to eq([global_status])
  end

  # INV-4. Core's own query names no project_id, so it would read this project's
  # rows together with the neighbour's; the plugin's never does.
  it 'never reads another project rows' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: projects(:projects_002).id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)
    statuses = described_class.allowed_statuses(
      issue: issue, user: user, initial_status: old_status, author: true, assignee: false
    )

    expect(statuses).to eq([global_status])
  end

  it 'allows nothing for a scope without rules' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    give_own_workflow(project, tracker, role)

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)
    statuses = described_class.allowed_statuses(
      issue: issue, user: user, initial_status: old_status, author: true, assignee: false
    )

    expect(statuses).to eq([])
  end

  it 'prefers project transitions over global ones for scoped roles' do
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)

    statuses = described_class.allowed_statuses(
      issue: issue,
      user: user,
      initial_status: old_status,
      author: true,
      assignee: false
    )

    expect(statuses).to include(project_status)
    expect(statuses).not_to include(global_status)
  end

  # F04. This is the hottest path the plugin owns: Issue#safe_attributes= calls
  # new_statuses_allowed_to unconditionally on every issue save, and the
  # bulk-edit form, the bulk-save loop and the context menu each fan it out once
  # per selected issue -- 200 selected issues is 200 of these statements in one
  # request.
  #
  # It used to be a join *plus* a subquery against the same table:
  #
  #   IssueStatus.joins(:workflow_transitions_as_new_status)
  #              .where(workflows: { id: combined_scope.select(:id) })
  #              .distinct
  #
  # which is one primary-key lookup back into `workflows` per matching
  # transition row, for an answer the subquery already had in hand: it selected
  # `workflows.id` so that the join could look the same row up again. Core does
  # one join with a WHERE and no subquery, identically on 5.1-stable and
  # 7.0-stable. Three concepts where one suffices, in the file a maintainer
  # opens first when comparing the plugin against core.
  #
  # The replacement keeps an `IN` subquery and drops the join and the DISTINCT,
  # because `IN` is already a semi-join. That is the distinction this group
  # asserts, and it is worth being exact about: "no subquery" would be the wrong
  # gate, and the first draft of this example asserted it and failed against the
  # correct fix.
  #
  # Asserted as statement shape, because the *answer* was never wrong -- the
  # eleven examples above already pin that, and would have stayed green through
  # a rewrite that reintroduced the join. The 'one statement' half matters as
  # much as the shape: the version the source review proposed
  # (`combined_scope.distinct.pluck(:new_status_id)` then a second query) would
  # satisfy 'no join' and add a round trip to this path.
  describe 'the shape of the statement it issues' do
    def statuses_for(issue)
      described_class.allowed_statuses(
        issue: issue, user: user, initial_status: old_status, author: false, assignee: false
      )
    end

    def transition_statements(issue)
      statements_during { statuses_for(issue) }
        .grep(/\bfrom\s+\W?issue_statuses\W/i)
    end

    before do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: old_status.id,
                                 new_status_id: global_status.id, project_id: nil,
                                 author: false, assignee: false)
    end

    it 'reads the statuses in one statement with no join and no DISTINCT' do
      issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)

      statements = transition_statements(issue)

      expect(statements.size).to eq(1)
      expect(statements.first).not_to match(/\bJOIN\b/i)
      expect(statements.first).not_to match(/\bDISTINCT\b/i)
      # The IN subquery is the point, not a leftover: it is what replaces both
      # the join and the DISTINCT, because IN is already a semi-join. What must
      # not come back is the subquery selecting `workflows.id` for the join to
      # look the row up by again.
      expect(statements.first).to match(/IN \(SELECT\b[^)]*new_status_id/i)
    end

    # The predicate it does keep: every project_id predicate stays inside
    # combined_scope, which this change did not touch (INV-4).
    it 'still names the project of an overriding combination' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: old_status.id,
                                 new_status_id: project_status.id, project_id: project.id,
                                 author: false, assignee: false)
      issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)

      expect(transition_statements(issue).first).to match(/project_id/i)
      expect(statuses_for(issue)).to contain_exactly(project_status)
    end

    # A NULL new_status_id cannot produce a false positive -- `id IN (NULL, 3)`
    # is NULL rather than true -- and TransitionWriter whitelists new_status_id
    # against IssueStatus.pluck(:id) anyway, so the plugin cannot write one.
    # Asserted rather than argued, because the DISTINCT that went is the only
    # thing that used to stand between the two.
    it 'ignores a transition row whose new status was deleted' do
      doomed = IssueStatus.create!(name: 'Doomed')
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: old_status.id,
                                 new_status_id: doomed.id, project_id: nil, author: false, assignee: false)
      IssueStatus.where(id: doomed.id).delete_all
      issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)

      expect(statuses_for(issue)).to contain_exactly(global_status)
    end
  end
end
