# frozen_string_literal: true

module RedmineProjectWorkflows
  module Hooks
    # The checkbox on Redmine's *Copy project* form.
    #
    # Core renders `call_hook :view_projects_copy_only_items` inside the very
    # fieldset that holds *Members*, *Issues*, *Wiki* and the rest, on 5.1, 6.1
    # and 7.0 identically. It is an extension point core added for exactly this,
    # so the plugin's own workflow item joins that list without a Deface
    # override and INV-9's count stays at fifteen.
    #
    # A ViewListener rather than a plain Listener because the item is markup:
    # `render_on` renders the partial through the view that called the hook, so
    # the partial gets `l`, `check_box_tag` and the source project as a local,
    # and the plugin writes no HTML in Ruby.
    #
    # Separate from ProjectCopyHook, which answers the *model* hook inside
    # Project#copy. One class could carry both, but a model-hook object that has
    # ApplicationHelper and every Rails route helper mixed into it is not what it
    # says it is.
    class ProjectCopyFormHook < Redmine::Hook::ViewListener
      render_on :view_projects_copy_only_items,
                partial: 'redmine_project_workflows/copy_project_workflow'
    end
  end
end
