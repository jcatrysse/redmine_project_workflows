# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # The workflow matrices' cell helpers, and the project selector above them.
    #
    # Attached to the **controllers'** helper chains, never to `WorkflowsHelper`
    # itself. This is the same rule `ProjectsHelperPatch` follows and the same
    # measurement stands behind it; see {apply!}.
    module WorkflowsHelperPatch
      include RedmineProjectWorkflows::VersionHelper
      include RedmineProjectWorkflows::BulkActionsHelper

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
        # **Two controllers, because two render these views.** `WorkflowsController`
        # owns the administration screens; `ProjectWorkflowsController` renders
        # core's own `workflows/_form` partial for the project matrices, and the
        # bulk row and column actions are injected into that partial. Naming one
        # would leave the other's cells unrendered.
        #
        # Including a module twice is a no-op, so a code reload is harmless.
        def apply!
          WorkflowsController.helper(self)
          ProjectWorkflowsController.helper(self)
          self
        end
      end

      def options_for_workflow_select(name, objects, selected, options = {})
        objects = normalize_workflow_objects(name, objects)
        selected = normalize_workflow_selected(objects, selected)

        super
      end

      def field_permission_tag(permissions, status, field, roles)
        name = field.is_a?(CustomField) ? field.id.to_s : field
        options = [['', ''], [l(:label_readonly), 'readonly']]
        options << [l(:label_required), 'required'] unless field_required?(field)
        html_options = {}

        if (perm = permissions[status.id][name])
          if perm.uniq.size > 1 || perm.size < workflow_permissions_matrix_size
            options << [l(:label_no_change_option), 'no_change']
            selected = 'no_change'
          else
            selected = perm.first
          end
        end

        hidden = field.is_a?(CustomField) &&
                 !field.visible? &&
                 !roles.detect { |role| role.custom_fields.to_a.include?(field) }

        if hidden
          options[0][0] = l(:label_hidden)
          selected = ''
          html_options[:disabled] = true
        end

        select_tag("permissions[#{status.id}][#{name}]", options_for_select(options, selected), html_options)
      end

      # The state of the current selection, as text. Three states have to stay
      # tellable apart (INV-3), and "own empty workflow" is a valid, deliberate
      # configuration -- so it is named in words rather than marked as a
      # problem. No colour, and no markup Redmine does not already use.
      def project_workflow_scope_state_tag(state)
        text =
          case state.state
          when :inherits then l(:label_project_workflow_state_inherits)
          when :own then l(:label_project_workflow_state_own)
          when :own_empty then l(:label_project_workflow_state_own_empty)
          else
            # A mixed selection names only the states it actually contains --
            # "0 own empty workflows" is noise, not information.
            {
              label_project_workflow_count_own: state.own,
              label_project_workflow_count_own_empty: state.own_empty,
              label_project_workflow_count_inherits: state.inheriting
            }.reject { |_key, count| count.zero? }
             .map { |key, count| l(key, count: count) }.join(', ')
          end
        content_tag(:span, text, class: "project-workflow-scope-state #{state.state}")
      end

      # One cell of the summary grid. Core builds the link with a bare
      # {:action => 'edit', :role_id => ..., :tracker_id => ...}, which carries
      # no project: with a project selected, the counts on the page would be
      # that project's and the link would open the generic matrix. The
      # selection is nil when it is the default -- the generic workflow alone --
      # so the URL then stays byte-identical to core's.
      def project_workflow_summary_count_link(count, tracker, role, selection)
        url = { action: 'edit', role_id: role, tracker_id: tracker }
        url[:project_id] = selection if selection.present?

        link_to(project_workflows_summary_count_body(count), url,
                title: l(:button_edit),
                class: project_workflows_summary_count_class(count))
      end

      def transition_tag(transition_count, old_status, new_status, name)
        tag_name = "transitions[#{old_status.try(:id) || 0}][#{new_status.id}][#{name}]"
        if old_status == new_status
          check_box_tag(tag_name, '1', true,
                        { :disabled => true,
                          :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}" })
        elsif transition_count.zero? || transition_count == workflow_permissions_matrix_size
          hidden_field_tag(tag_name, '0', :id => nil) +
            check_box_tag(tag_name, '1', transition_count != 0,
                          :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}")
        else
          # The same classes as a checkbox cell (claude F06). Core's own toggle
          # cannot reach a select whatever it is called -- it selects on
          # input[type=checkbox] -- but the plugin's row and column actions
          # select on the class alone, so one selector reaches both kinds of
          # cell and the mixed ones stop being the cells bulk editing skips.
          select_tag(
            tag_name,
            options_for_select(
              [
                [l(:general_text_Yes), '1'],
                [l(:general_text_No), '0'],
                [l(:label_no_change_option), 'no_change']
              ],
              'no_change'
            ),
            :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}"
          )
        end
      end

      private

      # How many workflows one cell of the matrix stands for. Core computes
      # @roles.size * @trackers.size; the plugin adds the scopes the selection
      # covers. Kept under core's name because that is what core's two cell
      # helpers ask for, and answered by the module that also renders the row and
      # column actions, so the two can never disagree about the size of a cell.
      def workflow_permissions_matrix_size
        project_workflow_selection_size
      end

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
