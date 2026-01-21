# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowRulePatch
      def copy_for_project(source_project_id, target_project_id, source_tracker, source_role, target_trackers, target_roles)
        unless source_tracker.is_a?(Tracker) || source_role.is_a?(Role)
          raise ArgumentError,
                "source_tracker or source_role must be specified, given: " \
                "#{source_tracker.class.name} and #{source_role.class.name}"
        end

        target_trackers = Array.wrap(target_trackers).compact
        target_roles = Array.wrap(target_roles).compact

        target_trackers = Tracker.sorted.to_a if target_trackers.empty?
        target_roles = Role.all.select(&:consider_workflow?) if target_roles.empty?

        target_pairs = target_trackers.product(target_roles)
        skipped_pairs = []
        copy_pairs = []

        source_project_id = Integer(source_project_id) if source_project_id
        target_project_id = Integer(target_project_id) if target_project_id

        target_pairs.each do |target_tracker, target_role|
          resolved_source_tracker = source_tracker || target_tracker
          resolved_source_role = source_role || target_role
          if resolved_source_tracker == target_tracker && resolved_source_role == target_role &&
              source_project_id == target_project_id
            skipped_pairs << [target_tracker, target_role]
            next
          end
          copy_pairs << [target_tracker, target_role]
        end

        return if copy_pairs.empty?

        delete_existing = copy_pairs.size <= 1
        delete_existing_rules_for_project(target_project_id, copy_pairs, skipped_pairs) unless delete_existing

        copy_pairs.each do |target_tracker, target_role|
          copy_one_for_project(
            source_project_id,
            target_project_id,
            source_tracker || target_tracker,
            source_role || target_role,
            target_tracker,
            target_role,
            delete_existing: delete_existing
          )
        end
      end

      def copy_one_for_project(source_project_id, target_project_id, source_tracker, source_role, target_tracker, target_role, delete_existing: true)
        unless source_tracker.is_a?(Tracker) && !source_tracker.new_record? &&
          source_role.is_a?(Role) && !source_role.new_record? &&
          target_tracker.is_a?(Tracker) && !target_tracker.new_record? &&
          target_role.is_a?(Role) && !target_role.new_record?

          raise ArgumentError, 'arguments can not be nil or unsaved objects'
        end

        source_project_id = Integer(source_project_id) if source_project_id
        target_project_id = Integer(target_project_id) if target_project_id
        source_project_condition = source_project_id ? "= #{source_project_id}" : 'IS NULL'
        target_project_value = target_project_id ? target_project_id.to_s : 'NULL'

        return false if source_tracker == target_tracker && source_role == target_role &&
          source_project_id == target_project_id

        transaction do
          if delete_existing
            where(tracker_id: target_tracker.id, role_id: target_role.id, project_id: target_project_id).delete_all
          end
          connection.insert(
            "INSERT INTO #{WorkflowRule.table_name}" \
              " (tracker_id, role_id, old_status_id, new_status_id," \
               " author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, project_id)" \
              " SELECT #{target_tracker.id}, #{target_role.id}, old_status_id, new_status_id," \
                      " author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, #{target_project_value}" \
                " FROM #{WorkflowRule.table_name}" \
                " WHERE tracker_id = #{source_tracker.id} AND role_id = #{source_role.id}" \
                " AND project_id #{source_project_condition}"
          )
        end
        true
      end

      def copy_one(source_tracker, source_role, target_tracker, target_role)
        unless source_tracker.is_a?(Tracker) && !source_tracker.new_record? &&
          source_role.is_a?(Role) && !source_role.new_record? &&
          target_tracker.is_a?(Tracker) && !target_tracker.new_record? &&
          target_role.is_a?(Role) && !target_role.new_record?

          raise ArgumentError, 'arguments can not be nil or unsaved objects'
        end

        return false if source_tracker == target_tracker && source_role == target_role

        transaction do
          where(tracker_id: target_tracker.id, role_id: target_role.id, project_id: nil).delete_all
          connection.insert(
            "INSERT INTO #{WorkflowRule.table_name}" \
              " (tracker_id, role_id, old_status_id, new_status_id," \
               " author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, project_id)" \
              " SELECT #{target_tracker.id}, #{target_role.id}, old_status_id, new_status_id," \
                      " author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, NULL" \
                " FROM #{WorkflowRule.table_name}" \
                " WHERE tracker_id = #{source_tracker.id} AND role_id = #{source_role.id} AND project_id IS NULL"
          )
        end
        true
      end

      def delete_existing_rules_for_project(project_id, copy_pairs, skipped_pairs)
        tracker_ids = copy_pairs.map { |tracker, _role| tracker.id }.uniq
        role_ids = copy_pairs.map { |_tracker, role| role.id }.uniq
        scope = where(tracker_id: tracker_ids, role_id: role_ids, project_id: project_id)
        return scope.delete_all if skipped_pairs.empty?

        table = WorkflowRule.arel_table
        exclusions = skipped_pairs.map do |tracker, role|
          table[:tracker_id].eq(tracker.id).and(table[:role_id].eq(role.id))
        end
        predicate = exclusions.reduce { |memo, condition| memo.or(condition) }
        scope.where.not(predicate).delete_all
      end
    end
  end
end
