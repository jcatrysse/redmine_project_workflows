# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::StatusListQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before { ProjectWorkflowScope.delete_all }

  it 'returns global statuses when the project has no scope' do
    WorkflowTransition.delete_all
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
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: [role.id]
    )

    expect(status_ids).to include(global_status.id)
    expect(status_ids).not_to include(project_status.id)
  end

  it 'prefers project statuses over global ones for scoped roles' do
    WorkflowTransition.delete_all
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

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: [role.id]
    )

    expect(status_ids).to include(project_status.id)
    expect(status_ids).not_to include(global_status.id)
  end

  it 'returns empty when trackers are missing' do
    status_ids = described_class.status_ids_for_pairs(
      pairs: [],
      role_ids: [role.id]
    )

    expect(status_ids).to be_empty
  end

  it 'returns empty when role ids are missing' do
    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: []
    )

    expect(status_ids).to be_empty
  end

  it 'returns empty when role ids are missing even with transitions present' do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: []
    )

    expect(status_ids).to be_empty
  end

  it 'applies no role filter at all when role ids are nil' do
    WorkflowTransition.delete_all
    # A role nobody can use for a workflow. Core's own queries here carry no
    # role predicate, so its rows count; the previous implementation filtered
    # on Role#consider_workflow? and dropped them.
    unmanned = Role.create!(name: 'No issue permissions', permissions: [])
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: unmanned.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    expect(unmanned).not_to be_consider_workflow

    status_ids = described_class.status_ids_for_pairs(
      pairs: [[project.id, tracker.id]],
      role_ids: nil
    )

    expect(status_ids).to include(global_status.id)
  end

  describe '.status_ids_for_pairs' do
    let(:second_tracker) { trackers(:trackers_002) }

    before { WorkflowTransition.delete_all }

    it 'reads each project in the list against its own scope' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: project_status.id,
        project_id: project.id, author: false, assignee: false
      )
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: global_status.id,
        project_id: nil, author: false, assignee: false
      )

      # The first project answers for itself, the second inherits. Both
      # populations are reachable; neither hides the other (INV-6).
      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id]]
      )

      expect(status_ids).to include(project_status.id)
      expect(status_ids).to include(global_status.id)
    end

    it 'drops the generic rows only for the tracker and role that every pair overrides' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, role)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: global_status.id,
        project_id: nil, author: false, assignee: false
      )
      WorkflowTransition.create!(
        tracker_id: second_tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: project_status.id,
        project_id: nil, author: false, assignee: false
      )

      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id],
                [project.id, second_tracker.id]]
      )

      expect(status_ids).not_to include(global_status.id)
      expect(status_ids).to include(project_status.id)
    end

    it 'reads the generic workflow for a pair whose project id is nil' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: global_status.id,
        project_id: nil, author: false, assignee: false
      )

      status_ids = described_class.status_ids_for_pairs(pairs: [[nil, tracker.id]])

      expect(status_ids).to contain_exactly(old_status.id, global_status.id)
    end

    it 'returns empty for an empty list of pairs' do
      expect(described_class.status_ids_for_pairs(pairs: [])).to be_empty
    end
  end

  # The three properties that make grouping the overriding pairs safe. The first
  # two were written before the grouping existed and confirmed to pass on the
  # per-pair form as well, because the risk finding F11 names is a fix that
  # breaches an invariant while every existing example stays green. They say, in
  # order: what grouping must not lose (a generic role only some of the pairs
  # answer for), what a merged branch must still read (every project in the
  # group, not the first), and what the group *key* protects (a row under no
  # scope stays unread). Each was confirmed to fail against the wrong
  # implementation it is about, rather than argued for.
  describe 'projects that override different parts of the same tracker' do
    let(:other_role) { roles(:roles_002) }
    let(:other_project_status) { issue_statuses(:issue_statuses_004) }
    let(:other_global_status) { issue_statuses(:issue_statuses_005) }

    before { WorkflowTransition.delete_all }

    def transition(project_id, role_id, new_status)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role_id,
        old_status_id: old_status.id, new_status_id: new_status.id,
        project_id: project_id, author: false, assignee: false
      )
    end

    # INV-6: one project overriding a role says nothing about the next one. The
    # generic rows for a role are out of reach only when *every* pair for that
    # tracker answers for that role itself, which is why `excluded` is an
    # intersection across the whole pair set. Computing it per group -- the
    # obvious mistake to make once the pairs are grouped -- drops both generic
    # rows here (INV-5, F11).
    #
    # F11 said no example covered this. That was too strong: 'reads each project
    # in the list against its own scope' above catches the same mistake, and
    # measuring found it does. This is the sharper case and worth having beside
    # it -- two non-empty *disjoint* role sets, every pair holding a scope, so
    # the intersection is empty for a reason no single-role example can show.
    it 'keeps both generic roles reachable when each project overrides only one' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, other_role)
      transition(nil, role.id, global_status)
      transition(nil, other_role.id, other_global_status)
      transition(project.id, role.id, project_status)
      transition(other_project.id, other_role.id, other_project_status)

      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id]]
      )

      expect(status_ids).to include(global_status.id, other_global_status.id)
      expect(status_ids).to include(project_status.id, other_project_status.id)
    end

    # Two projects overriding the same role for the same tracker are one group,
    # so they share one branch. Both projects' rows still have to come back -- a
    # group carries a project_id *list*, not its first element -- and the generic
    # row for that role stays out, because here every pair does answer for it.
    it 'reads every project that overrides the same role for the same tracker' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, role)
      transition(nil, role.id, global_status)
      transition(project.id, role.id, project_status)
      transition(other_project.id, role.id, other_project_status)

      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id]]
      )

      expect(status_ids).to contain_exactly(old_status.id, project_status.id, other_project_status.id)
    end

    # INV-3: which population a (project, tracker, role) reads comes from the
    # scope table and never from whether rows exist, so a row under no scope
    # applies to nothing. That state needs raw SQL or a dump restored from
    # before migration 003 deleted the orphans -- it is here because it is what
    # the group key protects: grouping the pairs by tracker alone, and unioning
    # the role sets, would read this row for a role this project does not answer
    # for, and the two examples above would both stay green (INV-5, F11).
    it 'ignores a row a project has under no scope, even when a sibling answers for that role' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, other_role)
      transition(nil, role.id, global_status)
      transition(project.id, role.id, project_status)
      transition(other_project.id, other_role.id, other_project_status)
      # other_project answers for other_role only, so this row is unreachable.
      transition(other_project.id, role.id, other_global_status)

      status_ids = described_class.status_ids_for_pairs(
        pairs: [[project.id, tracker.id], [other_project.id, tracker.id]]
      )

      expect(status_ids).not_to include(other_global_status.id)
      expect(status_ids).to include(global_status.id, project_status.id, other_project_status.id)
    end
  end
  # G6, and the half of finding F11 that is not about the answer: the branch
  # count of the OR is bounded by how many distinct override configurations
  # exist, not by how many projects have one -- and copy-to-subprojects gives a
  # whole tree the same configuration. Asserted as statement shape, because the
  # answer was never wrong: every example above was green on the per-pair form.
  #
  # It matters on two screens, not one. The administration matrix with "all
  # projects" selected is the one docs/design.md priced in; the other is
  # Project#rolled_up_statuses, which fills the status filter and the status
  # report on every project issue list.
  describe 'the shape of the statement it issues' do
    let(:third_project) { projects(:projects_003) }
    let(:fourth_project) { projects(:projects_004) }
    let(:other_role) { roles(:roles_002) }

    before { WorkflowTransition.delete_all }

    # Rails factors the predicates common to every branch out of the OR, so the
    # tracker and the base condition appear once whatever the branch count and
    # counting them counts nothing. What stays one per branch is the project_id
    # predicate -- IS NULL for the generic branch, an id or a list for each
    # configuration -- so counting that counts branches, on all three databases.
    def branches_in_statement_for(pairs)
      statement = statements_during { described_class.status_ids_for_pairs(pairs: pairs) }
                  .grep(/FROM\s+\W?workflows\W/i).first

      statement.scan(/project_id/i).size
    end

    it 'shares one branch between every project that overrides the same roles' do
      [project, other_project, third_project, fourth_project].each do |target|
        give_own_workflow(target, tracker, role)
      end
      pairs = [project, other_project, third_project, fourth_project].map { |p| [p.id, tracker.id] }

      two = branches_in_statement_for(pairs.first(2))
      four = branches_in_statement_for(pairs)

      # One generic branch and one for the single configuration, whether two
      # projects hold it or four. Per pair it would have been three and five.
      expect(four).to eq(2)
      expect(four).to eq(two)
    end

    it 'keeps a separate branch for each distinct configuration' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, role)
      give_own_workflow(third_project, tracker, other_role)

      branches = branches_in_statement_for(
        [[project.id, tracker.id], [other_project.id, tracker.id], [third_project.id, tracker.id]]
      )

      # The generic rows, the two projects that answer for +role+, and the one
      # that answers for +other_role+. Grouping by tracker alone would give two
      # branches and read the third project against roles it does not answer
      # for -- which is why the group key carries the role set (INV-5).
      expect(branches).to eq(3)
    end
  end
end
