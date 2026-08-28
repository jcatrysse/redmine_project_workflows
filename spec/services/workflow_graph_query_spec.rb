# frozen_string_literal: true

require_relative '../spec_helper'

# WP9. The whole workflow of one (project, tracker, roles) as a graph.
#
# The same two properties that carry WP8's map carry this, and one more:
#
# * It must never name an edge only another project's rules reach, and every
#   relation it builds names a project_id (INV-1, INV-4).
# * The three states of INV-3 have to be reported per role rather than inferred
#   from whether rules exist -- an own *empty* workflow is a configuration, not
#   an absence.
# * Nothing is inherited from a parent project (INV-6).
describe RedmineProjectWorkflows::Services::WorkflowGraphQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :enumerations, :projects_trackers

  let(:project) { projects(:projects_001) }
  # projects_003 is a child of projects_001 in Redmine's own fixtures, which is
  # what makes the "no inheritance" example about a real parent and child.
  let(:child) { projects(:projects_003) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:second_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }
  let(:resolved) { issue_statuses(:issue_statuses_003) }
  let(:closed) { issue_statuses(:issue_statuses_005) }

  before { RedmineProjectWorkflows::Services::Resolver.reset_cache! }

  def transition(from, to, project_id: nil, role_id: nil, author: false, assignee: false)
    WorkflowTransition.create!(
      tracker_id: tracker.id, role_id: role_id || role.id,
      old_status_id: from.respond_to?(:id) ? from.id : from,
      new_status_id: to.respond_to?(:id) ? to.id : to,
      project_id: project_id, author: author, assignee: assignee
    )
  end

  def graph_for(role_ids: [role.id], in_project: project)
    described_class.new(project: in_project, tracker: tracker, role_ids: role_ids).result
  end

  def pairs(graph)
    graph.edges.map { |edge| [edge.old_status_id, edge.new_status_id] }
  end

  describe 'which population is read' do
    it 'draws the generic workflow for a project that inherits' do
      transition(0, new_status)
      transition(new_status, assigned)

      graph = graph_for

      expect(pairs(graph)).to eq([[0, new_status.id], [new_status.id, assigned.id]])
      expect(graph.role_states.map(&:state)).to eq([:inherits])
    end

    it "draws the project's own workflow and never the generic one once it has a scope" do
      transition(new_status, closed)
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      graph = graph_for

      # INV-5: a scope replaces. The generic new -> closed rule is not merged in.
      expect(pairs(graph)).to eq([[new_status.id, assigned.id]])
    end

    it "never reads another project's rows" do
      give_own_workflow(other_project, tracker, role)
      transition(new_status, closed, project_id: other_project.id)
      transition(new_status, assigned)

      expect(pairs(graph_for)).to eq([[new_status.id, assigned.id]])
    end

    it 'does not inherit a parent project\'s scope (INV-6)' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)
      transition(new_status, closed)

      # The child has no scope of its own, so it reads the generic rows -- not
      # its parent's, however close the two are in the tree.
      expect(pairs(graph_for(in_project: child))).to eq([[new_status.id, closed.id]])
      expect(graph_for(in_project: child).role_states.map(&:state)).to eq([:inherits])
    end

    it 'names a project_id in every statement it issues against workflows' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      statements = statements_during { graph_for }
      workflow_statements = statements.grep(/FROM\s+"?workflows"?/i)

      expect(workflow_statements).not_to be_empty
      expect(workflow_statements).to all(match(/project_id/i))
    end

    it 'reads one population per role when two roles resolve differently' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)
      transition(new_status, closed, role_id: second_role.id)

      graph = graph_for(role_ids: [role.id, second_role.id])

      expect(pairs(graph)).to contain_exactly([new_status.id, assigned.id], [new_status.id, closed.id])
      expect(graph.role_states.map { |state| [state.role, state.state] })
        .to eq([[role, :own], [second_role, :inherits]])
    end
  end

  describe 'the three states of INV-3' do
    it 'reports an own empty workflow rather than inheritance' do
      # The defect the whole scope model exists to fix: no rows must not mean
      # "inherit". The scope is what says the project answers for itself.
      give_own_workflow(project, tracker, role)

      graph = graph_for

      expect(graph.role_states.map(&:state)).to eq([:own_empty])
      expect(graph.edges).to be_empty
      expect(graph).to be_empty_workflow
    end

    it 'reports an own workflow with rules as :own' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      expect(graph_for.role_states.map(&:state)).to eq([:own])
    end

    it 'reports no uniform state when two roles disagree' do
      give_own_workflow(project, tracker, role)

      graph = graph_for(role_ids: [role.id, second_role.id])

      expect(graph.uniform_state).to be_nil
      expect(graph.role_states.map(&:state)).to eq(%i[own_empty inherits])
    end

    it 'answers nothing at all when no selected role takes part in a workflow' do
      # Anonymous is the fixture whose consider_workflow? is false.
      graph = graph_for(role_ids: [roles(:roles_005).id])

      expect(graph.role_states).to be_empty
      expect(graph.nodes).to be_empty
      expect(graph.edges).to be_empty
    end
  end

  describe 'the nodes' do
    it 'always carries the entry node, first' do
      transition(0, new_status)

      graph = graph_for

      expect(graph.nodes.first.status_id).to eq(0)
      expect(graph.nodes.first).to be_entry
      expect(graph.entry_status_id).to eq(0)
    end

    it 'is in core\'s own status order rather than the order the rows came back in' do
      transition(resolved, assigned)
      transition(0, new_status)

      ids = graph_for.nodes.map(&:status_id)
      statuses = IssueStatus.where(id: ids - [0]).sorted.pluck(:id)

      expect(ids).to eq([0] + statuses)
    end

    it 'marks a status the selected roles\' rules never mention' do
      # resolved is in the tracker's workflow because *another* role names it;
      # the selected role's rules say nothing about it. That is a third state,
      # and neither "unreachable" nor "dead end" describes it.
      transition(0, new_status)
      transition(resolved, closed, role_id: second_role.id)

      graph = graph_for(role_ids: [role.id])

      expect(graph.unmentioned_nodes.map(&:status_id)).to include(resolved.id, closed.id)
      expect(graph.nodes.detect { |node| node.status_id == new_status.id }.mentioned).to be(true)
    end
  end

  describe 'the edges' do
    it 'excludes a transition from a status to itself' do
      transition(new_status, new_status)
      transition(new_status, assigned)

      expect(pairs(graph_for)).to eq([[new_status.id, assigned.id]])
    end

    it 'collapses several rows for one move into one edge, naming every role' do
      transition(new_status, assigned)
      transition(new_status, assigned, role_id: second_role.id)

      graph = graph_for(role_ids: [role.id, second_role.id])

      expect(graph.edges.size).to eq(1)
      expect(graph.edges.first.roles).to eq([role, second_role])
    end

    it 'collapses the author and assignee grids, and lets the unconditional one win' do
      transition(new_status, assigned, author: true)
      transition(new_status, assigned, assignee: true)
      transition(new_status, closed, author: true)

      edges = graph_for.edges.index_by { |edge| [edge.old_status_id, edge.new_status_id] }

      expect(edges[[new_status.id, assigned.id]].conditions).to eq(%w[author assignee])
      expect(edges[[new_status.id, closed.id]].conditions).to eq(%w[author])
    end

    it 'lets one unconditional row subsume the author variant of the same move' do
      transition(new_status, assigned)
      transition(new_status, assigned, author: true)

      expect(graph_for.edges.first.conditions).to eq(['always'])
    end
  end

  describe 'the diagnostics' do
    it 'names a status with no way out' do
      transition(0, new_status)
      transition(new_status, closed)

      expect(graph_for.dead_end_nodes.map(&:status_id)).to eq([closed.id])
    end

    it 'does not call the entry node a dead end' do
      transition(new_status, assigned)

      # Nothing leads out of the entry node here, but an issue never sits in it.
      expect(graph_for.dead_end_nodes.map(&:status_id)).not_to include(0)
    end

    it 'does not report a status as a dead end when it is simply not mentioned' do
      # Otherwise every status the tracker uses under another role would be
      # listed twice, under two headings that mean different things.
      transition(0, new_status)
      transition(resolved, closed, role_id: second_role.id)

      graph = graph_for(role_ids: [role.id])

      expect(graph.dead_end_nodes.map(&:status_id)).to eq([new_status.id])
      expect(graph.unmentioned_nodes.map(&:status_id)).to include(resolved.id)
    end
  end
end
