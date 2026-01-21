# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class PermissionWriter
      def self.replace_permissions(project, trackers, roles, permissions)
        replace_permissions_for_project_id(project.id, trackers, roles, permissions)
      end

      def self.replace_permissions_for_project_id(project_id, trackers, roles, permissions)
        trackers = Array.wrap(trackers)
        roles = Array.wrap(roles)
        permissions = normalize_permissions(permissions)

        WorkflowPermission.transaction do
          scope = WorkflowPermission.where(
            tracker_id: trackers.map(&:id),
            role_id: roles.map(&:id),
            project_id: project_id
          )
          delete_permissions_for_scope(scope, permissions)
          rows = build_permission_rows(project_id, trackers, roles, permissions)
          insert_permission_rows(rows)
        end
      end

      def self.delete_permissions_for_scope(scope, permissions)
        permissions = normalize_permissions(permissions)
        table = WorkflowPermission.arel_table
        conditions = permissions.each_with_object([]) do |(status_id, rule_by_field), memo|
          next unless rule_by_field.respond_to?(:keys)

          field_names = rule_by_field.keys
          next if field_names.empty?

          memo << table[:old_status_id].eq(status_id.to_i).and(table[:field_name].in(field_names))
        end
        return if conditions.empty?

        predicate = conditions.reduce { |memo, condition| memo.or(condition) }
        scope.where(predicate).delete_all
      end

      def self.build_permission_rows(project_id, trackers, roles, permissions)
        permissions = normalize_permissions(permissions)
        rows = []
        permissions.each do |status_id, rule_by_field|
          status_id = status_id.to_i
          next unless rule_by_field.respond_to?(:each)

          rule_by_field.each do |field, rule|
            next unless rule.present?

            trackers.each do |tracker|
              roles.each do |role|
                rows << {
                  role_id: role.id,
                  tracker_id: tracker.id,
                  old_status_id: status_id,
                  field_name: field,
                  rule: rule,
                  project_id: project_id,
                  type: 'WorkflowPermission'
                }
              end
            end
          end
        end
        rows
      end

      def self.insert_permission_rows(rows)
        return if rows.empty?

        rows.each_slice(1000) do |slice|
          WorkflowPermission.insert_all(slice)
        end
      end

      def self.normalize_permissions(permissions)
        return {} if permissions.nil?

        if permissions.respond_to?(:to_unsafe_h)
          permissions.to_unsafe_h
        elsif permissions.respond_to?(:to_h)
          permissions.to_h
        else
          permissions
        end
      end
      private_class_method :normalize_permissions
    end
  end
end
