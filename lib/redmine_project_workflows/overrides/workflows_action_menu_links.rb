# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsActionMenuLinks
      # The two links the plugin adds to Redmine's own workflow action menu, in
      # one override because they go in the same place for the same reason.
      #
      # Core renders this partial from workflows/edit and workflows/permissions
      # only. The summary and copy pages do not; both link to workflows/edit from
      # their own heading, so one anchor reaches the whole area in one click.
      #
      # **The cross-link is the one ADR-003 asks for** ("core's workflow screen
      # points at the plugin's, and the plugin's points back"), and it is the one
      # that matters after WP12: somebody who lands on Redmine's screen looking
      # for the project selector that used to be there has nothing else telling
      # them where it went. Answered **A** by Jan on 2026-08-28, against the
      # alternative of relying on the administration menu alone.
      #
      # The inventory link is the older of the two and goes when the project
      # dimension does: "which projects have taken a workflow over" is a question
      # about projects, and after WP12 it is asked from the plugin's own action
      # bar, which already carries it.
      #
      # INV-9: spec/integration/deface_overrides_spec.rb asserts each of them
      # against the rendered page, with an assertion only that link can satisfy.
      Deface::Override.new(
        virtual_path: 'workflows/_action_menu',
        name: 'redmine_project_workflows_action_menu_links',
        insert_bottom: 'div.contextual',
        text: <<~ERB
          <%= project_workflows_icon_link('list', l(:label_project_workflow_inventory),
                                          project_workflow_inventories_path) %>
          <%= project_workflows_icon_link('workflows', l(:label_project_workflow_rules),
                                          project_workflow_rules_path) %>
        ERB
      )
    end
  end
end
