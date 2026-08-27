# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::ScopeWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:project) { projects(:projects_001) }
  let(:other) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:second_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:second_tracker) { trackers(:trackers_002) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }
  let(:transitions) { ProjectWorkflowScope::TRANSITIONS }
  let(:permissions) { ProjectWorkflowScope::PERMISSIONS }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def generic_transition(from = s1, to = s2, for_role = role)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: for_role.id,
                               old_status_id: from.id, new_status_id: to.id, project_id: nil)
  end

  def project_transition(target = project, from = s1, to = s2)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: from.id, new_status_id: to.id, project_id: target.id)
  end

  def call(action, **overrides)
    described_class.public_send(
      action,
      project_ids: [project.id], tracker_ids: [tracker.id],
          role_ids: [role.id], rule_type: transitions, **overrides
    )
  end

  describe '.enable' do
    it 'creates the scope and copies the generic rules' do
      generic_transition(s1, s2)
      generic_transition(s2, s1)

      expect(call(:enable)).to eq(1)

      expect(own_workflow?(project, tracker, role)).to be(true)
      copied = WorkflowTransition.where(project_id: project.id).pluck(:old_status_id, :new_status_id)
      expect(copied).to contain_exactly([s1.id, s2.id], [s2.id, s1.id])
      expect(WorkflowTransition.where(project_id: nil).count).to eq(2)
    end

    it 'creates an empty scope when the copy is declined' do
      generic_transition

      expect(call(:enable, copy_generic: false)).to eq(1)

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
    end

    # INV-3: enabling is not the same as copying again. A second press must not
    # throw away what the first one produced.
    it 'leaves an existing scope and its rules alone' do
      generic_transition
      call(:enable)
      WorkflowTransition.where(project_id: project.id).delete_all
      project_transition(project, s2, s1)

      expect(call(:enable)).to eq(0)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:old_status_id, :new_status_id))
        .to eq([[s2.id, s1.id]])
    end

    it 'copies only the rule type it is asked for' do
      generic_transition
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: s1.id,
                                 field_name: 'due_date', rule: 'required', project_id: nil)

      call(:enable)

      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
      expect(WorkflowPermission.where(project_id: project.id)).to be_empty
      expect(own_workflow?(project, tracker, role, permissions)).to be(false)
    end

    it 'copies the generic rules of each role separately' do
      generic_transition(s1, s2, role)
      generic_transition(s2, s1, second_role)

      expect(call(:enable, role_ids: [role.id, second_role.id])).to eq(2)

      expect(WorkflowTransition.where(project_id: project.id, role_id: role.id)
        .pluck(:old_status_id, :new_status_id)).to eq([[s1.id, s2.id]])
      expect(WorkflowTransition.where(project_id: project.id, role_id: second_role.id)
        .pluck(:old_status_id, :new_status_id)).to eq([[s2.id, s1.id]])
    end

    it 'never touches another project' do
      generic_transition
      project_transition(other)
      give_own_workflow(other, tracker, role)

      call(:enable)

      expect(WorkflowTransition.where(project_id: other.id).count).to eq(1)
      expect(own_workflow?(other, tracker, role)).to be(true)
    end
  end

  describe '.return_to_inheritance' do
    it 'deletes the scope and the rules' do
      generic_transition
      call(:enable)

      expect(call(:return_to_inheritance)).to eq(1)

      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
    end

    it 'leaves the other rule type standing' do
      give_own_workflow(project, tracker, role, transitions)
      give_own_workflow(project, tracker, role, permissions)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: s1.id,
                                 field_name: 'due_date', rule: 'required', project_id: project.id)

      call(:return_to_inheritance)

      expect(own_workflow?(project, tracker, role, permissions)).to be(true)
      expect(WorkflowPermission.where(project_id: project.id).count).to eq(1)
    end

    it 'reports nothing done when the project already inherits' do
      expect(call(:return_to_inheritance)).to eq(0)
    end
  end

  describe '.clear_rules' do
    it 'keeps the scope and deletes the rules' do
      generic_transition
      call(:enable)

      expect(call(:clear_rules)).to eq(1)

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
    end

    it 'records who emptied it' do
      give_own_workflow(project, tracker, role)

      call(:clear_rules, user: users(:users_002))

      expect(ProjectWorkflowScope.first.updated_by_id).to eq(users(:users_002).id)
    end

    # Emptying a matrix the project does not own would read as a change while
    # leaving it inheriting -- exactly the confusion the scope table ends.
    it 'does nothing when the project has no scope' do
      project_transition

      expect(call(:clear_rules)).to eq(0)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
    end
  end

  # `.ensure_scopes` is gone. It created the scope a project write implied, on
  # behalf of the two rule writers, and that is exactly what made a plain Save
  # on the administration matrix hand an inheriting project an own **empty**
  # workflow. Creating a scope is now `.enable` and nothing else (INV-3), so
  # what that method used to be held to is asserted here of `.enable`.
  describe '.enable, as the only thing that creates a scope' do
    it 'creates one per tracker and role and records who did it' do
      user = users(:users_002)

      described_class.enable(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id, second_role.id], rule_type: transitions, user: user
      )

      scopes = ProjectWorkflowScope.where(project_id: project.id, rule_type: transitions)
      expect(scopes.pluck(:role_id)).to contain_exactly(role.id, second_role.id)
      expect(scopes.pluck(:created_by_id).uniq).to eq([user.id])
    end

    it 'is idempotent and leaves the first decision intact' do
      described_class.enable(
        project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: transitions, user: users(:users_002)
      )

      described_class.enable(
        project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: transitions, user: users(:users_003)
      )

      expect(ProjectWorkflowScope.count).to eq(1)
      expect(ProjectWorkflowScope.first.created_by_id).to eq(users(:users_002).id)
    end

    it 'records nothing when no project was named' do
      described_class.enable(
        project_ids: [nil], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: transitions, user: User.anonymous
      )

      expect(ProjectWorkflowScope.count).to eq(0)
    end

    it 'leaves created_by empty for an anonymous write' do
      described_class.enable(
        project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: transitions, user: User.anonymous
      )

      expect(ProjectWorkflowScope.first.created_by_id).to be_nil
    end

    # 0.1.1 put the rows in with insert_all, which runs no validations; the
    # guard that replaced them is still in front of the loop, because a rule
    # type nothing can read has to fail the call rather than be reported, row
    # by row, as a combination somebody else had already created.
    it 'refuses a rule type nothing can read' do
      expect do
        described_class.enable(
          project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
          rule_type: 'something_else'
        )
      end.to raise_error(ArgumentError)
    end

    # F01, and the reason the whole method was rewritten. A second
    # administrator pressed the same button first: by the time this call gets
    # to the INSERT, the combination is scoped and the winner's rules are in
    # the table. The loser must create nothing, count nothing, and -- the part
    # that actually damages data -- must not clear the winner's rules and copy
    # the generic ones over them.
    #
    # The race is arranged by making .missing_combinations answer as it did
    # before the winner committed, which is exactly the stale answer the real
    # race produces. With insert_all the row was silently dropped (it is
    # INSERT ... ON CONFLICT DO NOTHING) and the combination reported created
    # regardless.
    it 'creates nothing for a scope that appeared after the check' do
      allow(described_class).to receive(:missing_combinations)
        .and_return([[project.id, tracker.id, role.id]])
      give_own_workflow(project, tracker, role)
      project_transition(project, s2, s1)
      generic_transition(s1, s2)

      expect(call(:enable)).to eq(0)

      expect(WorkflowTransition.where(project_id: project.id).pluck(:old_status_id, :new_status_id))
        .to contain_exactly([s2.id, s1.id])
      expect(ProjectWorkflowScope.count).to eq(1)
    end

    # The narrower half of the same race: the winner commits between the
    # uniqueness validation's SELECT and this INSERT, so the unique index is
    # what stops the duplicate and the failure arrives as RecordNotUnique. On
    # PostgreSQL a failed statement makes every later statement of the same
    # transaction fail too, which is why the row is written inside a savepoint
    # -- without it the rest of the selection would go down with the one lost
    # race. The callback stands in for the second connection; insert_all ran no
    # callbacks at all, so this could not even be asked of the old code.
    it 'goes on to the rest of the selection when one row loses the race' do
      raced = false
      race = lambda do |record|
        next if raced || record.role_id != role.id

        raced = true
        raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint'
      end
      ProjectWorkflowScope.set_callback(:create, :before, race)

      begin
        created = described_class.enable(
          project_ids: [project.id], tracker_ids: [tracker.id],
          role_ids: [role.id, second_role.id], rule_type: transitions, copy_generic: false
        )
      ensure
        ProjectWorkflowScope.skip_callback(:create, :before, race, raise: false)
      end

      expect(created).to eq(1)
      expect(ProjectWorkflowScope.pluck(:role_id)).to eq([second_role.id])
    end

    # A duplicate is the *only* validation failure that counts as "somebody
    # else got here first". Anything else is a bug, and swallowing it would
    # turn a rejected row into a silently skipped one -- which is how a save
    # comes to report success over a table it never wrote to.
    it 'raises rather than skipping a row the model rejects' do
      allow(described_class).to receive(:missing_combinations)
        .and_return([[project.id, nil, role.id]])

      expect { call(:enable) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(ProjectWorkflowScope.count).to eq(0)
    end

    it 'writes every combination of a large selection' do
      described_class.enable(
        project_ids: [project.id, other.id], tracker_ids: [tracker.id],
        role_ids: [role.id, second_role.id], rule_type: transitions, copy_generic: false
      )

      expect(ProjectWorkflowScope.count).to eq(4)
      expect(ProjectWorkflowScope.pluck(:created_at).compact.size).to eq(4)
    end
  end

  describe 'the cache the resolver keeps' do
    it 'is invalidated when a scope appears' do
      generic_transition
      issue = Issue.new(project: project, tracker: tracker, status: s1, author: users(:users_002))
      RedmineProjectWorkflows::Services::Resolver.new(
        project_id: project.id, tracker_id: tracker.id, role_ids: [role.id]
      ).overridden_role_ids_for(WorkflowTransition)

      call(:enable, copy_generic: false)

      expect(
        RedmineProjectWorkflows::Services::Resolver.new(
          project_id: project.id, tracker_id: tracker.id, role_ids: [role.id]
        ).overridden_role_ids_for(WorkflowTransition)
      ).to eq([role.id])
      expect(issue).to be_present
    end

    it 'is invalidated when a scope goes' do
      give_own_workflow(project, tracker, role)
      RedmineProjectWorkflows::Services::Resolver.scoped_role_ids(
        project_id: project.id, tracker_id: tracker.id, rule_type: transitions
      )

      call(:return_to_inheritance)

      expect(
        RedmineProjectWorkflows::Services::Resolver.scoped_role_ids(
          project_id: project.id, tracker_id: tracker.id, rule_type: transitions
        )
      ).to eq([])
    end
  end

  describe '.ensure_scopes_for_copy' do
    # The copy screen writes rules straight into a project. Without a scope the
    # resolver ignores every one of them (INV-3).
    it 'records a scope where rules arrived' do
      project_transition
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, old_status_id: s1.id,
                                 field_name: 'due_date', rule: 'required', project_id: project.id)

      described_class.ensure_scopes_for_copy(
        combinations: [[project.id, tracker.id, role.id]]
      )

      expect(own_workflow?(project, tracker, role, transitions)).to be(true)
      expect(own_workflow?(project, tracker, role, permissions)).to be(true)
    end

    # An empty transitions scope would stop every issue in the project from
    # changing status, so a rule type that received nothing gets no scope.
    it 'records nothing for a rule type that received no rules' do
      project_transition

      described_class.ensure_scopes_for_copy(
        combinations: [[project.id, tracker.id, role.id]]
      )

      expect(own_workflow?(project, tracker, role, transitions)).to be(true)
      expect(own_workflow?(project, tracker, role, permissions)).to be(false)
    end

    it 'records nothing for a project that received nothing' do
      project_transition(other)

      described_class.ensure_scopes_for_copy(
        combinations: [[project.id, tracker.id, role.id], [other.id, tracker.id, role.id]]
      )

      expect(own_workflow?(project, tracker, role, transitions)).to be(false)
      expect(own_workflow?(other, tracker, role, transitions)).to be(true)
    end

    it 'leaves an existing scope untouched' do
      give_own_workflow(project, tracker, role, transitions)
      project_transition

      expect do
        described_class.ensure_scopes_for_copy(
          combinations: [[project.id, tracker.id, role.id]]
        )
      end.not_to change(ProjectWorkflowScope, :count)
    end
  end
  # WP6. The two halves of the audit trail answer different questions, and a
  # repeated save has to move one of them without moving the other.
  describe 'the audit trail' do
    let(:author) { users(:users_002) }
    let(:editor) { users(:users_003) }

    def scope_row
      ProjectWorkflowScope.find_by!(project_id: project.id, tracker_id: tracker.id,
                                    role_id: role.id, rule_type: transitions)
    end

    it 'stamps both halves when it creates the scope' do
      described_class.enable(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id], rule_type: transitions, user: author
      )

      row = scope_row
      expect(row.created_by_id).to eq(author.id)
      expect(row.updated_by_id).to eq(author.id)
    end

    it 'records who changed the rules without rewriting who made the decision' do
      described_class.enable(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id], rule_type: transitions, user: author
      )
      created_at = scope_row.created_at

      described_class.touch_scopes(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id], rule_type: transitions, user: editor
      )

      row = scope_row
      expect(row.created_by_id).to eq(author.id)
      expect(row.updated_by_id).to eq(editor.id)
      # eq, not be_within: created_at is read back from the same row, so a
      # tolerance would let a stamp that rewrote it pass. And updated_at has to
      # have moved, or "who last changed the rules" is not being recorded at all.
      expect(row.created_at).to eq(created_at)
      expect(row.updated_at).to be >= row.created_at
    end

    # A project matrix save routes through the writers, which is the path an
    # ordinary edit takes; this is what makes the inventory's line true.
    it 'is stamped by a save through TransitionWriter' do
      give_own_workflow(project, tracker, role, transitions)
      User.current = editor

      RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
        project.id, [tracker], [role], { s1.id.to_s => { s2.id.to_s => { 'always' => '1' } } }
      )

      expect(scope_row.updated_by_id).to eq(editor.id)
    ensure
      User.current = nil
    end

    it 'is stamped by emptying the matrix' do
      give_own_workflow(project, tracker, role, transitions)
      project_transition

      described_class.clear_rules(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id], rule_type: transitions, user: editor
      )

      expect(scope_row.updated_by_id).to eq(editor.id)
    end

    # A copy into a project that already has a scope rewrites its rules and
    # creates nothing, so without a stamp the audit line would go on naming
    # whoever last saved the matrix by hand.
    it 'is stamped by a copy into a project that already has a scope' do
      give_own_workflow(project, tracker, role, transitions)
      project_transition

      described_class.ensure_scopes_for_copy(
        combinations: [[project.id, tracker.id, role.id]], user: editor
      )

      expect(scope_row.updated_by_id).to eq(editor.id)
    end

    # ...and it still must not create one where the copy landed nothing, because
    # a scope with no rules is an own *empty* workflow (INV-3).
    it 'creates no scope for a project a copy did not reach' do
      expect do
        described_class.ensure_scopes_for_copy(
          combinations: [[project.id, tracker.id, role.id]], user: editor
        )
      end.not_to change(ProjectWorkflowScope, :count)
    end

    # F04. .touch_combinations is the copy path's stamp, and the difference from
    # .touch_scopes is the shape of the selection: exact triples rather than the
    # cross product of three id lists. The example arranges two diagonal
    # combinations and asserts that the two the cross product would add are
    # untouched -- which is the stamp the copy screen used to leave.
    it 'stamps exactly the combinations it was given, not their cross product' do
      diagonal = [give_own_workflow(project, tracker, role, transitions),
                  give_own_workflow(project, second_tracker, second_role, transitions)]
      off_diagonal = [give_own_workflow(project, tracker, second_role, transitions),
                      give_own_workflow(project, second_tracker, role, transitions)]

      described_class.touch_combinations(
        [[project.id, tracker.id, role.id], [project.id, second_tracker.id, second_role.id]],
        transitions, editor
      )

      expect(diagonal.map { |scope| scope.reload.updated_by_id }).to eq([editor.id, editor.id])
      expect(off_diagonal.map { |scope| scope.reload.updated_by_id }).to eq([nil, nil])
    end

    it 'stamps nothing at all for an empty set of combinations' do
      scope = give_own_workflow(project, tracker, role, transitions)

      expect(described_class.touch_combinations([], transitions, editor)).to eq(0)
      expect(scope.reload.updated_by_id).to be_nil
    end

    # INV-3: touching must never be a way of taking a workflow over. A
    # combination that inherits has no row, and nothing here creates one.
    it 'stamps nothing where the project inherits' do
      expect do
        described_class.touch_scopes(
          project_ids: [project.id], tracker_ids: [tracker.id],
          role_ids: [role.id], rule_type: transitions, user: editor
        )
      end.not_to change(ProjectWorkflowScope, :count)
    end

    # INV-1 / INV-4: the stamp names its selection, so a neighbour's scope is
    # not marked as having been edited.
    it 'leaves another project, tracker, role or rule type alone' do
      give_own_workflow(project, tracker, role, transitions)
      give_own_workflow(other, tracker, role, transitions)
      give_own_workflow(project, tracker, second_role, transitions)
      give_own_workflow(project, tracker, role, permissions)

      described_class.touch_scopes(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id], rule_type: transitions, user: editor
      )

      expect(scope_row.updated_by_id).to eq(editor.id)
      expect(ProjectWorkflowScope.where.not(id: scope_row.id).pluck(:updated_by_id).uniq).to eq([nil])
    end

    # A rake task, a migration or a console has no user, and inventing one would
    # name somebody who was not there.
    it 'records no author for a write with nobody logged in' do
      give_own_workflow(project, tracker, role, transitions)

      described_class.touch_scopes(
        project_ids: [project.id], tracker_ids: [tracker.id],
        role_ids: [role.id], rule_type: transitions, user: User.anonymous
      )

      expect(scope_row.updated_by_id).to be_nil
    end
  end
end
