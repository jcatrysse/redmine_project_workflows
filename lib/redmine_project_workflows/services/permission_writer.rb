# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class PermissionWriter
      # The rules core's WorkflowPermission accepts. A blank rule is not a rule
      # but the request to remove one, so it is kept and dropped again when the
      # rows are built.
      RULES = %w[readonly required].freeze

      def self.replace_permissions(project, trackers, roles, permissions)
        replace_permissions_for_project_id(project.id, trackers, roles, permissions)
      end

      def self.replace_permissions_for_project_id(project_id, trackers, roles, permissions)
        trackers = Array.wrap(trackers)
        roles = Array.wrap(roles)
        return if trackers.empty? || roles.empty?

        permissions = sanitize_permissions(normalize_permissions(permissions))
        return if permissions.empty?

        WorkflowPermission.transaction do
          # See TransitionWriter: a project write records the decision too.
          if project_id
            ScopeWriter.ensure_scopes(
              project_ids: [project_id],
              tracker_ids: trackers.map(&:id),
              role_ids: roles.map(&:id),
              rule_type: ProjectWorkflowScope::PERMISSIONS
            )
          end

          scope = WorkflowPermission.where(
            tracker_id: trackers.map(&:id),
            role_id: roles.map(&:id),
            project_id: project_id
          )
          delete_permissions_for_scope(scope, permissions)
          rows = build_permission_rows(project_id, trackers, roles, permissions)
          insert_permission_rows(rows)
        end
        # See TransitionWriter: the rules have changed, so anything cached from
        # them is now wrong.
        Resolver.reset_cache!
      end

      # INV-2: the rows are written with insert_all, which runs no validations,
      # so this whitelist *is* the validation. It restores what core's
      # WorkflowPermission checks -- validates_inclusion_of :rule,
      # validate_field_name and the presence of old_status -- which the
      # plugin's routing of replace_permissions would otherwise have removed
      # from the generic write path as well.
      #
      # An entry that fails the whitelist is dropped before the delete, not
      # only before the insert, so an unacceptable value changes nothing rather
      # than clearing the rule it names.
      def self.sanitize_permissions(permissions)
        status_ids = valid_status_ids
        field_names = valid_field_names

        permissions.each_with_object({}) do |(status_id, rule_by_field), sanitized|
          next unless rule_by_field.respond_to?(:each)
          next unless status_ids.include?(status_id.to_s)

          rule_by_field.each do |field, rule|
            next unless field_names.include?(field.to_s)
            next unless rule.blank? || RULES.include?(rule.to_s)

            sanitized[status_id] ||= {}
            sanitized[status_id][field] = rule
          end
        end
      end
      private_class_method :sanitize_permissions

      def self.valid_status_ids
        IssueStatus.pluck(:id).to_set(&:to_s)
      end
      private_class_method :valid_status_ids

      # Core accepts any run of digits as a custom field reference; requiring
      # the field to exist is strictly narrower and cannot reject anything the
      # matrix offers, because it only offers the trackers' own custom fields.
      def self.valid_field_names
        (Tracker::CORE_FIELDS_ALL + IssueCustomField.pluck(:id).map(&:to_s)).to_set
      end
      private_class_method :valid_field_names

      def self.delete_permissions_for_scope(scope, permissions)
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
        rows = []
        permissions.each do |status_id, rule_by_field|
          status_id = status_id.to_i
          next unless rule_by_field.respond_to?(:each)

          rule_by_field.each do |field, rule|
            next if rule.blank?

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
