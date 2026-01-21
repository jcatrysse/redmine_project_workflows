# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowsHelperPatch
      GlobalWorkflowProject = Struct.new(:id, :name)

      def options_for_workflow_select(name, objects, selected, options = {})
        objects = normalize_workflow_objects(name, objects)
        selected = normalize_workflow_selected(objects, selected)

        html = super(name, objects, selected, options)
      end

      def field_permission_tag(permissions, status, field, roles)
        name = field.is_a?(CustomField) ? field.id.to_s : field
        options = [["", ""], [l(:label_readonly), "readonly"]]
        options << [l(:label_required), "required"] unless field_required?(field)
        html_options = {}

        if (perm = permissions[status.id][name])
          if perm.uniq.size > 1 || perm.size < workflow_permissions_matrix_size
            options << [l(:label_no_change_option), "no_change"]
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

      def transition_tag(transition_count, old_status, new_status, name)
        tag_name = "transitions[#{old_status.try(:id) || 0}][#{new_status.id}][#{name}]"
        if old_status == new_status
          check_box_tag(tag_name, "1", true,
                        { :disabled => true, :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}" })
        elsif transition_count == 0 || transition_count == workflow_permissions_matrix_size
          hidden_field_tag(tag_name, "0", :id => nil) +
            check_box_tag(tag_name, "1", transition_count != 0,
                          :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}")
        else
          select_tag(
            tag_name,
            options_for_select(
              [
                [l(:general_text_Yes), "1"],
                [l(:general_text_No), "0"],
                [l(:label_no_change_option), "no_change"]
              ],
              "no_change"
            )
          )
        end
      end

      private

      def workflow_permissions_matrix_size
        project_multiplier = @projects_for_update.present? ? @projects_for_update.size : 1
        project_multiplier += 1 if @global_selected && @projects_for_update.present?
        @roles.size * @trackers.size * project_multiplier
      end

      def normalize_workflow_objects(name, objects)
        return objects unless name == 'project_id[]'

        normalized = []
        global_option = GlobalWorkflowProject.new('global', l(:label_project_workflows_global))

        Array(objects).each do |object|
          id = workflow_object_id(object).to_s
          next if id == 'all'

          if id == 'global'
            normalized << global_option
          elsif object.is_a?(Array)
            normalized << GlobalWorkflowProject.new(object[1], object[0])
          else
            normalized << object
          end
        end

        normalized.unshift(global_option) unless normalized.any? { |object| workflow_object_id(object).to_s == 'global' }
        normalized
      end

      def normalize_workflow_selected(objects, selected)
        if selected.is_a?(String)
          if selected == 'global'
            return objects.select { |object| object.id.to_s == 'global' }
          end

          return objects.select { |object| object.id.to_s == selected }
        end

        return selected unless selected.respond_to?(:map)

        selected.map do |value|
          next value if value.respond_to?(:id)

          objects.find { |object| object.id.to_s == value.to_s }
        end.compact
      end

      def workflow_object_id(object)
        return object[1] if object.is_a?(Array)

        object.respond_to?(:id) ? object.id : object
      end
    end
  end
end
