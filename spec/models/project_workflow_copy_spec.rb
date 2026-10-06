# frozen_string_literal: true

require_relative '../spec_helper'

# Copying a project copies its workflow (finding F01 of 2026-08-28, second run).
#
# Before this, Redmine's *Copy project* brought the members, the trackers, the
# categories and the issues across and left the project's own workflow behind,
# so the copy silently ran the generic one -- more permissive than the original,
# which is the wrong direction for a surprise to point in.
#
# Red on the old code: with the hook listener removed (or
# ProjectWorkflowCopier.copy stubbed to return [0, 0]) every example under
# "through Project#copy" and every positive example under "the copier" fails,
# because nothing writes a scope or a rule for the target at all.
describe 'Copying a project' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :enabled_modules, :users

  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:own_only_status) { issue_statuses(:issue_statuses_003) }

  let(:source) do
    Project.create!(name: 'Workflow copy source', identifier: 'wf-copy-source',
                    tracker_ids: [tracker.id, other_tracker.id],
                    enabled_module_names: %w[issue_tracking])
  end

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def transition(project_id:, tracker_id: nil, role_id: nil, from: old_status, to: new_status)
    WorkflowTransition.create!(
      tracker_id: tracker_id || tracker.id, role_id: role_id || role.id,
      old_status_id: from.id, new_status_id: to.id,
      project_id: project_id, author: false, assignee: false
    )
  end

  def permission(project_id:, tracker_id: nil, role_id: nil, field: 'due_date', rule: 'required')
    WorkflowPermission.create!(
      tracker_id: tracker_id || tracker.id, role_id: role_id || role.id,
      old_status_id: old_status.id, field_name: field, rule: rule,
      project_id: project_id
    )
  end

  def copy_of(project, identifier: 'wf-copy-target')
    copy = Project.copy_from(project)
    copy.name = "Copy of #{project.name}"
    copy.identifier = identifier
    raise 'the copy did not save' unless copy.copy(project)

    copy
  end

  describe 'through Project#copy, which is what the Copy button calls' do
    it "carries the project's own workflow, scope and rules together" do
      give_own_workflow(source, tracker, role)
      transition(project_id: source.id)

      copy = copy_of(source)

      expect(own_workflow?(copy, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: copy.id).count).to eq(1)
    end

    # INV-3: create scope / delete scope and rows / keep scope and delete rows
    # are three different things. An own *empty* workflow that came out of the
    # copy as an inheriting one would collapse two of them.
    it 'carries an own empty workflow as an empty one, not as inheritance' do
      give_own_workflow(source, tracker, role)

      copy = copy_of(source)

      expect(own_workflow?(copy, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: copy.id).count).to eq(0)
    end

    # INV-1: a project write never touches generic rows, and the source is not a
    # party to its own copy either.
    it 'leaves the generic workflow and the source alone' do
      give_own_workflow(source, tracker, role)
      transition(project_id: source.id)
      transition(project_id: nil, from: new_status, to: old_status)

      copy = copy_of(source)

      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
      expect(WorkflowTransition.where(project_id: source.id).count).to eq(1)
      expect(ProjectWorkflowScope.where(project_id: source.id).count).to eq(1)
      expect(copy.id).not_to eq(source.id)
    end

    # The checkbox on core's copy form (Jan, 2026-08-28). The first answer to
    # F01 copied the workflow unconditionally; the form has a checkbox for every
    # other kind of content, and core renders a hook inside that very fieldset
    # for a plugin to add one more.
    #
    # Red on the old code: before the checkbox, `only:` had no effect on the
    # workflow at all, so the first two of these three fail -- the unticked case
    # copied anyway, and the "named but not ours" case did too.
    describe 'the copy form checkbox' do
      let(:key) { RedmineProjectWorkflows::Services::ProjectWorkflowCopier::COPY_ONLY_KEY }

      before do
        give_own_workflow(source, tracker, role)
        transition(project_id: source.id)
      end

      def copy_with(only, identifier)
        copy = Project.copy_from(source)
        copy.name = "Copy #{identifier}"
        copy.identifier = identifier
        raise 'the copy did not save' unless copy.copy(source, only: only)

        copy
      end

      # What core's form submits when the box is unticked: the other items, plus
      # the empty string core's own hidden field always sends.
      it 'copies no workflow when the box is unticked' do
        copy = copy_with(%w[members issues], 'wf-copy-unticked')

        expect(ProjectWorkflowScope.where(project_id: copy.id).count).to eq(0)
        expect(WorkflowTransition.where(project_id: copy.id).count).to eq(0)
      end

      it 'copies the workflow when the box is ticked' do
        copy = copy_with(['members', '', key], 'wf-copy-ticked')

        expect(own_workflow?(copy, tracker, role)).to be(true)
        expect(WorkflowTransition.where(project_id: copy.id).count).to eq(1)
      end

      # A console or API caller that passes no :only at all means everything,
      # which is core's own rule for its eight items.
      it 'copies the workflow when nothing was named at all' do
        copy = copy_of(source, identifier: 'wf-copy-unnamed')

        expect(own_workflow?(copy, tracker, role)).to be(true)
      end

      # A hand-built request can put anything there. Anything that is not the
      # key narrows the copy rather than raising or widening it -- the same thing
      # it does to core's own eight items.
      it 'copies no workflow for an only list that is not a list of strings' do
        copy = copy_with({ 'x' => 'y' }, 'wf-copy-malformed')

        expect(ProjectWorkflowScope.where(project_id: copy.id).count).to eq(0)
      end
    end

    # "Who took this decision, and when" is what the project's Workflow tab and
    # the inventory show. A copy is a decision, so it is stamped with the person
    # who pressed Copy rather than left blank.
    it 'records the operator on the scopes it creates' do
      give_own_workflow(source, tracker, role)
      operator = users(:users_002)
      User.current = operator

      copy = copy_of(source)

      expect(ProjectWorkflowScope.where(project_id: copy.id).pluck(:created_by_id, :updated_by_id))
        .to eq([[operator.id, operator.id]])
    ensure
      User.current = nil
    end

    it 'copies nothing when the project has no workflow of its own' do
      transition(project_id: nil)

      copy = copy_of(source)

      expect(ProjectWorkflowScope.where(project_id: copy.id).count).to eq(0)
      expect(WorkflowTransition.where(project_id: copy.id).count).to eq(0)
    end

    # The copy has to answer the resolver the way the source does; equal row
    # counts would not prove that on their own.
    #
    # The project's own rule names a status the generic workflow never mentions,
    # so an inheriting copy answers a strictly smaller list -- which is what
    # this example rejects, and what it did answer before the fix.
    it 'resolves to the same effective status list as the source' do
      give_own_workflow(source, tracker, role)
      transition(project_id: source.id, to: own_only_status)
      transition(project_id: nil)

      copy = copy_of(source)
      query = RedmineProjectWorkflows::Services::StatusListQuery
      RedmineProjectWorkflows::Services::Resolver.reset_cache!

      expect(query.status_ids_for_pairs(pairs: [[source.id, tracker.id]])).to include(own_only_status.id)
      expect(query.status_ids_for_pairs(pairs: [[copy.id, tracker.id]]).sort)
        .to eq(query.status_ids_for_pairs(pairs: [[source.id, tracker.id]]).sort)
    end
  end

  describe 'the copier itself' do
    let(:target) do
      Project.create!(name: 'Workflow copy target', identifier: 'wf-copy-plain',
                      tracker_ids: [tracker.id],
                      enabled_module_names: %w[issue_tracking])
    end

    def copy!
      RedmineProjectWorkflows::Services::ProjectWorkflowCopier.copy(
        source_project_id: source.id, target_project_id: target.id, user: User.anonymous
      )
    end

    it 'carries field permissions as well as transitions' do
      give_own_workflow(source, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      permission(project_id: source.id)

      expect(copy!).to eq([1, 1])
      expect(own_workflow?(target, tracker, role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
      expect(WorkflowPermission.where(project_id: target.id).count).to eq(1)
    end

    # The target has trackers_001 and nothing else. A decision about a tracker
    # the project does not have is a decision about nothing.
    it 'skips a tracker the target does not have' do
      give_own_workflow(source, tracker, role)
      give_own_workflow(source, other_tracker, role)
      transition(project_id: source.id)
      transition(project_id: source.id, tracker_id: other_tracker.id)

      expect(copy!).to eq([1, 1])
      expect(ProjectWorkflowScope.where(project_id: target.id).pluck(:tracker_id)).to eq([tracker.id])
      expect(WorkflowTransition.where(project_id: target.id).pluck(:tracker_id)).to eq([tracker.id])
    end

    # A rule row whose (tracker, role, rule type) has no scope is invisible to
    # the resolver where it is now (INV-3), so carrying it across would move
    # rubbish into the copy and make the two projects differ in the table while
    # agreeing on the screen.
    it 'skips a rule row that no scope makes visible' do
      give_own_workflow(source, tracker, role)
      transition(project_id: source.id)
      transition(project_id: source.id, role_id: other_role.id)

      expect(copy!).to eq([1, 1])
      expect(WorkflowTransition.where(project_id: target.id).pluck(:role_id)).to eq([role.id])
    end

    it 'does nothing at all when the source has no scope' do
      transition(project_id: source.id)

      expect(copy!).to eq([0, 0])
      expect(WorkflowTransition.where(project_id: target.id).count).to eq(0)
    end

    # "Copied over" is not one of INV-3's three actions. A project that has
    # already decided something about its own workflow keeps its decision.
    it 'leaves a target that already runs its own workflow untouched' do
      give_own_workflow(source, tracker, role)
      transition(project_id: source.id)
      give_own_workflow(target, tracker, other_role)

      expect(copy!).to eq([0, 0])
      expect(ProjectWorkflowScope.where(project_id: target.id).pluck(:role_id)).to eq([other_role.id])
      expect(WorkflowTransition.where(project_id: target.id).count).to eq(0)
    end

    it 'refuses to copy a project onto itself' do
      give_own_workflow(source, tracker, role)
      transition(project_id: source.id)

      expect(
        RedmineProjectWorkflows::Services::ProjectWorkflowCopier.copy(
          source_project_id: source.id, target_project_id: source.id
        )
      ).to eq([0, 0])
      expect(WorkflowTransition.where(project_id: source.id).count).to eq(1)
    end
  end
end
