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

  # PostgreSQL writes FROM "workflows" and MySQL and MariaDB write FROM
  # `workflows`, so a pattern that spells one of the two quote characters matches
  # nothing on six of the nine CI cells -- and the assertion it feeds is
  # `not_to be_empty`, which then fails rather than passing vacuously. That is
  # the lucky half of this trap; the same pattern under a `to all(...)` would
  # have gone green over an empty list and proved nothing at all.
  def workflows_table
    /FROM\s+["`]?workflows["`]?/i
  end

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

  # The rules somebody wrote, without core's own fallback arrow. Which
  # population a query reads is a question about stored rows, and the fallback
  # is not one -- it is what Redmine does when there is no row. The fallback has
  # a describe block of its own further down, where it is asserted rather than
  # filtered out.
  def stored_pairs(graph)
    graph.stored_edges.map { |edge| [edge.old_status_id, edge.new_status_id] }
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
      expect(stored_pairs(graph)).to eq([[new_status.id, assigned.id]])
    end

    it "never reads another project's rows" do
      give_own_workflow(other_project, tracker, role)
      transition(new_status, closed, project_id: other_project.id)
      transition(new_status, assigned)

      expect(stored_pairs(graph_for)).to eq([[new_status.id, assigned.id]])
    end

    it 'does not inherit a parent project\'s scope (INV-6)' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)
      transition(new_status, closed)

      # The child has no scope of its own, so it reads the generic rows -- not
      # its parent's, however close the two are in the tree.
      expect(stored_pairs(graph_for(in_project: child))).to eq([[new_status.id, closed.id]])
      expect(graph_for(in_project: child).role_states.map(&:state)).to eq([:inherits])
    end

    it 'names a project_id in every statement it issues against workflows' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      statements = statements_during { graph_for }
      workflow_statements = statements.grep(workflows_table)

      expect(workflow_statements).not_to be_empty
      expect(workflow_statements).to all(match(/project_id/i))
    end

    it 'reads one population per role when two roles resolve differently' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)
      transition(new_status, closed, role_id: second_role.id)

      graph = graph_for(role_ids: [role.id, second_role.id])

      expect(stored_pairs(graph)).to contain_exactly([new_status.id, assigned.id], [new_status.id, closed.id])
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
      expect(graph.stored_edges).to be_empty
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

      expect(stored_pairs(graph_for)).to eq([[new_status.id, assigned.id]])
    end

    it 'collapses several rows for one move into one edge, naming every role' do
      transition(new_status, assigned)
      transition(new_status, assigned, role_id: second_role.id)

      graph = graph_for(role_ids: [role.id, second_role.id])

      expect(graph.stored_edges.size).to eq(1)
      expect(graph.stored_edges.first.roles).to eq([role, second_role])
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

  # Finding F01. Redmine's own redmine:load_default_data seeds no
  # old_status_id = 0 row, so on a freshly installed Redmine the workflow names
  # no status for a new issue -- and core then starts the issue on the tracker's
  # default status rather than refusing to create one (Issue#new_statuses_allowed_to,
  # app/models/issue.rb). Before this the drawing modelled only the rules, so on
  # the shipped configuration every status was reported unreachable.
  describe "core's own fallback for a new issue" do
    let(:default_status) { tracker.default_status }

    it 'adds an arrow from the entry node to the tracker default when no rule leaves it' do
      transition(new_status, assigned)

      graph = graph_for
      fallback = graph.fallback_edge

      expect(pairs(graph)).to include([0, tracker.default_status_id])
      expect(fallback).not_to be_nil
      expect(fallback.old_status_id).to eq(0)
      expect(fallback.new_status_id).to eq(default_status.id)
      expect(fallback).to be_fallback
      expect(fallback.conditions).to eq(['always'])
      expect(fallback.roles).to eq([role])
    end

    it 'adds nothing when a rule already leaves the entry node' do
      transition(0, assigned)
      transition(new_status, assigned)

      expect(graph_for.fallback_edge).to be_nil
      expect(graph_for.edges).to eq(graph_for.stored_edges)
    end

    it 'adds nothing when one of several selected roles has an entry rule' do
      # Core resolves a new issue's status over the reader's roles *together*
      # (Issue#roles_for_workflow), so one role naming a status for a new issue
      # is enough for the fallback not to apply.
      transition(0, assigned, role_id: second_role.id)
      transition(new_status, closed)

      expect(graph_for(role_ids: [role.id, second_role.id]).fallback_edge).to be_nil
    end

    it 'adds nothing when the tracker has no default status to fall back to' do
      # Tracker validates the presence of a default status, so this is reachable
      # only through a status deleted underneath one -- but the drawing must not
      # raise on it.
      transition(new_status, assigned)
      allow(tracker).to receive(:default_status).and_return(nil)

      expect(described_class.new(project: project, tracker: tracker, role_ids: [role.id])
                            .result.fallback_edge).to be_nil
    end

    it 'is not a stored rule, so the workflow is still reported as empty' do
      # INV-3 in its user-visible half: an own *empty* workflow is a
      # configuration, and Redmine having a default must not make it read as a
      # workflow somebody filled in.
      give_own_workflow(project, tracker, role)

      graph = graph_for

      expect(graph.stored_edges).to be_empty
      expect(graph).to be_empty_workflow
      expect(graph.fallback_edge).not_to be_nil
    end

    it 'makes every status reachable again on a workflow with no entry rule' do
      # The shipped shape, in miniature: rules between statuses and none out of
      # the entry node. Without the fallback nothing is reachable from a new
      # issue, so *every* status lands in the band below the dotted line and the
      # one diagnostic this screen exists for fires on all of them (finding F01).
      # new_status is trackers_001's default_status, which is what rescues the
      # rest of the chain with it.
      transition(new_status, assigned)
      transition(assigned, closed)

      layout = RedmineProjectWorkflows::Services::WorkflowGraphLayout.new(graph_for).result

      expect(layout.band_nodes).to be_empty
      expect(graph_for.dead_end_nodes.map(&:status_id)).to eq([closed.id])
    end

    it 'leaves a status the fallback cannot reach in the band' do
      # The fallback rescues what the tracker's default status leads to and
      # nothing else: an island of statuses is still a real defect in a workflow
      # and still has to be reported as one.
      transition(new_status, assigned)
      transition(resolved, closed)

      layout = RedmineProjectWorkflows::Services::WorkflowGraphLayout.new(graph_for).result

      expect(layout.band_nodes.map { |placed| placed.node.status_id })
        .to contain_exactly(resolved.id, closed.id)
    end

    it 'counts the fallback target as mentioned, so it is not filed under "not used"' do
      transition(resolved, closed)

      graph = graph_for

      expect(graph.unmentioned_nodes.map(&:status_id)).not_to include(default_status.id)
      expect(graph.nodes.detect { |node| node.status_id == default_status.id }.mentioned).to be(true)
    end

    it 'reports the fallback target as a dead end when nothing leads out of it' do
      # The one diagnostic that only makes sense once the fallback is modelled:
      # a new issue starts here and can never leave.
      give_own_workflow(project, tracker, role)
      transition(resolved, closed, project_id: project.id)

      expect(graph_for.dead_end_nodes.map(&:status_id)).to include(default_status.id)
    end
  end

  # Finding F03. Redmine's own default workflow is complete -- every status may
  # become every other -- and a layered drawing of a complete graph is one
  # column per status with an arc between every pair.
  describe 'a workflow with no progression to draw' do
    def complete_workflow(statuses)
      statuses.permutation(2) { |from, to| transition(from, to) }
    end

    it 'reports a complete workflow over four statuses as dense' do
      complete_workflow([new_status, assigned, resolved, closed])

      expect(graph_for).to be_dense
    end

    it 'does not report a staged workflow as dense' do
      transition(0, new_status)
      transition(new_status, assigned)
      transition(assigned, resolved)
      transition(resolved, closed)

      expect(graph_for).not_to be_dense
    end

    it 'does not report a complete workflow over three statuses as dense' do
      # Three boxes and six arrows is still a picture somebody can read, and a
      # screen that refused to draw it would be hiding the easy case.
      complete_workflow([new_status, assigned, resolved])

      expect(graph_for).not_to be_dense
    end

    it 'does not count the entry arrow towards the density' do
      # The entry node is not a status any move can return to, so counting it
      # would put a fifth "status" into a four-status workflow and drop a
      # complete graph back under the threshold -- twelve moves out of twenty
      # rather than twelve out of twelve.
      complete_workflow([new_status, assigned, resolved, closed])
      transition(0, new_status)

      expect(graph_for).to be_dense
    end
  end
end
