# frozen_string_literal: true

# The installation the browser scenarios expect: three projects that between them
# cover the three states of INV-3, three roles, three trackers, six statuses, a
# generic workflow worth inheriting, and four users of different privilege.
#
# Idempotent -- run it as often as you like. It writes only through the models,
# and the generic workflow it builds is the one every project starts from.
User.current = User.find(1)

admin = User.find(1)
admin.password = admin.password_confirmation = 'adminadmin1!'
admin.must_change_passwd = false
admin.save!

def user!(login, first, last, mail)
  u = User.find_by(login: login) || User.new(login: login)
  u.firstname = first
  u.lastname = last
  u.mail = mail
  u.password = u.password_confirmation = 'testpass1!'
  u.must_change_passwd = false
  u.admin = false
  u.status = User::STATUS_ACTIVE
  u.save!
  u
end

manager   = user!('mgr',  'Maria', 'Manager',   'mgr@example.com')
developer = user!('dev',  'Dirk',  'Developer', 'dev@example.com')
onlooker  = user!('look', 'Lieve', 'Looker',    'look@example.com')

trackers = Tracker.order(:id).to_a
roles = Role.givable.order(:id).to_a
statuses = IssueStatus.order(:position).to_a

def project!(identifier, name)
  p = Project.find_by(identifier: identifier) || Project.new(identifier: identifier)
  p.name = name
  p.save!
  p.enabled_module_names = %w[issue_tracking]
  p.trackers = Tracker.order(:id).to_a
  p.save!
  p
end

alpha = project!('alpha', 'Alpha — takes its own workflow')
beta  = project!('beta',  'Beta — inherits everything')
gamma = project!('gamma', 'Gamma — an own empty workflow')

mgr_role = roles.first
dev_role = roles.second

[[alpha, manager, mgr_role], [beta, manager, mgr_role], [gamma, manager, mgr_role],
 [alpha, developer, dev_role], [beta, developer, dev_role],
 [alpha, onlooker, dev_role]].each do |project, user, role|
  member = Member.find_or_initialize_by(project_id: project.id, user_id: user.id)
  member.roles = [role]
  member.save!
end

# What a project manager needs to edit their own project's workflow, and what a
# viewer needs to read one. The pair is what makes the authorization scenario
# meaningful: view and manage have to come apart.
mgr_role.add_permission!(:view_project_workflow_rules, :manage_project_workflow_rules)
dev_role.add_permission!(:view_project_workflow_rules)

# A generic workflow worth inheriting: every status may move to every later one,
# and a new issue may be created as either of the first two.
WorkflowTransition.where(project_id: nil).delete_all
trackers.each do |tracker|
  roles.each do |role|
    statuses.each_with_index do |from, i|
      statuses[(i + 1)..].to_a.each do |to|
        WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                   old_status_id: from.id, new_status_id: to.id)
      end
    end
    statuses.first(2).each do |to|
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: 0, new_status_id: to.id)
    end
  end
end

puts "trackers: #{trackers.map(&:name).join(', ')}"
puts "roles:    #{roles.map(&:name).join(', ')}"
puts "statuses: #{statuses.map(&:name).join(', ')}"
puts "generic transitions: #{WorkflowTransition.where(project_id: nil).count}"
puts 'admin / adminadmin1!  |  mgr, dev, look / testpass1!'
