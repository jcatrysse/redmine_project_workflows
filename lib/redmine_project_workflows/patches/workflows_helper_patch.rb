# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # The project selector above core's own workflow matrices.
    #
    # One method of core's, +options_for_workflow_select+, taught to render a
    # project option list beside the tracker and role ones. The cells themselves
    # are +ProjectWorkflowMatrixHelper+ and are not a patch on anything.
    #
    # Attached to the **controller's** helper chain, never to `WorkflowsHelper`
    # itself. This is the same rule `ProjectsHelperPatch` follows and the same
    # measurement stands behind it; see {apply!}.
    module WorkflowsHelperPatch
      GlobalWorkflowProject = Struct.new(:id, :name)

      class << self
        # `WorkflowsHelper.prepend(self)` is the construct `CLAUDE.md`'s
        # forbidden-constructs table bans, and this module was the copy that
        # had not moved (finding F01 of 2026-08-28-claude-audit).
        #
        # Plugins load alphabetically and many still take a core helper over
        # with a 2013-era alias chain -- `alias_method :x_without_y, :x`, then
        # `alias_method :x, :x_with_y`. `alias_method` resolves the name through
        # `WorkflowsHelper.ancestors`, which with a prepend in place *starts* at
        # the prepended module: the neighbour copies **our** method into its
        # `_without_` alias, and that copy's `super` looks above `WorkflowsHelper`,
        # where core's own method is not. `#options_for_workflow_select` calls
        # `super`, so the administration workflow screens become
        # `NoMethodError` for both plugins, in either load order. Reproduced on a
        # running Redmine 5.1:
        #
        #   call FAILED: NoMethodError: super: no superclass method
        #                `options_for_workflow_select'
        #
        # The sibling shape is quieter and just as wrong: `#transition_tag` and
        # `#field_permission_tag` replace core outright, so a neighbour that
        # alias-chains *those* has its redefinition land on `WorkflowsHelper`
        # itself -- below the prepended module -- and never runs at all.
        #
        # `controller.helper` avoids both by construction: the module lands in
        # the controller's own `_helpers`, above `WorkflowsHelper` but not inside
        # it, so no alias chain can copy it and `super` always reaches whatever
        # `WorkflowsHelper` holds -- core's method, or a neighbour's aliased
        # version.
        #
        # **One controller, and only core's.** The plugin's own screens declare
        # `helper ProjectWorkflowMatrixHelper` in their class bodies like any
        # other Rails controller; the only thing that cannot is core's, which is
        # why this method exists at all. `ProjectWorkflowMatrixHelper` goes with
        # it, because core's administration matrices render the cells the plugin
        # draws (a mixed cell as a <select>, and the row and column actions of
        # WP5) and core's controller cannot name it either.
        #
        # Including a module twice is a no-op, so a code reload is harmless.
        def apply!
          WorkflowsController.helper(self)
          WorkflowsController.helper(ProjectWorkflowMatrixHelper)
          self
        end
      end

      def options_for_workflow_select(name, objects, selected, options = {})
        objects = normalize_workflow_objects(name, objects)
        selected = normalize_workflow_selected(objects, selected)

        super
      end

      private

      def normalize_workflow_objects(name, objects)
        return objects unless name == 'project_id[]'

        normalized = []
        global_option = GlobalWorkflowProject.new('global', l(:label_project_workflows_global))

        Array(objects).each do |object|
          id = workflow_object_id(object).to_s
          next if id == 'all'

          normalized << if id == 'global'
                          global_option
                        elsif object.is_a?(Array)
                          GlobalWorkflowProject.new(object[1], object[0])
                        else
                          object
                        end
        end

        normalized.unshift(global_option) unless normalized.any? do |object|
          workflow_object_id(object).to_s == 'global'
        end
        normalized
      end

      def normalize_workflow_selected(objects, selected)
        if selected.is_a?(String)
          return objects.select { |object| object.id.to_s == 'global' } if selected == 'global'

          return objects.select { |object| object.id.to_s == selected }
        end

        return selected unless selected.respond_to?(:map)

        selected.filter_map do |value|
          next value if value.respond_to?(:id)

          objects.find { |object| object.id.to_s == value.to_s }
        end
      end

      def workflow_object_id(object)
        return object[1] if object.is_a?(Array)

        object.respond_to?(:id) ? object.id : object
      end
    end
  end
end
