# frozen_string_literal: true

# B2's points 1-5 against the plugin as installed; run by check-legacy-defects.sh,
# which installs 0.0.3 first. Each line says whether the defect showed.
puts "plugin version: #{Redmine::Plugin.find(:redmine_project_workflows).version}"
writer = RedmineProjectWorkflows::Services::TransitionWriter
s1, s2, s3 = %w[rp-a rp-b rp-c].map { |name| IssueStatus.create!(name: name) }
t = Tracker.create!(name: 'rp-t', default_status_id: s1.id)
r1, r2 = %w[rp-r1 rp-r2].map { |name| Role.create!(name: name, permissions: %i[view_issues add_issues edit_issues]) }
p = Project.create!(name: 'rp-p', identifier: 'rp-p', tracker_ids: [t.id])
u = User.create!(login: 'rp-u', firstname: 'R', lastname: 'P', mail: 'rp-u@example.com')
Member.create!(project: p, principal: u, roles: [r1])
prio = IssuePriority.first || IssuePriority.create!(name: 'rp-prio')
issue = Issue.create!(project: p, tracker: t, status: s1, subject: 'rp', author: u, priority: prio)
report = ->(label, shown) { puts "#{shown ? 'DEFECT REPRODUCED' : 'not reproduced'}: #{label}" }
generic = lambda do |role, **flags|
  WorkflowTransition.create!(project_id: nil, tracker_id: t.id, role_id: role.id,
                             old_status_id: s1.id, new_status_id: s2.id, **flags)
end
cell = ->(to, value) { { s1.id.to_s => { to.id.to_s => { 'always' => value } } } }

# 1: emptying a project workflow
generic.call(r1)
writer.replace_transitions(p, [t], [r1], cell.call(s3, '1'))
before = issue.reload.new_statuses_allowed_to(u).map(&:name)
writer.replace_transitions(p, [t], [r1], cell.call(s3, '0'))
after = issue.reload.new_statuses_allowed_to(u).map(&:name)
puts "  own workflow #{before.inspect}, after emptying it #{after.inspect}"
report.call('1 an emptied project workflow falls back to the generic one', after.include?('rp-b'))
WorkflowTransition.where(tracker_id: t.id).delete_all

# 2: a generic save for R1+R2, R1 with only an author transition, R2 with none --
# the payload core's form submits for that cell when nothing is changed
generic.call(r1, author: true)
WorkflowTransition.replace_transitions([t], [r1, r2], cell.call(s2, '0'))
left = WorkflowTransition.where(tracker_id: t.id, role_id: r1.id, author: true).count
report.call("2 an unchanged multi-role save deletes R1's author-only rule (left: #{left})", left.zero?)
WorkflowTransition.where(tracker_id: t.id).delete_all

# 3: Integer 1
generic.call(r1)
WorkflowTransition.replace_transitions([t], [r1], cell.call(s2, 1))
left = WorkflowTransition.where(tracker_id: t.id, role_id: r1.id).count
report.call("3 Integer 1 is read as off and deletes the transition (left: #{left})", left.zero?)
WorkflowTransition.where(tracker_id: t.id).delete_all

# 4: a project without members
generic.call(r1)
bare = Project.create!(name: 'rp-bare', identifier: 'rp-bare', tracker_ids: [t.id])
statuses = bare.rolled_up_statuses.map(&:name)
report.call("4 a project without members gets no statuses (#{statuses.inspect})", statuses.empty?)

# 5: POST /workflows/duplicate with target_project_ids[]=999999, as the
# administrator a stock database creates
User.find_by!(login: 'admin').tap { |admin| admin.must_change_passwd = false }.save!
session = ActionDispatch::Integration::Session.new(Rails.application)
session.host! 'localhost'
session.post '/login', params: { username: 'admin', password: 'admin' }
begin
  session.post '/workflows/duplicate',
               params: { source_tracker_id: t.id, source_role_id: r1.id, target_tracker_ids: [t.id],
                         target_role_ids: [r2.id], target_project_ids: ['999999'] }
  status = session.response.status
  report.call("5 a copy to a missing project fails (status #{status})", status == 500)
rescue AbstractController::DoubleRenderError => e
  report.call("5 a copy to a missing project raises #{e.class}", true)
end
