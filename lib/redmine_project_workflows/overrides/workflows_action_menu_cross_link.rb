# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsActionMenuCrossLink
      # The one link from Redmine's own workflow screens to the plugin's
      # administration area (WP12, ADR-003 -- "core's workflow screen points at
      # the plugin's, and the plugin's points back"). Answered **A** by Jan on
      # 2026-08-28, against the alternative of relying on the administration
      # menu alone.
      #
      # It is the link that matters after WP12: somebody who lands on Redmine's
      # screen looking for the project selector that used to be there has
      # nothing else telling them where it went.
      #
      # Core renders this partial from workflows/edit and workflows/permissions
      # only. The summary and copy pages do not; both link to workflows/edit
      # from their own heading, so one anchor reaches the whole area in one
      # click.
      #
      # It used to carry a second link, to the inventory. That went with the
      # project dimension: "which projects have taken a workflow over" is a
      # question about projects, and it is now asked from the plugin's own
      # action bar, one click further on.
      #
      # INV-9: spec/integration/deface_overrides_spec.rb asserts it against the
      # rendered page, scoped to the element this override writes into. An
      # unscoped assertion would pass whatever this does -- the `admin_menu`
      # entry WP12 registered renders the same href into the layout of every
      # administration page.
      Deface::Override.new(
        virtual_path: 'workflows/_action_menu',
        name: 'redmine_project_workflows_action_menu_cross_link',
        insert_bottom: 'div.contextual',
        text: <<~ERB
          <%= project_workflows_icon_link('workflows', l(:label_project_workflow_rules),
                                          project_workflow_rules_path) %>
        ERB
      )
    end
  end
end
