# frozen_string_literal: true

require_relative '../spec_helper'

# ADR-004. *Give own workflow* creates its scope rows in one statement per batch
# and copies the generic rules with one `INSERT … SELECT` per (tracker, role),
# under the coordination rows for those pairs, and refuses above the same ceiling
# the matrix save uses.
#
# The measurement that decided it is in the ADR; what is asserted here is that
# the batched write does exactly what the per-row one did, in the cases where a
# set operation can quietly do more.
describe RedmineProjectWorkflows::Services::ScopeWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:s3) { issue_statuses(:issue_statuses_003) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:budget) { RedmineProjectWorkflows::Services::WriteBudget }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    ProjectWorkflowWriteLock.delete_all
    Setting.plugin_redmine_project_workflows = {}
  end

  after { Setting.clear_cache }

  def generic_rule(from, to, on_tracker: tracker, for_role: role)
    WorkflowTransition.create!(tracker_id: on_tracker.id, role_id: for_role.id, project_id: nil,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def project_rule(target, from, to, on_tracker: tracker, for_role: role)
    WorkflowTransition.create!(tracker_id: on_tracker.id, role_id: for_role.id, project_id: target.id,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def enable(projects: [project], trackers: [tracker], roles: [role], copy_generic: true)
    described_class.enable(
      project_ids: projects.map(&:id), tracker_ids: trackers.map(&:id), role_ids: roles.map(&:id),
      rule_type: transitions, copy_generic: copy_generic, user: User.find(1)
    )
  end

  describe 'the batched write' do
    it 'gives every combination the generic rules, as the per-row write did' do
      [role, other_role].each do |for_role|
        generic_rule(s1, s2, for_role: for_role)
        generic_rule(s2, s3, for_role: for_role)
      end

      expect(enable(projects: [project, other_project], roles: [role, other_role])).to eq(4)

      expect(ProjectWorkflowScope.count).to eq(4)
      [project, other_project].each do |target|
        [role, other_role].each do |for_role|
          expect(WorkflowTransition.where(project_id: target.id, role_id: for_role.id)
                                   .pluck(:old_status_id, :new_status_id))
            .to contain_exactly([s1.id, s2.id], [s2.id, s3.id])
        end
      end
    end

    # The trap the first prototype fell into. A statement written as
    # `tracker_id IN (…) AND role_id IN (…) AND project_id IN (…)` spans the
    # whole cross product, so a combination inside those lists that already had
    # a scope would have the generic rules copied into it a second time. It only
    # passed because every combination in the prototype was new.
    it 'does not copy the generic rules into a combination that already had a scope' do
      generic_rule(s1, s2)
      give_own_workflow(other_project, other_tracker, other_role)
      project_rule(other_project, s2, s1, on_tracker: other_tracker, for_role: other_role)

      enable(projects: [project, other_project], trackers: [tracker, other_tracker],
             roles: [role, other_role])

      expect(WorkflowTransition.where(project_id: other_project.id, tracker_id: other_tracker.id,
                                      role_id: other_role.id)
                               .pluck(:old_status_id, :new_status_id))
        .to contain_exactly([s2.id, s1.id])
    end

    # The rules of one pair must not reach another pair's projects. A single
    # cross-product statement would do exactly that where the generic workflows
    # differ.
    it 'keeps each (tracker, role) pair to its own generic rules' do
      generic_rule(s1, s2)
      generic_rule(s2, s3, on_tracker: other_tracker, for_role: other_role)

      enable(trackers: [tracker, other_tracker], roles: [role, other_role])

      expect(WorkflowTransition.where(project_id: project.id, tracker_id: tracker.id, role_id: role.id)
                               .pluck(:old_status_id, :new_status_id)).to contain_exactly([s1.id, s2.id])
      expect(WorkflowTransition.where(project_id: project.id, tracker_id: other_tracker.id,
                                      role_id: other_role.id)
                               .pluck(:old_status_id, :new_status_id)).to contain_exactly([s2.id, s3.id])
      expect(WorkflowTransition.where(project_id: project.id, tracker_id: tracker.id,
                                      role_id: other_role.id)).to be_empty
    end

    it 'stamps the audit columns and the timestamps the per-row write set' do
      generic_rule(s1, s2)

      enable

      # .first rather than .sole: Redmine 5.1 runs Rails 6.1, which has no #sole.
      expect(ProjectWorkflowScope.count).to eq(1)
      scope = ProjectWorkflowScope.first
      expect(scope.created_by_id).to eq(1)
      expect(scope.updated_by_id).to eq(1)
      expect(scope.created_at).to be_within(1.minute).of(Time.now.utc)
      expect(scope.updated_at).to be_within(1.minute).of(Time.now.utc)
    end

    # A database that predates the scope table can hold project rules under no
    # scope. They are cleared, so that what *enable* leaves behind is a copy of
    # the generic workflow and nothing else.
    it 'clears rules that were lying under an unscoped combination' do
      generic_rule(s1, s2)
      project_rule(project, s3, s1)

      enable

      expect(WorkflowTransition.where(project_id: project.id).pluck(:old_status_id, :new_status_id))
        .to contain_exactly([s1.id, s2.id])
    end

    it 'is one statement per batch rather than one per combination' do
      generic_rule(s1, s2)

      statements = statements_during do
        enable(projects: [project, other_project], trackers: [tracker, other_tracker],
               roles: [role, other_role])
      end
      # The two tables the action is about. The coordination table is written to
      # as well, once per (rule type, tracker, role) for the life of the
      # installation -- after the first time those rows are simply there.
      writes = statements.grep(/\A\s*(INSERT INTO|DELETE FROM|UPDATE)\s+\W?(workflows|project_workflow_scopes)\b/i)

      expect(ProjectWorkflowScope.count).to eq(8)
      # Eight combinations: one insert for the scopes, and one copy per (tracker,
      # role) pair. Nothing that grows with the number of projects.
      expect(writes.size).to eq(5)
    end

    it 'takes the coordination rows before it writes anything' do
      skip('this adapter has no row locking to assert') unless row_locking?
      generic_rule(s1, s2)

      statements = statements_during { enable }

      expect(index_of_write_lock(statements)).to be_present
      expect(index_of_write_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    it 'writes nothing at all when the selection is empty' do
      expect(enable(projects: [])).to eq(0)
      expect(ProjectWorkflowScope.count).to eq(0)
    end
  end

  describe 'the ceiling' do
    before { generic_rule(s1, s2) && generic_rule(s2, s3) }

    it 'projects exactly what the copy would write' do
      combinations = [[project.id, tracker.id, role.id], [other_project.id, tracker.id, role.id]]

      expect(budget.projected_enable_rules(combinations: combinations, rule_type: transitions)).to eq(4)
    end

    it 'counts each pair with its own generic workflow' do
      generic_rule(s1, s3, on_tracker: other_tracker, for_role: other_role)
      combinations = [[project.id, tracker.id, role.id], [project.id, other_tracker.id, other_role.id]]

      expect(budget.projected_enable_rules(combinations: combinations, rule_type: transitions)).to eq(3)
    end

    it 'refuses a copy above the ceiling, before anything is written' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '3' }

      expect { enable(projects: [project, other_project]) }
        .to raise_error(budget::TooLarge) { |error|
              expect(error.projected).to eq(4)
              expect(error.ceiling).to eq(3)
            }

      expect(ProjectWorkflowScope.count).to eq(0)
      expect(WorkflowTransition.where.not(project_id: nil)).to be_empty
    end

    it 'allows a copy that is exactly at the ceiling' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '4' }

      expect(enable(projects: [project, other_project])).to eq(2)
    end

    it 'allows anything with the ceiling set to 0' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '0' }

      expect(enable(projects: [project, other_project])).to eq(2)
    end

    # The empty variant copies no rule, so it is never refused -- which is the
    # point: it is the bulk action that stays available at any size.
    it 'never refuses an own empty workflow, whatever the ceiling' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '1' }

      expect(enable(projects: [project, other_project], copy_generic: false)).to eq(2)
      expect(WorkflowTransition.where.not(project_id: nil)).to be_empty
    end

    # A second press has nothing left to create, so it projects nothing and is
    # not refused even under a ceiling the first press would have failed.
    it 'projects only what is still missing' do
      enable
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '1' }

      expect(enable).to eq(0)
    end
  end
end
