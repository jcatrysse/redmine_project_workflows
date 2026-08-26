# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsActionMenuAddInventoryLink
      # The inventory is the one workflow screen core does not have, so it needs
      # a way in. It goes next to core's own "Summary" link, which is the same
      # kind of thing: a read-only view across the workflow configuration.
      #
      # Core renders this partial from workflows/edit and workflows/permissions
      # only. The summary and copy pages do not, so the summary page gets the
      # link from the plugin's own header partial instead.
      Deface::Override.new(
        virtual_path: 'workflows/_action_menu',
        name: 'redmine_project_workflows_action_menu_add_inventory_link',
        insert_bottom: 'div.contextual',
        text: <<~ERB
          <%= project_workflows_icon_link('list', l(:label_project_workflow_inventory),
                                          project_workflow_inventories_path) %>
        ERB
      )
    end
  end
end
