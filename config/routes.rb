# frozen_string_literal: true

# The workflow matrices themselves stay on Redmine's own routes; the plugin only
# adds the three scope actions (INV-3). They sit on their own path rather than
# under /workflows so that nothing here can shadow a core route -- plugin routes
# are drawn after core's.
post   'project_workflow_scopes',       to: 'project_workflow_scopes#create', as: 'project_workflow_scopes'
delete 'project_workflow_scopes',       to: 'project_workflow_scopes#destroy'
post   'project_workflow_scopes/clear', to: 'project_workflow_scopes#clear', as: 'clear_project_workflow_scopes'
