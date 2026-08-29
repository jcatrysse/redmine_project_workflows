# frozen_string_literal: true

require_relative '../spec_helper'

# WP17, finding F01 of docs/review/findings/2026-08-29-claude-revalidation.md.
#
# A restore is the thing an operator runs at the worst moment they will ever
# have with this plugin: the workflows are gone and this file is what is left.
# It therefore has to be safe to be *interrupted* -- a dropped connection, a
# killed terminal, a container evicted -- and it has to be safe to be run again
# afterwards, because running it again is what the README tells them to do.
#
# It was neither. The restore prepared every combination first (creating each
# missing scope) and only then looped over them writing rules, so an
# interruption left every combination it had not reached with a scope and no
# rules under it -- which is not an absence but a decision: an own EMPTY
# workflow, in which no status change is permitted at all. The retry then
# skipped exactly those, because a combination that already has a scope is one
# the default leaves alone. Reproduced before the fix: three projects in, two
# left empty, the retry reported three skipped and restored nothing.
#
# Every example here fails on that code. The unit is now one combination in one
# transaction, so a combination is either wholly restored -- safe to skip on a
# retry -- or wholly rolled back to inheriting -- safe to redo on a retry. The
# operator does not have to know which happened, and does not need OVERWRITE=1.
describe RedmineProjectWorkflows::Services::WorkflowRestore do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:backup) { RedmineProjectWorkflows::Services::WorkflowBackup }
  let(:writer) { RedmineProjectWorkflows::Services::TransitionWriter }
  let(:reached) { projects(:projects_001) }
  let(:interrupted) { projects(:projects_002) }
  let(:later) { projects(:projects_003) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:targets) { [reached, interrupted, later] }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    targets.each do |target|
      give_own_workflow(target, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: target.id,
                                 old_status_id: s1.id, new_status_id: s2.id)
    end
  end

  # What a downgrade leaves behind, without running one.
  def discard_project_workflows
    WorkflowRule.where.not(project_id: nil).delete_all
    ProjectWorkflowScope.where.not(project_id: nil).delete_all
  end

  # The interruption, injected where one really lands: the restore is a
  # sequence of writer calls, and the machine stops between two of them. Raising
  # from the writer rather than stubbing the database keeps the example the same
  # on PostgreSQL, MySQL and SQLite -- what is under test is the transaction
  # boundary, not any one adapter's failure mode.
  #
  # Once, not always, so that the retry in the examples below is the operator's
  # real second run rather than a mock being taken away between them.
  def interrupt_writing_once_for(target)
    original = writer.method(:replace_transitions_for_project_id)
    fired = false
    allow(writer).to receive(:replace_transitions_for_project_id) do |project_id, *rest|
      if project_id == target.id && !fired
        fired = true
        raise ActiveRecord::StatementInvalid, 'simulated: connection lost'
      end

      original.call(project_id, *rest)
    end
  end

  def rules_for(target)
    WorkflowTransition.where(project_id: target.id).pluck(:old_status_id, :new_status_id)
  end

  describe 'an interrupted restore' do
    it 'leaves the combination it could not write inheriting, not owning an empty workflow' do
      document = backup.document
      discard_project_workflows
      interrupt_writing_once_for(interrupted)

      described_class.call(document)

      # The distinction INV-3 exists for. A scope with no rules under it would
      # be a project that has decided it permits no transition at all -- an
      # answer this restore never had the right to give on its behalf.
      expect(own_workflow?(interrupted, tracker, role)).to be(false)
      expect(rules_for(interrupted)).to be_empty
    end

    it 'restores every other combination rather than stopping at the failure' do
      document = backup.document
      discard_project_workflows
      interrupt_writing_once_for(interrupted)

      report = described_class.call(document)

      expect(report.scopes).to eq(2)
      expect(rules_for(reached)).to eq([[s1.id, s2.id]])
      expect(rules_for(later)).to eq([[s1.id, s2.id]])
    end

    # A number does not say which project, and "which project" is the whole of
    # what the operator has to act on.
    it 'names what failed instead of counting it as left alone' do
      document = backup.document
      discard_project_workflows
      interrupt_writing_once_for(interrupted)

      report = described_class.call(document)

      expect(report).to be_failed
      expect(report.skipped_existing).to eq(0)
      expect(report.failed.join)
        .to match(/project #{interrupted.id}, tracker #{tracker.id}, role #{role.id}, transitions/)
      expect(report.lines.join("\n")).to include('run the restore again to retry them')
    end

    # The audit stamp is the last statement a combination runs, so a failure
    # there rolls back rules that were written a moment earlier. A report built
    # inside the transaction counted such a combination as restored *and* as
    # failed, which is worse than either -- an operator reading it would see
    # everything accounted for twice and no way to tell which number was true.
    it 'counts nothing for a combination whose last statement failed' do
      document = backup.document
      discard_project_workflows
      allow(described_class).to receive(:stamp_audit).and_wrap_original do |original, key, *rest|
        raise ActiveRecord::StatementInvalid, 'simulated: the commit never came' if key.first == interrupted.id

        original.call(key, *rest)
      end

      report = described_class.call(document)

      expect(report.scopes).to eq(2)
      expect(report.rules).to eq(2)
      expect(report.failed.size).to eq(1)
      expect(own_workflow?(interrupted, tracker, role)).to be(false)
      expect(rules_for(interrupted)).to be_empty
    end
  end

  describe 'running the same command again, which is what the README says to do' do
    it 'restores what failed and leaves what succeeded alone, without OVERWRITE' do
      document = backup.document
      discard_project_workflows
      interrupt_writing_once_for(interrupted)
      described_class.call(document)

      report = described_class.call(document)

      expect(report).not_to be_failed
      expect(report.scopes).to eq(1)
      expect(report.skipped_existing).to eq(2)
      expect(own_workflow?(interrupted, tracker, role)).to be(true)
      expect(rules_for(interrupted)).to eq([[s1.id, s2.id]])
    end

    it 'ends with every project holding exactly what the backup held' do
      before_rules = WorkflowRule.where.not(project_id: nil)
                                 .pluck(:project_id, :old_status_id, :new_status_id).sort
      before_scopes = ProjectWorkflowScope.where.not(project_id: nil)
                                          .pluck(:project_id, :tracker_id, :role_id, :rule_type).sort
      document = backup.document
      discard_project_workflows

      interrupt_writing_once_for(interrupted)
      described_class.call(document)
      described_class.call(document)

      expect(WorkflowRule.where.not(project_id: nil)
                         .pluck(:project_id, :old_status_id, :new_status_id).sort).to eq(before_rules)
      expect(ProjectWorkflowScope.where.not(project_id: nil)
                                 .pluck(:project_id, :tracker_id, :role_id, :rule_type).sort)
        .to eq(before_scopes)
    end

    # An interruption during an OVERWRITE run is the other half: there the
    # combination already had a scope, and the rollback has to put its rules
    # back rather than leave the project with the empty workflow that clearing
    # them created.
    it 'rolls an overwritten combination back to the rules it already had' do
      document = backup.document
      WorkflowRule.where(project_id: interrupted.id).delete_all
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: interrupted.id,
                                 old_status_id: s2.id, new_status_id: s1.id)
      interrupt_writing_once_for(interrupted)

      described_class.call(document, overwrite: true)

      expect(own_workflow?(interrupted, tracker, role)).to be(true)
      expect(rules_for(interrupted)).to eq([[s2.id, s1.id]])
    end
  end
end
