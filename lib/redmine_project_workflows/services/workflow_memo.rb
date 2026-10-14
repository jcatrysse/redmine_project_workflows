# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Turns on the per-combination memo of TransitionQuery and PermissionQuery
    # for the duration of a block. Used around the actions that ask the same
    # workflow question once per selected issue: measured on the combined GEOxyz
    # 7.0 host, the context menu for 10 issues ran about 28 workflow statements.
    #
    # A rule write inside the block clears the memo through
    # Resolver.reset_cache!, as it clears every other workflow cache.
    module WorkflowMemo
      def self.during
        current = RedmineProjectWorkflows::Current
        outer = [current.allowed_statuses, current.permission_rules]
        current.allowed_statuses ||= {}
        current.permission_rules ||= {}
        yield
      ensure
        current.allowed_statuses, current.permission_rules = outer
      end
    end
  end
end
