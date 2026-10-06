# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    # WP8. The link to the workflow panel, beside core's own status control on the
    # issue form.
    #
    # **Two overrides, because core renders that control two different ways.**
    # `issues/_attributes.html.erb` is
    #
    #   <% if @issue.safe_attribute?('status_id') && @allowed_statuses.present? %>
    #     <p><%= f.select :status_id, ... %> ... help icon ... </p>
    #   <% else %>
    #     <p><label><%= l(:field_status) %></label> <%= @issue.status %></p>
    #   <% end %>
    #
    # and the second branch is not a rare corner: it is exactly what a project
    # with its own **empty** workflow produces. `new_statuses_allowed_to` appends
    # the issue's own status to its answer only when the workflow permitted
    # something, so an empty workflow makes `@allowed_statuses` empty, and core
    # then replaces the select with a plain label -- no dropdown, no help icon,
    # and nothing anywhere on the form saying why.
    #
    # A single override on the select alone therefore withheld the panel in the
    # one case the panel exists for. Both branches get the link.
    #
    # Neither anchor is core's help icon, which would have been the more natural
    # neighbour of the first: 6.0 turned its CSS icon into an SVG sprite, so its
    # text differs between the supported versions and a `:contains` on it would
    # match on some hosts and not others -- which produces no error, only a
    # missing link. Both anchors used here are byte-identical in 5.1, 6.1 and
    # 7.0 and each is unique in the file.
    #
    # `insert_after` on the select puts the plugin's link between it and core's
    # help icon. That is also the right reading order: core's icon describes the
    # statuses, this one describes the rules that decide which statuses are
    # offered at all.
    #
    # The helper renders nothing when the form has no project or no tracker to
    # describe. Not the global new-issue form, which was the example given here
    # and is wrong: core preselects a project there, so the link does render.
    # It is the guard for a form whose project select has not resolved to one.
    #
    # INV-9: `spec/integration/deface_overrides_spec.rb` asserts each of these
    # against the real rendered issue form on every supported version, with an
    # assertion only that one can satisfy -- the first with a status select on the
    # page, the second with the select provably absent.
    #
    # The `respond_to?` guard is not defensiveness about our own controller.
    # `Patches::IssuesControllerPatch` puts the helper into `IssuesController`'s
    # chain, and core renders `issues/_attributes` only from `issues/_form`,
    # which only that controller owns. But a *neighbouring plugin* that renders
    # `issues/_form` from a controller of its own would reach this expression
    # with no such helper and raise `NoMethodError` on its own screen -- an
    # injected call into a core partial has to survive a renderer we do not
    # know about.
    module IssuesAttributesAddTransitionMapLink
      Deface::Override.new(
        virtual_path: 'issues/_attributes',
        name: 'redmine_project_workflows_issues_attributes_add_transition_map_link',
        insert_after: 'erb[loud]:contains("f.select :status_id")',
        text: <<~ERB
          <%= project_workflow_map_link(@issue) if respond_to?(:project_workflow_map_link) %>
        ERB
      )

      Deface::Override.new(
        virtual_path: 'issues/_attributes',
        name: 'redmine_project_workflows_issues_attributes_add_transition_map_link_readonly',
        insert_after: 'erb[loud]:contains("l(:field_status)")',
        text: <<~ERB
          <%= project_workflow_map_link(@issue) if respond_to?(:project_workflow_map_link) %>
        ERB
      )
    end
  end
end
