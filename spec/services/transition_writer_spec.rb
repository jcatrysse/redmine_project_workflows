# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::TransitionWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:other_status) { issue_statuses(:issue_statuses_003) }

  # A project write goes into a scope that already exists and never creates one
  # (INV-3): taking a workflow over is one of the three actions of ScopeWriter,
  # not a side effect of pressing Save. Every example below that writes into a
  # project therefore has to arrange the decision first, exactly as the screens
  # do.
  before { give_own_workflow(project, tracker, role) }

  # F02 (2026-08-27-bundled-followup) asked what a Hash whose keys are not
  # Strings should mean, since that is the other shape Rails can produce and
  # neither controller guard named it. Decided here rather than left unmentioned:
  # **the writers accept any key that answers to_s and to_i, and normalise what
  # survives the whitelist to Strings.** No request can produce a non-String key
  # -- Rails always hands over Strings -- but core's own
  # WorkflowTransition.replace_transitions is routed through this writer (INV-1),
  # so a plugin or a script may.
  #
  # The alternative, coercing keys in the two controller guards, was rejected: the
  # internal API does not pass through them, so it would fix the shape only where
  # it cannot arrive. Normalising inside the sanitizer is the same thing this file
  # already does one level deeper, where the *rule* key is normalised so that
  # everything below can ask `key?(ALWAYS)` reliably.
  #
  # Symbol keys are the case that made this worth doing rather than documenting:
  # they passed the whitelist (`:"1".to_s` is `"1"`) and then reached
  # `submitted_pairs`, where `Symbol#to_i` does not exist -- a 500 from a payload
  # the whitelist had accepted.

  # Finding F04 of 2026-08-28-claude-audit. `MatrixParams#to_plain_hash` and
  # `WorkflowsControllerPatch#to_plain_hash` were both corrected to ask what a
  # payload **is** rather than what it answers to, because `Array` answers
  # `respond_to?(:to_h)` yes and then raises `TypeError`. These two writers were
  # the copies that did not move.
  #
  # Not reachable from either screen -- both controllers convert first -- but
  # INV-1 routes core's own `replace_transitions` through here, so a neighbouring
  # plugin, a rake task or a console reaches it. A validator that raises has not
  # rejected.
  describe 'a payload that is not a matrix at all' do
    # Red on the old code: TypeError, "wrong element type String at 0
    # (expected array)".
    it 'rejects an array rather than raising' do
      result = nil
      expect { result = described_class.replace_transitions(project, [tracker], [role], ['x']) }.not_to raise_error
      expect(result.written).to eq(0)
      expect(result.skipped).to eq(0)
      expect(result.rejected).to eq(0)
    end

    # Red on the old code in a different way: a String answered `respond_to?(:to_h)`
    # false and fell through untouched, so the whitelist raised NoMethodError on
    # it one method later.
    it 'rejects a string rather than raising' do
      result = nil
      expect { result = described_class.replace_transitions(project, [tracker], [role], 'x') }.not_to raise_error
      expect(result.written).to eq(0)
    end

    it 'rejects a scalar rather than raising' do
      result = nil
      expect { result = described_class.replace_transitions(project, [tracker], [role], 7) }.not_to raise_error
      expect(result.written).to eq(0)
    end

    it 'writes nothing for any of them' do
      described_class.replace_transitions(project, [tracker], [role], ['x'])
      described_class.replace_transitions(project, [tracker], [role], 'x')
      expect(WorkflowTransition.count).to eq(0)
    end
  end

  describe 'a payload whose keys are not strings' do
    def rows_for(project_id = project.id)
      WorkflowTransition.where(project_id: project_id)
                        .pluck(:old_status_id, :new_status_id, :author, :assignee)
    end

    it 'writes integer keys as the same rows as string keys' do
      described_class.replace_transitions(
        project, [tracker], [role],
        status.id => { new_status.id => { 'always' => '1' } }
      )

      expect(rows_for).to eq([[status.id, new_status.id, false, false]])
    end

    it 'writes symbol keys as the same rows as string keys' do
      described_class.replace_transitions(
        project, [tracker], [role],
        status.id.to_s.to_sym => { new_status.id.to_s.to_sym => { author: '1' } }
      )

      expect(rows_for).to eq([[status.id, new_status.id, true, false]])
    end

    # And the count the screen reports is unaffected by how the keys were
    # spelled: one leaf submitted, one refused.
    it 'counts the leaves of a non-string-keyed payload' do
      result = described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        status.id => { new_status.id => { always: '1', author: 'not_a_value' } }
      )

      expect(result).to have_attributes(written: 1, rejected: 1)
    end
  end

  it 'stores a single author/assignee row when both are enabled' do
    transitions = {
      status.id.to_s => {
        new_status.id.to_s => {
          'always' => '0',
          'author' => '1',
          'assignee' => '1'
        }
      }
    }

    described_class.replace_transitions(project, [tracker], [role], transitions)

    rows = WorkflowTransition.where(project_id: project.id)
    expect(rows.count).to eq(1)
    expect(rows.first).to have_attributes(author: true, assignee: true)
  end

  it 'stores separate always and author rows when both are enabled' do
    transitions = {
      status.id.to_s => {
        new_status.id.to_s => {
          'always' => '1',
          'author' => '1',
          'assignee' => '0'
        }
      }
    }

    described_class.replace_transitions(project, [tracker], [role], transitions)

    rows = WorkflowTransition.where(project_id: project.id).order(:author, :assignee)
    expect(rows.count).to eq(2)
    expect(rows.map { |row| [row.author, row.assignee] }).to contain_exactly([false, false], [true, false])
  end

  it 'replaces transitions only for the provided status/new status pairs' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: other_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    transitions = {
      status.id.to_s => {
        new_status.id.to_s => {
          'always' => '1',
          'author' => '0',
          'assignee' => '0'
        }
      }
    }

    described_class.replace_transitions(project, [tracker], [role], transitions)

    expect(
      WorkflowTransition.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: other_status.id,
        new_status_id: new_status.id,
        project_id: project.id
      )
    ).to exist
  end

  # WP0 / external F05. insert_all runs no validations, so the whitelist in
  # the writer is the validation -- including core's
  # validates_presence_of :new_status, which the plugin's routing of
  # WorkflowTransition.replace_transitions had removed from the generic write
  # path too. INV-2.
  describe 'server-side validation' do
    it 'rejects a new status id that does not exist' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { '999999' => { 'always' => '1' } } })

      expect(WorkflowTransition.where(new_status_id: 999_999)).not_to exist
    end

    it 'rejects an old status id that does not exist' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { '999999' => { new_status.id.to_s => { 'always' => '1' } } })

      expect(WorkflowTransition.where(old_status_id: 999_999)).not_to exist
    end

    # 0 is not an IssueStatus: it is how core stores a transition out of the
    # "new issue" pseudo status, and it has to keep working.
    it 'accepts the new-issue pseudo status' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { '0' => { new_status.id.to_s => { 'always' => '1' } } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: 0,
                                 new_status_id: new_status.id)
      ).to exist
    end

    it 'rejects a rule name the matrix cannot produce' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => { 'nobody' => '1' } } })

      expect(WorkflowTransition.where(project_id: project.id)).not_to exist
    end

    # A rejected value is dropped before the delete, not only before the
    # insert, so an unacceptable cell value cannot remove a transition.
    it 'leaves the stored transition alone when an unknown cell value arrives' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: false, assignee: false
      )

      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => { 'always' => 'bogus' } } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                                 new_status_id: new_status.id)
      ).to exist
    end

    # The controller strips 'no_change' before it reaches the writer, so a cell
    # the administrator left alone arrives as an empty rule hash. That used to
    # still contribute to the delete and then insert nothing, which turned
    # "leave this as it is" into "remove it".
    it 'leaves a transition alone when every rule for the cell says no change' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: false, assignee: false
      )

      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => {} } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                                 new_status_id: new_status.id)
      ).to exist
    end

    it 'still removes a transition when the request clears it' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: false, assignee: false
      )

      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => { 'always' => '0' } } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                                 new_status_id: new_status.id)
      ).not_to exist
    end
  end

  # WP1, amended by this session: a project write records that somebody changed
  # the rules, and records **nothing else**. It never creates the decision.
  #
  # Until now the writer created the scope a project write implied, which is how
  # a plain Save on the administration matrix -- where an inheriting project
  # renders as an empty grid -- gave that project an own *empty* workflow, in
  # which no issue can change status at all. ADR-001 names that state as the one
  # to keep unreachable by accident, and ProjectWorkflowsController has refused
  # such a save since WP4. Now the writer refuses it too, whichever screen asked.
  describe 'the scope a project write records' do
    let(:inheriting_role) { roles(:roles_002) }

    it 'writes nothing for a combination that still inherits, and says how many' do
      result = described_class.replace_transitions_for_project_id(
        project.id, [tracker], [inheriting_role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )

      expect(result.skipped).to eq(1)
      expect(result.written).to eq(0)
      expect(WorkflowTransition.where(project_id: project.id, role_id: inheriting_role.id)).to be_empty
      expect(own_workflow?(project, tracker, inheriting_role)).to be(false)
    end

    it 'writes the combinations that do have a scope and skips only the rest' do
      result = described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role, inheriting_role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )

      expect(result.skipped).to eq(1)
      expect(result.written).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:role_id)).to eq([role.id])
    end

    it 'creates none for a generic write' do
      expect do
        described_class.replace_transitions_for_project_id(
          nil, [tracker], [role],
          { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
        )
      end.not_to change(ProjectWorkflowScope, :count)
    end

    # INV-3 again: clearing the last rule is not the same as returning the
    # project to the generic workflow, so the scope stays.
    it 'survives a save that removes every rule' do
      described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )
      described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '0' } } }
      )

      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(own_workflow?(project, tracker, role)).to be(true)
    end

    it 'creates none when the whole submission was rejected' do
      expect do
        described_class.replace_transitions_for_project_id(
          project.id, [tracker], [role],
          { status.id.to_s => { new_status.id.to_s => { 'sometimes' => '1' } } }
        )
      end.not_to change(ProjectWorkflowScope, :count)
    end
  end

  # The defect this session found. One cell of the transitions matrix is three
  # controls -- always, author, assignee -- over two stored rows, and each of the
  # three can independently arrive as "no change", which the controller strips
  # before the writer sees it. The delete was keyed on (old status, new status)
  # alone, so any surviving rule put the whole cell in the delete list and took
  # the rows nobody had asked about with it.
  #
  # Red on the old code: the first two examples. Core's own
  # WorkflowTransition.replace_transitions keeps both rows in these cases, so
  # this is where the plugin's routing of that method had changed what a generic
  # save does as well.
  describe 'a cell whose columns disagree about being left alone' do
    def store(author:, assignee:)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: author, assignee: assignee
      )
    end

    def write(rules)
      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => rules } })
    end

    # Sorted by hand: booleans are not Comparable, so Array#sort raises on a
    # pair of them.
    def stored
      WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                               new_status_id: new_status.id)
                        .pluck(:author, :assignee)
                        .sort_by { |author, assignee| [author ? 1 : 0, assignee ? 1 : 0] }
    end

    it 'keeps the unconditional row when only the author and assignee columns were submitted' do
      store(author: false, assignee: false)

      write('author' => '0', 'assignee' => '0')

      expect(stored).to eq([[false, false]])
    end

    it 'keeps the author row when only the unconditional column was submitted' do
      store(author: false, assignee: false)
      store(author: true, assignee: false)

      write('always' => '1')

      expect(stored).to eq([[false, false], [true, false]])
    end

    # The finer half of the same rule: author and assignee share one row, so a
    # submitted author column must not reset an assignee flag that was left at
    # "no change". Core mutates the row rather than replacing it, and this is
    # how the plugin reproduces that.
    it 'keeps the assignee flag when only the author column was submitted' do
      store(author: false, assignee: true)

      write('author' => '1')

      expect(stored).to eq([[true, true]])
    end

    it 'keeps the author flag when only the assignee column was submitted' do
      store(author: true, assignee: false)

      write('assignee' => '1')

      expect(stored).to eq([[true, true]])
    end

    it 'still clears the shared row when the last of its two flags is switched off' do
      store(author: true, assignee: false)

      write('author' => '0')

      expect(stored).to be_empty
    end

    it 'writes a new author row where none was stored' do
      write('author' => '1')

      expect(stored).to eq([[true, false]])
    end

    # Nothing constrains the table against two flag rows for one cell -- that is
    # what rake redmine_project_workflows:deduplicate_workflow_rules exists for.
    # Reading them to preserve a flag left at "no change" therefore has to answer
    # the same way on every database, so the flags are OR-ed rather than one row
    # being picked: picking would depend on the order the rows came back in, and
    # OR is what the matrix already draws, since either flag renders as checked.
    it 'merges two stored rows for one cell rather than picking one of them' do
      store(author: true, assignee: false)
      store(author: false, assignee: true)

      write('author' => '1')

      expect(stored).to eq([[true, true]])
    end
  end

  # F06 (2026-08-27-bundled). MatrixSaveResult carried two counts, and they
  # covered all-or-nothing: a save whose whitelist dropped *some* entries had a
  # positive `written`, so it was indistinguishable from one that applied
  # everything. The README promises that an unacceptable value leaves the rule it
  # names alone *and the screen says so* -- true for the empty case since the
  # earlier F06, and not for the middle.
  describe 'the values the whitelist dropped' do
    def save(matrix)
      described_class.replace_transitions_for_project_id(project.id, [tracker], [role], matrix)
    end

    it 'counts a rejected value in a payload whose other values are written' do
      result = save(
        status.id.to_s => {
          new_status.id.to_s => { 'always' => '1', 'bogus_rule' => '1' }
        }
      )

      expect(result).to have_attributes(written: 1, skipped: 0, rejected: 1)
    end

    # And the rule the rejected value named is untouched, which is the promise
    # the count exists to report rather than to change.
    it 'leaves the rule a rejected value names alone' do
      save(status.id.to_s => { new_status.id.to_s => { 'always' => '1' } })

      expect do
        save(status.id.to_s => { new_status.id.to_s => { 'always' => 'not_a_value' } })
      end.not_to change(WorkflowTransition, :count)
    end

    it 'counts every rejected leaf, not every rejected cell' do
      result = save(
        status.id.to_s => {
          new_status.id.to_s => { 'always' => 'nope', 'author' => 'nope' },
          '999999' => { 'always' => '1' }
        }
      )

      expect(result.rejected).to eq(3)
    end

    it 'reports nothing rejected for a payload the whitelist kept whole' do
      result = save(status.id.to_s => { new_status.id.to_s => { 'always' => '1' } })

      expect(result).to have_attributes(written: 1, rejected: 0)
      expect(result).not_to be_rejected
    end

    # The empty case the earlier F06 fixed still answers as it did, and now also
    # says how much was dropped.
    it 'still reports nothing applied when the whitelist emptied the payload' do
      result = save(status.id.to_s => { new_status.id.to_s => { 'always' => 'nope' } })

      expect(result).to be_nothing_applied
      expect(result.rejected).to eq(1)
    end
  end
end
