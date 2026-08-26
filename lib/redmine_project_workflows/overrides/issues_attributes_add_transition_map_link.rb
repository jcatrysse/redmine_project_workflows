# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    # WP8. The link to the workflow panel, beside core's own status dropdown.
    #
    # The anchor is core's +f.select :status_id+ expression, which is
    # byte-identical in Redmine 5.1, 6.1 and 7.0. The help icon rendered directly
    # after it would have been the more natural neighbour and is deliberately
    # *not* the anchor: 6.0 turned its CSS icon into an SVG sprite, so its text
    # differs between the supported versions and a +:contains+ on it would match
    # on some hosts and not others -- which produces no error, only a missing
    # link.
    #
    # +insert_after+ therefore puts the plugin's link between the select and
    # core's help icon. That is also the right reading order: core's icon
    # describes the statuses, this one describes the rules that decide which
    # statuses are there at all.
    #
    # The helper renders nothing when the form has no project or no tracker yet,
    # which is the global new-issue form before either has been chosen.
    #
    # INV-9: +spec/integration/deface_overrides_spec.rb+ asserts this override
    # against the real rendered issue form on every supported version, with an
    # assertion only it can satisfy -- the link's own path, which nothing else on
    # the page renders.
    module IssuesAttributesAddTransitionMapLink
      Deface::Override.new(
        virtual_path: 'issues/_attributes',
        name: 'redmine_project_workflows_issues_attributes_add_transition_map_link',
        insert_after: 'erb[loud]:contains("f.select :status_id")',
        text: <<~ERB
          <%= project_workflow_map_link(@issue) %>
        ERB
      )
    end
  end
end
