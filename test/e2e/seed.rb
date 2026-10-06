# frozen_string_literal: true

# Plugin data for the end-to-end scenarios in test/e2e/, run by
# .codex/start_server.sh after the generic seed (.codex/e2e/seed.rb), so the
# users admin, manager, reporter, outsider and the projects e2e-project and
# e2e-private exist already.
#
# Adds what the generic seed cannot know about this plugin:
#   viewer   member of e2e-project with "E2E workflow viewer": may read the
#            project's workflow (view_project_workflow_rules), not change it
#   a generic workflow for the "E2E full" role (a copy of core's Manager), so
#   the manager can move issues before any project decides anything
#
# Then it puts the plugin in its starting state: no project has a workflow of
# its own. Idempotent; test/e2e/support.mjs calls the same reset between scenarios.
User.current = User.find_by(login: 'admin')
password = ENV.fetch('RMP_USER_PASSWORD', ENV.fetch('RMP_ADMIN_PASSWORD', 'Redmine7Test!'))

viewer = User.find_by(login: 'viewer') ||
         User.new(login: 'viewer', firstname: 'Viewer', lastname: 'E2E', mail: 'viewer@example.net')
viewer.password = viewer.password_confirmation = password
viewer.must_change_passwd = false
viewer.status = User::STATUS_ACTIVE
viewer.save!(validate: false)

view_role = Role.find_by(name: 'E2E workflow viewer') || Role.new(name: 'E2E workflow viewer', assignable: true)
view_role.permissions = %i[view_issues add_issues edit_issues add_issue_notes view_project_workflow_rules]
view_role.issues_visibility = 'all'
view_role.save!

project = Project.find_by!(identifier: 'e2e-project')
unless Member.where(user_id: viewer.id, project_id: project.id).exists?
  Member.create!(principal: viewer, project: project, roles: [view_role])
end

full = Role.find_by!(name: 'E2E full')
template = Role.find_by(name: 'Manager')
[full, view_role].each do |role|
  next if template.nil? || WorkflowTransition.where(role_id: role.id, project_id: nil).exists?

  role.copy_workflow_rules(template)
end

ProjectWorkflowScope.delete_all
WorkflowRule.where.not(project_id: nil).delete_all
Setting.plugin_redmine_project_workflows = Redmine::Plugin.find(:redmine_project_workflows).settings[:default]

puts "Plugin seed: viewer + role '#{view_role.name}', generic transitions for '#{full.name}': " \
     "#{WorkflowTransition.where(role_id: full.id, project_id: nil).count}, project rules: " \
     "#{WorkflowRule.where.not(project_id: nil).count}"
