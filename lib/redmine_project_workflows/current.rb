# frozen_string_literal: true

module RedmineProjectWorkflows
  # Request-scoped state.
  #
  # Rails resets CurrentAttributes around every request and every job through
  # the executor, so nothing stored here outlives the request that filled it.
  # Thread.current gives no such guarantee -- a threaded application server
  # reuses a thread across requests, and a configuration change would not be
  # seen until the thread was recycled. RequestStore would do, but only up to
  # Redmine 6.1: Redmine 7.0 no longer bundles request_store at all, so on 7.0
  # the Thread.current branch this replaces was not a dead fallback but the
  # only path.
  class Current < ActiveSupport::CurrentAttributes
    # {custom_field_id => [role_id, ...]} for the issue custom fields that are
    # not visible to everyone. One query per request instead of one per issue.
    attribute :invisible_custom_field_role_map

    # {[project_id, tracker_id, rule_type] => [role_id, ...]} -- which roles a
    # project answers for itself. See Services::Resolver.scoped_role_ids.
    attribute :scoped_role_ids

    # {[project_id, tracker_id] => [status_id, ...]} -- the statuses a project's
    # effective workflow for one tracker uses, with no role filter. Saves the
    # repeat when several issues of the same tracker in the same project change
    # tracker in one request. See Patches::IssuePatch#tracker=.
    #
    # Unlike scoped_role_ids this is derived from the *rules*, not only from the
    # scope table, so it goes stale on a rule write as well -- which is why
    # reset_workflow_caches! is called from the rule writers too and not only
    # from ScopeWriter.
    attribute :effective_status_ids

    # Forget everything cached about the workflow configuration. Called after
    # any write that changes a scope **or a rule**, so that a request which
    # changes the configuration and then reads it back does not answer from a
    # cache it has just invalidated.
    def self.reset_workflow_caches!
      self.scoped_role_ids = nil
      self.effective_status_ids = nil
    end
  end
end
