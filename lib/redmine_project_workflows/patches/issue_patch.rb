# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module IssuePatch
      # Reimplements core's method rather than delegating to it for the projects
      # that inherit. Core's own query names no project_id, so it would read
      # this project's rows together with every other project's (INV-4); there
      # is no argument that narrows it. The body below is core's, with the one
      # query replaced by a project-scoped one -- it is byte-identical in
      # Redmine 5.1, 6.1 and 7.0, and spec/models/issue_workflow_spec.rb holds
      # it to core's answers wherever no scope applies.
      def workflow_rule_by_attribute(user=nil)
        return @workflow_rule_by_attribute if @workflow_rule_by_attribute && user.nil?

        roles = roles_for_workflow(user || User.current)
        return {} if roles.empty?

        result = {}
        workflow_permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_for(
          issue: self,
          user: user || User.current,
          old_status_id: status_id
        )
        if workflow_permissions.any?
          workflow_rules = workflow_permissions.inject({}) do |hash, permission|
            hash[permission.field_name] ||= {}
            hash[permission.field_name][permission.role_id] = permission.rule
            hash
          end
          fields_with_roles = invisible_custom_field_role_map
          roles.each do |role|
            fields_with_roles.each do |field_id, role_ids|
              next if role_ids.include?(role.id)

              field_name = field_id.to_s
              workflow_rules[field_name] ||= {}
              workflow_rules[field_name][role.id] = 'readonly'
            end
          end
          workflow_rules.each do |attr, rules|
            next if rules.size < roles.size

            uniq_rules = rules.values.uniq
            result[attr] = uniq_rules.size == 1 ? uniq_rules.first : 'required'
          end
        end
        @workflow_rule_by_attribute = result if user.nil?
        result
      end

      # Core's method, with its two project-blind lookups replaced: the status
      # list that decides the initial status after a tracker change, and the
      # transition query itself. See #workflow_rule_by_attribute for why core is
      # not called for the inheriting case either.
      def new_statuses_allowed_to(user=User.current, include_default=false)
        roles = roles_for_workflow(user)

        initial_status = nil
        if new_record?
          # nop
        elsif tracker_id_changed?
          if Tracker.where(id: tracker_id_was, default_status_id: status_id_was).any?
            initial_status = default_status
          elsif RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_project(
            project: project,
            trackers: tracker,
            role_ids: roles.map(&:id)
          ).include?(status_id_was)
            initial_status = IssueStatus.find_by_id(status_id_was)
          else
            initial_status = default_status
          end
        else
          initial_status = status_was
        end

        initial_assigned_to_id = assigned_to_id_changed? ? assigned_to_id_was : assigned_to_id
        assignee_transitions_allowed = initial_assigned_to_id.present? &&
          (user.id == initial_assigned_to_id || user.group_ids.include?(initial_assigned_to_id))

        statuses = []
        statuses += RedmineProjectWorkflows::Services::TransitionQuery.allowed_statuses(
          issue: self,
          user: user,
          initial_status: initial_status,
          author: author == user,
          assignee: assignee_transitions_allowed
        )
        statuses << initial_status unless statuses.empty?
        statuses << default_status if include_default || (new_record? && statuses.empty?)

        statuses = statuses.compact.uniq.sort
        unless closable?
          # cannot close a blocked issue or a parent with open subtasks
          statuses.reject!(&:is_closed?)
        end
        unless reopenable?
          # cannot reopen a subtask of a closed parent
          statuses.select!(&:is_closed?)
        end
        statuses
      end


      private

      # See RedmineProjectWorkflows::Current for why the cache is held there and
      # not in Thread.current or RequestStore.
      def invisible_custom_field_role_map
        RedmineProjectWorkflows::Current.invisible_custom_field_role_map ||=
          compute_invisible_custom_field_role_map
      end

      def compute_invisible_custom_field_role_map
        IssueCustomField.where(visible: false).joins(:roles).pluck(:id, 'role_id').each_with_object({}) do |(field_id, role_id), map|
          map[field_id] ||= []
          map[field_id] << role_id
        end
      end

    end
  end
end
