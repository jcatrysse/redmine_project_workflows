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
  end
end
