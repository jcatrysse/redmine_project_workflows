# frozen_string_literal: true

require_relative '../spec_helper'

# WP15 item 4 -- the batched delete at exactly its batch size, on whatever
# database is running.
#
# `ScopeBulkWriter.each_batch_predicate` expresses a delete as an `OR` of exact
# (project, tracker, role) triples, `DELETE_BATCH_SIZE` of them per statement.
# Nothing in the suite had ever built more than a handful of terms, so the size
# that ships was a number nobody had asked a database about. PostgreSQL was
# measured safe to a thousand nested `OR`s during the 2026-08-28 audit; SQLite
# fails well under a hundred, and MySQL and MariaDB -- six of the nine supported
# cells -- were unmeasured.
#
# What makes this a gate rather than a benchmark is that it runs on every cell
# CI has: a database that cannot plan a statement of this shape fails here, on
# the exact size the code uses, rather than on somebody's ten-thousand-project
# installation.
#
# **The padding triples name projects that do not exist, deliberately.** A
# `DELETE` predicate naming an absent id is ordinary SQL -- there is no foreign
# key involved in matching a row -- and creating five hundred real projects
# would make this a spec about `Project`'s callbacks. What has to be real is
# every row the example asserts about, and those are.
describe RedmineProjectWorkflows::Services::ScopeBulkWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:batch) { described_class::DELETE_BATCH_SIZE }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  # Ids nothing has. Taken from the top of each table rather than from fixed
  # numbers, so this cannot collide with a fixture on a host whose sequences have
  # run on.
  #
  # All three vary, and that matters: padding that held one tracker and one role
  # would make the statement's `OR` of triples indistinguishable from an `IN`
  # over each column separately -- which is the wrong shape, and one this file
  # is meant to be able to tell apart.
  def padding_triples(count)
    first_project = Project.maximum(:id).to_i + 1_000
    first_tracker = Tracker.maximum(:id).to_i + 1_000
    first_role = Role.maximum(:id).to_i + 1_000
    Array.new(count) { |index| [first_project + index, first_tracker + index, first_role + index] }
  end

  def rule_for(target, from, to, on_tracker: tracker, for_role: role)
    WorkflowTransition.create!(tracker_id: on_tracker.id, role_id: for_role.id, project_id: target.id,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def delete_statements(&block)
    statements_during(&block).grep(/\A\s*DELETE\s+FROM\s+\W?workflows\b/i)
  end

  describe 'the predicate builder' do
    it 'yields one predicate for exactly a full batch' do
      yielded = []
      described_class.each_batch_predicate(padding_triples(batch), WorkflowTransition.arel_table) do |predicate|
        yielded << predicate
      end

      expect(yielded.size).to eq(1)
    end

    it 'yields two for one triple more' do
      yielded = []
      described_class.each_batch_predicate(padding_triples(batch + 1), WorkflowTransition.arel_table) do |predicate|
        yielded << predicate
      end

      expect(yielded.size).to eq(2)
    end

    it 'yields nothing for no combinations at all' do
      yielded = 0
      described_class.each_batch_predicate([], WorkflowTransition.arel_table) { yielded += 1 }

      expect(yielded).to eq(0)
    end
  end

  # The half that only a real database can answer.
  describe 'the delete this database actually runs' do
    it 'plans and runs a statement of exactly DELETE_BATCH_SIZE terms' do
      rule_for(project, s1, s2)
      combinations = padding_triples(batch - 1) + [[project.id, tracker.id, role.id]]
      expect(combinations.size).to eq(batch)

      statements = delete_statements do
        described_class.delete_rules(combinations, transitions)
      end

      expect(statements.size).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'splits one triple over the batch size into two statements' do
      rule_for(project, s1, s2)
      rule_for(other_project, s1, s2)
      combinations = padding_triples(batch - 1) +
                     [[project.id, tracker.id, role.id], [other_project.id, tracker.id, role.id]]
      expect(combinations.size).to eq(batch + 1)

      statements = delete_statements do
        described_class.delete_rules(combinations, transitions)
      end

      expect(statements.size).to eq(2)
      expect(WorkflowTransition.where(project_id: [project.id, other_project.id]).count).to eq(0)
    end

    # The property the OR-of-triples shape exists for: it is not the cross
    # product of the three id lists, so a combination the caller did not name
    # survives however large the batch is. Asserted at full batch size, because
    # that is the statement whose correctness is hardest to read.
    it 'leaves a combination it was not given, at full batch size' do
      other_tracker = trackers(:trackers_002)
      other_role = roles(:roles_002)
      named = [rule_for(project, s1, s2),
               rule_for(other_project, s1, s2, on_tracker: other_tracker, for_role: other_role)]
      # In the cross product of the three columns the named triples span, and in
      # no named triple: an `IN` per column -- the shape this predicate is
      # deliberately not -- would take it with them.
      spared = rule_for(project, s1, s2, on_tracker: other_tracker, for_role: other_role)
      generic = WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                           old_status_id: s1.id, new_status_id: s2.id)

      combinations = padding_triples(batch - 2) +
                     [[project.id, tracker.id, role.id],
                      [other_project.id, other_tracker.id, other_role.id]]
      expect(combinations.size).to eq(batch)

      described_class.delete_rules(combinations, transitions)

      expect(WorkflowTransition.exists?(spared.id)).to be(true)
      expect(WorkflowTransition.exists?(generic.id)).to be(true)
      named.each { |rule| expect(WorkflowTransition.exists?(rule.id)).to be(false) }
    end

    # The scope table takes the same predicate through a different model, and it
    # carries a `rule_type` condition alongside it -- so its statement is one
    # term wider than the rules table's at every batch size.
    it 'plans and runs the same size of statement against the scope table' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      described_class.delete_scopes(padding_triples(batch - 1) + [[project.id, tracker.id, role.id]],
                                    transitions)

      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
    end
  end
end
