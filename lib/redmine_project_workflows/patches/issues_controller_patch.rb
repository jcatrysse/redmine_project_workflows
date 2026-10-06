# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # Puts the plugin's issue-form helper into the chain of the controller that
    # renders the issue form (WP8).
    #
    # Not a prepend: nothing of core's is overridden here. The Deface override in
    # +overrides/issues_attributes_add_transition_map_link.rb+ injects a call to
    # +project_workflow_map_link+ into +issues/_attributes+, which is a view
    # IssuesController owns, and Rails' +include_all_helpers+ is built from the
    # host application's helper paths -- it never reaches a plugin's
    # +app/helpers+. Without this the override renders and raises
    # +NoMethodError+ on every issue form.
    #
    # +helper+ rather than +ProjectWorkflowMapsHelper+ being included into
    # IssuesController directly, for the reason the forbidden-constructs table in
    # CLAUDE.md gives: every public instance method of a controller is an action,
    # so a module mixed into one makes its methods routable.
    #
    # IssuesController is the only controller that renders +issues/_form+, and so
    # +issues/_attributes+: +issues/new+, +issues/edit+, the inline edit form on
    # +issues/show+, and the +update_issue_form+ round trip all go through it.
    # +issues/bulk_edit+ has markup of its own and is deliberately out of scope --
    # a selection can span projects and trackers, so one map would be a lie about
    # most of it.
    module IssuesControllerPatch
      def self.apply!
        IssuesController.helper(ProjectWorkflowMapsHelper)
        self
      end
    end
  end
end
