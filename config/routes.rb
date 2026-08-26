# frozen_string_literal: true

# The workflow matrices themselves stay on Redmine's own routes; the plugin only
# adds the three scope actions (INV-3). They sit on their own path rather than
# under /workflows so that nothing here can shadow a core route -- plugin routes
# are drawn after core's.
post   'project_workflow_scopes',       to: 'project_workflow_scopes#create', as: 'project_workflow_scopes'
delete 'project_workflow_scopes',       to: 'project_workflow_scopes#destroy'
post   'project_workflow_scopes/clear', to: 'project_workflow_scopes#clear', as: 'clear_project_workflow_scopes'

# The inventory: a read-only view across every project's workflow decisions.
# On its own path for the same reason as the scope actions above.
get 'project_workflow_inventories', to: 'project_workflow_inventories#index',
                                    as: 'project_workflow_inventories'

# The project's own workflow screens (WP4). The project is named by the path and
# by nothing else, so no request parameter can widen what an action reaches
# (INV-7): every action here authorizes against params[:project_id] and writes
# to that one project.
#
# The names are deliberately singular where the administration routes above are
# plural -- project_workflow_scope_path is this project's scope, while
# project_workflow_scopes_path is the administration action over a selection.
get    'projects/:project_id/workflow/transitions',   to: 'project_workflows#transitions',
                                                      as: 'project_workflow_transitions'
patch  'projects/:project_id/workflow/transitions',   to: 'project_workflows#update_transitions'
get    'projects/:project_id/workflow/permissions',   to: 'project_workflows#permissions',
                                                      as: 'project_workflow_permissions'
patch  'projects/:project_id/workflow/permissions',   to: 'project_workflows#update_permissions'
get    'projects/:project_id/workflow/compare',       to: 'project_workflows#compare',
                                                      as: 'project_workflow_compare'
post   'projects/:project_id/workflow/scope',         to: 'project_workflows#enable',
                                                      as: 'project_workflow_scope'
delete 'projects/:project_id/workflow/scope',         to: 'project_workflows#inherit'
post   'projects/:project_id/workflow/scope/clear',   to: 'project_workflows#clear',
                                                      as: 'clear_project_workflow_scope'

# The workflow panel on the issue form (WP8). Read-only, and authorized by the
# issue rather than by a permission of its own: a saved issue through
# Issue.visible, and the new-issue form through the project plus add_issues.
#
# Two paths to one action, because the two carry their scope differently: with an
# issue the project is the issue's and no parameter is consulted for it, and
# without one the project is named by the path. Neither can be widened by a
# request parameter (INV-7).
get 'issues/:issue_id/workflow_map',    to: 'project_workflow_maps#show',
                                        as: 'issue_workflow_map'
get 'projects/:project_id/workflow_map', to: 'project_workflow_maps#show',
                                         as: 'project_workflow_map'
