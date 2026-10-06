# frozen_string_literal: true

module RedmineProjectWorkflows
  module Hooks
    # The plugin's only hook listener, and the plugin's only reason to have one.
    #
    # Project#copy has no extension point but this: its list of things to copy
    # is a local array of method names, and the one thing a plugin is offered is
    # +model_project_copy_before_save+, called with the source and the
    # destination inside core's own transaction, after everything else has been
    # copied and before the final save. Redmine 5.1, 6.1 and 7.0 call it
    # identically.
    #
    # Everything the copy actually does is in Services::ProjectWorkflowCopier;
    # this is the wiring and the argument checking, so that the service can be
    # called from a console or a spec without a hook context.
    #
    # A failure here is deliberately *not* swallowed. The call is inside core's
    # transaction, so raising rolls the whole copy back and the operator is told;
    # rescuing would hand them a project that looks copied and quietly permits
    # more than the original -- which is the defect this exists to remove.
    class ProjectCopyHook < Redmine::Hook::Listener
      def model_project_copy_before_save(context = {})
        source = context[:source_project]
        destination = context[:destination_project]
        return unless source.is_a?(Project) && destination.is_a?(Project)
        return if source.new_record? || destination.new_record?
        # The checkbox on the copy form, carried here by Patches::ProjectPatch#copy
        # -- core's model hook is given the two projects and nothing else.
        return unless destination.copy_project_workflow?

        RedmineProjectWorkflows::Services::ProjectWorkflowCopier.copy(
          source_project_id: source.id,
          target_project_id: destination.id
        )
      end
    end
  end
end
