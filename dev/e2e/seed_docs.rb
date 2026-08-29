# frozen_string_literal: true

# The state the screenshots in docs/images/ are taken from. Run seed.rb first,
# then this, then docshots.mjs.
#
# It renames the scenario projects to something that reads like a real
# installation rather than a fixture, gives one of them a workflow worth looking
# at -- a plain path with two shortcuts, not Redmine's everything-to-everything
# default, which draws as spaghetti -- and creates one issue so the issue-form
# panel has something to describe.
#
# Running seed.rb again puts the scenario names back, which is why the browser
# scenarios and the screenshots do not share a seed.
User.current = User.find(1)
ProjectWorkflowScope.delete_all
WorkflowRule.where.not(project_id: nil).delete_all
Issue.delete_all

# Names that read like a real installation rather than test fixtures.
{ 'alpha' => 'Website redesign', 'beta' => 'Internal tooling', 'gamma' => 'Customer support' }
  .each { |ident, name| Project.find_by(identifier: ident)&.update!(name: name) }

site = Project.find_by(identifier: 'alpha')
bug = Tracker.find_by(name: 'Bug')
mgr = Role.find_by(name: 'Manager')

RedmineProjectWorkflows::Services::ScopeWriter.enable(
  project_ids: [site.id], tracker_ids: [bug.id], role_ids: [mgr.id],
  rule_type: 'transitions', copy_generic: true, user: User.find_by(login: 'mgr')
)

# A workflow that is worth looking at: a plain path plus two shortcuts, rather
# than the everything-to-everything default.
s = IssueStatus.order(:position).index_by(&:name)
WorkflowTransition.where(project_id: site.id, tracker_id: bug.id, role_id: mgr.id).delete_all
[[0, 'New'],
 ['New', 'In Progress'], ['New', 'Rejected'],
 ['In Progress', 'Resolved'], ['In Progress', 'Feedback'],
 ['Feedback', 'In Progress'],
 ['Resolved', 'Closed'], ['Resolved', 'Feedback']].each do |from, to|
  WorkflowTransition.create!(tracker_id: bug.id, role_id: mgr.id, project_id: site.id,
                             old_status_id: from.zero? ? 0 : s[from].id,
                             new_status_id: s[to].id)
end
Issue.create!(project_id: site.id, tracker_id: bug.id, author_id: User.find_by(login: 'mgr').id,
              subject: 'Contact form does not send on mobile', status_id: s['In Progress'].id,
              priority: IssuePriority.first)
puts "site rules: #{WorkflowTransition.where(project_id: site.id).count}, issue: #{Issue.last.id}"
