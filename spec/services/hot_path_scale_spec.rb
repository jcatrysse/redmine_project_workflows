# frozen_string_literal: true

require_relative '../spec_helper'

# WP15 item 6 -- what grows with the installation, and what does not.
#
# G6 says the resolver's hot path stays a point lookup and that nothing here is
# an N+1. Both halves had gates for the *page* size (the inventory's, and the
# settings tab's); neither had one for the two dimensions an installation
# actually grows in: how many **roles** one person holds, and how many
# **issues** one request touches.
#
# `Issue#safe_attributes=` calls `new_statuses_allowed_to` on every issue save,
# and the bulk-edit form, the bulk-save loop and the context menu each fan it
# out once per selected issue. So a query per role, or a scope lookup per issue,
# is not a slow page -- it is a save that gets slower the longer the
# installation is used.
#
# **Asserted as a shape, not as a number.** Each example measures the same
# operation twice at two sizes and asserts the counts are equal. A budget of
# "at most N statements" would have to be revised by whoever adds a legitimate
# query, and revising it is how such a gate stops meaning anything; equality
# across two sizes cannot be satisfied by a per-item query at any budget.
describe 'the workflow hot path as an installation grows' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :enumerations

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:user) { users(:users_002) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  # Statements against the two tables the plugin owns the queries on.
  #
  # Narrowed to those rather than counting everything, and that is not a way of
  # making the number small: core's own `new_statuses_allowed_to` reads
  # `issue_relations` and loads that table's schema on first use, so a count of
  # *every* statement is one higher the first time an example asks and equal
  # thereafter -- a difference that has nothing to do with how many roles
  # anybody holds. What has to not grow is the plugin's own work.
  def workflow_statements
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      sql = payload[:sql].to_s
      seen << sql if sql.match?(/\b(project_workflow_scopes|workflows)\b/) && payload[:name] != 'SCHEMA'
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # `count` further roles for this user in this project, each with a workflow of
  # the project's own, so every one of them is a scope the resolver has to
  # answer for. Built rather than fixtured: the fixtures hold five roles and the
  # point is what happens at twenty.
  def give_user_more_roles(count)
    member = Member.find_by(user_id: user.id, project_id: project.id)
    Array.new(count) do |index|
      # `:edit_issues` is not decoration: core's own `roles_for_workflow` keeps
      # only roles that answer `consider_workflow?`, which is
      # `add_issues || edit_issues`. Roles created with `:view_issues` alone are
      # filtered out before the plugin sees them, and the first version of this
      # file measured one role at both sizes for exactly that reason.
      extra = Role.create!(name: "scale spec role #{Role.count}-#{index}", permissions: [:edit_issues])
      MemberRole.create!(member: member, role: extra)
      give_own_workflow(project, tracker, extra)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: extra.id, project_id: project.id,
                                 old_status_id: s1.id, new_status_id: s2.id)
      extra
    end
  end

  # How many roles core's own filter actually hands the plugin. Asserted before
  # each measurement, because "the count did not grow" is only interesting once
  # the thing that was supposed to grow did.
  def roles_seen(issue)
    issue.send(:roles_for_workflow, User.find(user.id)).size
  end

  def an_issue
    Issue.create!(project: project, tracker: tracker, status: s1, priority: enumerations(:enumerations_004),
                  author: user, subject: 'hot path scale spec')
  end

  # The resolver's cache is per request, and an example is not a request.
  #
  # A **freshly loaded** user, not `user.reload`: core memoises a member's roles
  # per project on the User instance (`@membership_by_project_id`), and reload
  # does not clear it -- so an example that grants roles and then asks the same
  # object sees the roles it had before. The first version of this file did
  # exactly that and measured one role at both sizes, which is a comparison of
  # nothing against nothing.
  def ask_fresh(issue)
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
    issue.instance_variable_set(:@new_statuses_allowed_to, nil)
    issue.new_statuses_allowed_to(User.find(user.id))
  end

  describe 'a user who holds many roles in one project' do
    before do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: s1.id, new_status_id: s2.id)
    end

    # The property the resolver is built for: its lookup is deliberately not
    # narrowed by role, so one row read answers for every role the reader holds.
    # A per-role lookup would put this at 1 + N.
    it 'costs the same number of statements at four roles as at twenty' do
      issue = an_issue

      give_user_more_roles(3)
      expect(roles_seen(issue)).to eq(4)
      few = workflow_statements { ask_fresh(issue) }

      give_user_more_roles(16)
      expect(roles_seen(issue)).to eq(20)
      many = workflow_statements { ask_fresh(issue) }

      expect(many.size).to eq(few.size)
      # Two: the scope lookup, and the transitions query. Named so that an
      # equality which became "0 == 0" -- a filter that stopped matching, or a
      # path that stopped running -- fails rather than passing quietly.
      expect(few.size).to eq(2)
    end

    it 'gives the same answer at both sizes' do
      issue = an_issue
      give_user_more_roles(3)
      few = ask_fresh(issue).map(&:id)

      give_user_more_roles(16)

      expect(ask_fresh(issue).map(&:id)).to eq(few)
    end
  end

  describe 'one request touching many issues of the same project and tracker' do
    before do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: s1.id, new_status_id: s2.id)
    end

    # The scope lookup is cached for the length of the request precisely because
    # an issue list renders many issues of one tracker in one project. What must
    # *not* be cached away is the transitions query itself, which is per issue --
    # so the growth here is one statement per further issue and not two.
    it 'reads the scope table once however many issues it asks about' do
      issues = Array.new(6) { an_issue }
      RedmineProjectWorkflows::Services::Resolver.reset_cache!

      scope_reads = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        scope_reads += 1 if payload[:sql].to_s.match?(/FROM\s+\W?project_workflow_scopes\b/i)
      end
      begin
        issues.each { |issue| issue.new_statuses_allowed_to(user) }
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(scope_reads).to eq(1)
    end

    # ...and the cache is not a correctness hole: a write during the same
    # request clears it, so the next issue sees the new decision.
    it 'stops using the cached decision once a write has cleared it' do
      issue = an_issue
      # The current status is in every answer core gives, so what identifies
      # which population answered is the status the *rules* lead to.
      expect(issue.new_statuses_allowed_to(user).map(&:id)).to include(s2.id)

      RedmineProjectWorkflows::Services::ScopeWriter.return_to_inheritance(
        project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: ProjectWorkflowScope::TRANSITIONS
      )
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: s1.id, new_status_id: issue_statuses(:issue_statuses_003).id)

      moved_to = an_issue.new_statuses_allowed_to(user).map(&:id)
      expect(moved_to).to include(issue_statuses(:issue_statuses_003).id)
      expect(moved_to).not_to include(s2.id)
    end
  end
end
