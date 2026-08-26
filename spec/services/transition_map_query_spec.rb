# frozen_string_literal: true

require_relative '../spec_helper'

# WP8. The map behind the panel on the issue form.
#
# Two properties matter more than the rest, and they are what most of this file
# is about: it must never name a status only another project's rules reach
# (INV-4), and it must not contradict the status list on the form -- every edge
# it shows that the list withholds has to carry the reason why.
describe RedmineProjectWorkflows::Services::TransitionMapQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :enumerations, :projects_trackers

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:second_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user) { users(:users_002) }
  # A member of the same project holding the *other* role, so an arrangement for
  # them has to be stored against second_role -- and one stored against `role` is
  # invisible to them, which is what makes these examples honest about roles.
  let(:stranger) { users(:users_003) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }
  let(:resolved) { issue_statuses(:issue_statuses_003) }
  let(:closed) { issue_statuses(:issue_statuses_005) }

  before do
    member = Member.where(project: project, user: user).first_or_initialize
    member.roles = [role] if member.new_record? || member.roles.empty?
    member.save!
  end

  def transition(from, to, project_id: nil, role_id: nil, author: false, assignee: false)
    WorkflowTransition.create!(
      tracker_id: tracker.id, role_id: role_id || role.id,
      old_status_id: from.respond_to?(:id) ? from.id : from,
      new_status_id: to.respond_to?(:id) ? to.id : to,
      project_id: project_id, author: author, assignee: assignee
    )
  end

  def issue_in(status, author: user, assigned_to: nil, in_project: project)
    Issue.create!(project: in_project, tracker: tracker, status: status, author: author,
                  assigned_to: assigned_to, subject: 'transition map spec')
  end

  def map_for(issue, as: user)
    described_class.new(issue: issue, user: as).result
  end

  describe 'which workflow applies, per role' do
    it 'says the project inherits when it has no scope' do
      map = map_for(issue_in(new_status))

      expect(map.role_states.map(&:role)).to eq([role])
      expect(map.role_states.map(&:state)).to eq([:inherits])
      expect(map.uniform_state).to eq(:inherits)
    end

    it 'says the project has its own workflow when the scope holds a rule' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      expect(map_for(issue_in(new_status)).uniform_state).to eq(:own)
    end

    # The state that most needs saying: an empty status list with no explanation
    # is indistinguishable from a broken plugin (INV-3).
    it 'tells an own empty workflow apart from an own one' do
      give_own_workflow(project, tracker, role)

      map = map_for(issue_in(new_status))

      expect(map.uniform_state).to eq(:own_empty)
      expect(map.outgoing).to be_empty
    end

    # A rule stored against the project but with no scope applies to nothing
    # (INV-3), so it must not turn "own empty" into "own".
    it 'does not count a project rule that no scope makes effective' do
      transition(new_status, assigned, project_id: project.id)

      expect(map_for(issue_in(new_status)).uniform_state).to eq(:inherits)
    end

    it 'does not count another project rules as this project own' do
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: other_project.id)

      expect(map_for(issue_in(new_status)).uniform_state).to eq(:own_empty)
    end

    # Resolution is per role (INV-5), so a reader holding two roles can be
    # overridden in one and inheriting in the other -- and that is exactly the
    # case no other screen makes visible from the issue.
    it 'answers per role when the roles disagree' do
      Member.where(project: project, user: user).first.update!(role_ids: [role.id, second_role.id])
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      map = map_for(issue_in(new_status))

      expect(map.uniform_state).to be_nil
      expect(map.role_states.map { |state| [state.role, state.state] })
        .to eq([[role, :own], [second_role, :inherits]])
    end

    # Redmine's Anonymous role is the one built-in role whose consider_workflow?
    # is false, so an anonymous reader of a public project is the real case where
    # the workflow answers nothing at all -- and the panel says so rather than
    # rendering an empty table.
    it 'has nothing to describe for a reader with no workflow role' do
      transition(new_status, assigned)

      map = map_for(issue_in(new_status), as: User.anonymous)

      expect(map).not_to be_any_roles
      expect(map.outgoing).to be_empty
      expect(map.incoming).to be_empty
    end
  end

  describe 'the edges' do
    it 'lists what the generic workflow allows from here' do
      transition(new_status, assigned)
      transition(new_status, resolved)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:new_status)).to eq([assigned, resolved])
      expect(map.outgoing.map(&:conditions)).to eq([['always'], ['always']])
    end

    it 'lists what leads here' do
      transition(new_status, assigned)
      transition(resolved, assigned)

      map = map_for(issue_in(assigned))

      expect(map.incoming.map(&:old_status)).to eq([new_status, resolved])
      expect(map.outgoing).to be_empty
    end

    # INV-4 on the map itself: the one property the whole scope model exists for.
    it 'never names a status only another project rules reach' do
      transition(new_status, assigned)
      transition(new_status, closed, project_id: other_project.id, role_id: role.id)
      give_own_workflow(other_project, tracker, role)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:new_status)).to eq([assigned])
    end

    it 'reads the project own rows once the project has taken over' do
      transition(new_status, assigned)
      give_own_workflow(project, tracker, role)
      transition(new_status, resolved, project_id: project.id)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:new_status)).to eq([resolved])
    end

    # An unsaved issue starts at core's "new issue" pseudo-status, stored as
    # old_status_id 0, which is where the dropdown on the new-issue form reads
    # from too.
    it 'starts a new issue at the new issue node' do
      transition(0, new_status)
      transition(new_status, assigned)

      map = map_for(Issue.new(project: project, tracker: tracker, author: user))

      expect(map.status).to be_nil
      expect(map.status_id).to eq(0)
      expect(map.outgoing.map(&:new_status)).to eq([new_status])
    end

    it 'leaves a transition from a status to itself out' do
      transition(new_status, new_status)
      transition(new_status, assigned)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:new_status)).to eq([assigned])
      expect(map.incoming).to be_empty
    end

    it 'names the roles that permit a move' do
      Member.where(project: project, user: user).first.update!(role_ids: [role.id, second_role.id])
      transition(new_status, assigned)
      transition(new_status, assigned, role_id: second_role.id)
      transition(new_status, resolved, role_id: second_role.id)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map { |edge| [edge.new_status, edge.roles] })
        .to eq([[assigned, [role, second_role]], [resolved, [second_role]]])
    end

    # A row with both flags set is in two of core's three grids at once, which
    # is how core's own matrix renders it.
    it 'collapses one row carrying both flags into both conditions' do
      transition(new_status, assigned, author: true, assignee: true)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:conditions)).to eq([%w[author assignee]])
    end

    # An unconditional move subsumes the author and assignee variants of itself,
    # so listing them beside it would only pad the row.
    it 'drops the conditional variants of a move anyone may make' do
      transition(new_status, assigned)
      transition(new_status, assigned, author: true)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:conditions)).to eq([['always']])
    end

    it 'orders the edges by the position of the status, not by the row order' do
      transition(new_status, resolved)
      transition(new_status, assigned)

      map = map_for(issue_in(new_status))

      expect(map.outgoing.map(&:new_status_id)).to eq([assigned.id, resolved.id])
    end
  end

  # The honesty clause. The map says what the workflow allows; the status list on
  # the form stays the authority for what may be done now, so every edge it
  # withholds carries the reason.
  describe 'whether the status list offers a move now' do
    it 'marks an unconditional move as offered' do
      transition(new_status, assigned)

      edge = map_for(issue_in(new_status)).outgoing.first

      expect(edge.available).to be(true)
      expect(edge.reason).to be_nil
    end

    it 'withholds an author-only move from somebody who is not the author' do
      transition(new_status, assigned, role_id: second_role.id, author: true)

      edge = map_for(issue_in(new_status, author: user), as: stranger).outgoing.first

      expect(edge.available).to be(false)
      expect(edge.reason).to eq(I18n.t(:text_project_workflow_map_requires_author))
    end

    it 'offers an author-only move to the author' do
      transition(new_status, assigned, author: true)

      edge = map_for(issue_in(new_status, author: user)).outgoing.first

      expect(edge.available).to be(true)
    end

    it 'names the assignee when that is the only condition' do
      transition(new_status, assigned, role_id: second_role.id, assignee: true)

      edge = map_for(issue_in(new_status, author: user), as: stranger).outgoing.first

      expect(edge.reason).to eq(I18n.t(:text_project_workflow_map_requires_assignee))
    end

    it 'names both when either identity would do' do
      transition(new_status, assigned, role_id: second_role.id, author: true, assignee: true)

      edge = map_for(issue_in(new_status, author: user), as: stranger).outgoing.first

      expect(edge.reason).to eq(I18n.t(:text_project_workflow_map_requires_author_or_assignee))
    end

    # Core's own sentence, not one of the plugin's: it is the same sentence the
    # warning icon beside the status list on the same form carries.
    it 'carries core own reason for an issue that cannot be closed' do
      transition(new_status, closed)
      parent = issue_in(new_status)
      Issue.create!(project: project, tracker: tracker, status: new_status, author: user,
                    subject: 'open subtask', parent_issue_id: parent.id)

      edge = map_for(parent.reload).outgoing.detect { |candidate| candidate.new_status_id == closed.id }

      expect(edge).not_to be_nil
      expect(edge.available).to be(false)
      expect(edge.reason).to eq(I18n.t(:notice_issue_not_closable_by_open_tasks))
    end

    it 'carries core own reason for a subtask of a closed parent' do
      transition(closed, assigned)
      parent = issue_in(closed)
      child = Issue.create!(project: project, tracker: tracker, status: closed, author: user,
                            subject: 'child of a closed parent', parent_issue_id: parent.id)

      edge = map_for(child.reload).outgoing.detect { |candidate| candidate.new_status_id == assigned.id }

      expect(edge).not_to be_nil
      expect(edge.available).to be(false)
      expect(edge.reason).to eq(I18n.t(:notice_issue_not_reopenable_by_closed_parent_issue))
    end

    # The property the whole clause exists for, asserted against the dropdown
    # itself rather than against a list this spec wrote down: everything the form
    # offers is on the map and marked offered, and everything else carries a
    # reason.
    it 'agrees with the status list the form is built from' do
      transition(new_status, assigned)
      transition(new_status, resolved, author: true)
      transition(new_status, closed, assignee: true)
      issue = issue_in(new_status, author: user)

      map = map_for(issue)
      offered = issue.new_statuses_allowed_to(user).map(&:id) - [new_status.id]

      expect(map.outgoing.select(&:available).map(&:new_status_id).sort).to eq(offered.sort)
      expect(map.outgoing.reject(&:available)).to all(satisfy { |edge| edge.reason.present? })
    end

    # Core's own test too: an issue assigned to a *group* is assigned to its
    # members for this purpose, so an assignee-only move is on offer to each of
    # them. Getting this wrong would withhold a move the form is offering.
    it 'treats a member of the assigned group as the assignee' do
      # Redmine only lets a group hold an issue when this is on, and the setting
      # is cached on the class, so it has to be cleared again afterwards.
      Setting.issue_group_assignment = '1'
      group = Group.create!(lastname: 'Transition map spec group')
      group.users << users(:users_002)
      Member.create!(project: project, principal: group, roles: [role])
      issue = issue_in(new_status, author: users(:users_003), assigned_to: group)
      transition(new_status, assigned, assignee: true)

      edge = map_for(issue).outgoing.first

      expect(edge.available).to be(true)
      expect(edge.reason).to be_nil
    ensure
      Setting.clear_cache
    end

    # Author and assignee at once: either condition on its own is enough, so an
    # author-only move and an assignee-only move are both on offer and neither
    # carries a reason.
    it 'offers both variants to somebody who is author and assignee' do
      issue = issue_in(new_status, author: user, assigned_to: user)
      transition(new_status, assigned, author: true)
      transition(new_status, resolved, assignee: true)

      expect(map_for(issue).outgoing.map { |edge| [edge.new_status, edge.available] })
        .to eq([[assigned, true], [resolved, true]])
    end

    # An incoming edge ends at the status the issue is already in, so it is
    # history rather than an action; asking would answer "yes" for every one of
    # them, because the list always offers the current status back.
    it 'claims nothing about an incoming edge' do
      transition(new_status, assigned)

      edge = map_for(issue_in(assigned)).incoming.first

      expect(edge.available).to be_nil
      expect(edge.reason).to be_nil
    end
  end

  # A row naming a status that no longer exists is something the table allows and
  # core's own delete does not leave behind. It must not become a blank cell or
  # raise: the edge is still in the workflow, so it is named by its id.
  it 'keeps an edge whose status has been deleted' do
    # The row has to be created against a real status -- WorkflowTransition
    # validates the association -- and the status then removed underneath it,
    # which is the state a hand-edited database can be in.
    orphan = IssueStatus.create!(name: 'Transition map spec orphan')
    transition(new_status, orphan)
    orphan_id = orphan.id
    IssueStatus.where(id: orphan_id).delete_all

    edge = map_for(issue_in(new_status)).outgoing.first

    expect(edge.new_status).to be_nil
    expect(edge.new_status_id).to eq(orphan_id)
    expect(edge.available).to be(false)
  end

  # The tracker the form currently shows, applied to the issue before the map is
  # drawn. This is the property the whole "must not contradict the status list"
  # clause rests on: after Issue#tracker= the issue's status is the same one
  # new_statuses_allowed_to picks as its initial status, so map and list read
  # from one object. Asserted against the list itself, not against a status this
  # spec chose.
  it 'agrees with the status list after a tracker change the form has made' do
    other_tracker = trackers(:trackers_002)
    project.trackers << other_tracker unless project.trackers.include?(other_tracker)
    transition(new_status, assigned)
    WorkflowTransition.create!(tracker_id: other_tracker.id, role_id: role.id, project_id: nil,
                               old_status_id: new_status.id, new_status_id: resolved.id)
    issue = issue_in(new_status)

    issue.tracker = other_tracker
    map = described_class.new(issue: issue, user: user, tracker: other_tracker).result
    offered = issue.new_statuses_allowed_to(user).map(&:id) - [map.status_id]

    expect(map.outgoing.select(&:available).map(&:new_status_id).sort).to eq(offered.sort)
    expect(map.outgoing.map(&:new_status)).to eq([resolved])
  end

  # G6. The cost is behind a link, but it still has to be a fixed number of
  # queries rather than one per role or per status.
  it 'costs a fixed number of queries whatever the size of the workflow' do
    give_own_workflow(project, tracker, role)
    [assigned, resolved, closed].each do |status|
      transition(new_status, status, project_id: project.id)
      transition(status, new_status, project_id: project.id)
    end
    issue = issue_in(new_status)
    # The dropdown is part of the answer and costs what it costs; force the
    # fixtures and the associations the map does not pay for.
    issue.new_statuses_allowed_to(user)
    RedmineProjectWorkflows::Current.reset

    counted = 0
    counter = ->(_name, _start, _finish, _id, payload) { counted += 1 unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { map_for(issue) }

    expect(counted).to be <= 8
  end
end
