# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # Deleting an issue status says what it did to the projects that run their
    # own workflow (audit finding F03).
    #
    # Core's IssueStatus#delete_workflow_rules removes every workflow row naming
    # the status, in both populations. The plugin's scope rows survive it, and a
    # scope whose rules have all gone is an own **empty** workflow: for
    # transitions that permits no change of status at all. So a system
    # administrator tidying up an unused status can freeze a project's issues
    # without being told.
    #
    # **Warn, do not clean up.** Deleting the emptied scopes would return those
    # combinations to the generic workflow, which is a decision the project made
    # and the administrator did not undo -- collapsing two of INV-3's three
    # meanings on their behalf. The deletion itself is left exactly as core
    # performs it; the only change is that the administrator is told.
    #
    # The count is taken **before** super, because super is what removes the
    # rules the count is over, and it is only reported if the status is really
    # gone afterwards -- core swallows a failed destroy into flash[:error] and
    # redirects, so "did it happen" cannot be read off the response.
    #
    # Nothing here is public but #destroy, which is already an action. A second
    # public method on a controller is a second route (CLAUDE.md).
    module IssueStatusesControllerPatch
      # Above this many affected projects the inventory link drops its project
      # filter rather than naming them all: a query string of several hundred
      # ids is a request some proxies refuse, and the unfiltered inventory still
      # lists every own workflow.
      INVENTORY_FILTER_LIMIT = 50

      def destroy
        status_id = params[:id].to_s.match?(/\A\d+\z/) ? params[:id].to_i : nil
        impact = status_id && IssueStatus.exists?(status_id) ? impact_of_deleting(status_id) : nil

        super

        return unless impact&.any?
        return if IssueStatus.exists?(status_id)

        warn_about_emptied_workflows(impact)
      end

      private

      def impact_of_deleting(status_id)
        RedmineProjectWorkflows::Services::StatusDeletionImpact.of(status_id)
      end

      # Set after super, which has already redirected. That is deliberate and it
      # works: a flash written during the action is read by the request the
      # redirect leads to, which is the issue statuses list core sends the
      # administrator back to.
      def warn_about_emptied_workflows(impact)
        flash[:warning] = l(:warning_project_workflow_status_deleted_emptied,
                            count: impact.count, link: inventory_link(impact.project_ids))
      end

      # A link the administrator can act on, filtered to the projects that were
      # actually affected -- the inventory's own project filter, so nothing new
      # is invented for it.
      #
      # There is no user-supplied text anywhere in the result -- integers and one
      # translated label -- which is what makes it safe to put in a flash, since
      # Redmine renders flash messages with html_safe on all three versions.
      def inventory_link(project_ids)
        parameters = { deviations_only: '1' }
        parameters[:project_id] = project_ids.map(&:to_s) if project_ids.size <= INVENTORY_FILTER_LIMIT
        view_context.link_to(l(:label_project_workflow_inventory),
                             project_workflow_inventories_path(parameters))
      end
    end
  end
end
