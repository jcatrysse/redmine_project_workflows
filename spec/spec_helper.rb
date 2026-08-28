# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../../config/environment', __dir__)
require 'rspec/rails'

# Deliberately no fallback that applies the patches when the host boot did not.
# Such a fallback hides the one failure mode that matters most here: an init.rb
# that registers its patches somewhere Rails never calls leaves the plugin doing
# nothing in a real installation, and a green suite would say otherwise.
# spec/plugin_conventions_spec.rb asserts the boot did apply them.

# Small helpers for the scope table (ADR-001). They read as the three states of
# INV-3 so that a spec says what it is arranging rather than which rows it is
# inserting.
module ProjectWorkflowScopeHelpers
  # "This project runs its own workflow for this tracker and role." Rules are a
  # separate matter: a scope without rules is an own *empty* workflow.
  def give_own_workflow(project, tracker, role, rule_type = ProjectWorkflowScope::TRANSITIONS)
    ProjectWorkflowScope.create!(
      project_id: id_of(project),
      tracker_id: id_of(tracker),
      role_id: id_of(role),
      rule_type: rule_type
    )
  end

  def own_workflow?(project, tracker, role, rule_type = ProjectWorkflowScope::TRANSITIONS)
    ProjectWorkflowScope.exists?(
      project_id: id_of(project), tracker_id: id_of(tracker),
      role_id: id_of(role), rule_type: rule_type
    )
  end

  def id_of(object)
    object.respond_to?(:id) ? object.id : object
  end
end

# "Did this write take the scope lock before it touched a rule?", asked of the
# statements one block actually issued.
#
# Here rather than in one spec file because four write paths have to answer it
# and they are tested from three of them: the two matrix writers and the two
# scope actions from spec/services/workflow_concurrency_spec.rb, and the copy
# screen from spec/controllers/project_workflow_rules_controller_spec.rb, which
# needs a controller. Finding F01 was one path missing the lock while a universal claim
# stood in docs/design.md; a second copy of the helpers would be the same shape
# of mistake in the tests.
module WorkflowStatementOrderHelpers
  def statements_during
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      seen << payload[:sql].to_s
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def index_of_scope_lock(statements)
    statements.index { |sql| sql.match?(/project_workflow_scopes/i) && sql.match?(/FOR UPDATE/i) }
  end

  def index_of_first_rule_write(statements)
    statements.index { |sql| sql.match?(/\A\s*(INSERT INTO|DELETE FROM|UPDATE)\s+\W?workflows\b/i) }
  end

  # SQLite has no row locking to assert and is not one of the nine supported
  # cells; PostgreSQL, MySQL and MariaDB all speak SELECT ... FOR UPDATE.
  def row_locking?
    ActiveRecord::Base.connection.adapter_name.match?(/postgres|mysql|trilogy/i)
  end
end

# What a *neighbouring* plugin demands before core's issue pages will render.
#
# `redmine_view_issue_description` prepends IssuesController and answers 403 to
# #show, #edit and #update unless the reader holds :view_issue_description for
# the issue's tracker. That is the plugin working as designed -- and it means
# the examples here that open an issue form fail on a host carrying it, for a
# reason that has nothing to do with what they assert. They are about the markup
# on the form, not about who may reach it; this plugin's own authorization is
# asserted where it belongs, against this plugin's own controllers.
#
# Named rather than derived, and it has to be: the gate is a controller prepend
# and the permission is declared with an **empty** action hash, so
# Redmine::AccessControl holds nothing connecting it to issues#show. There is
# no computable answer -- which is a correction to what finding F04 of
# 2026-08-28-claude-plugin-compat-5.1 suggested. A neighbour added later that
# gates the same pages needs one more name in the list.
#
# The guard is what keeps that honest. On a host where the permission is not
# registered -- which is the host CI runs, this plugin alone -- this does
# nothing at all, so it cannot quietly widen what any example is granted.
module HostPluginPermissionHelpers
  ISSUE_PAGE_PERMISSIONS = %i[view_issue_description].freeze

  def grant_host_issue_page_permissions(role)
    demanded = ISSUE_PAGE_PERMISSIONS.select { |name| Redmine::AccessControl.permission(name) }
    role.add_permission!(*demanded) if demanded.any?
  end
end

RSpec.configure do |config|
  config.include ProjectWorkflowScopeHelpers
  config.include WorkflowStatementOrderHelpers
  config.include HostPluginPermissionHelpers

  fixtures_dir = File.expand_path('../../../test/fixtures', __dir__)

  # rspec-rails older versions (Redmine 5.1 setups)
  if config.respond_to?(:fixture_path=)
    config.fixture_path = fixtures_dir
    # rspec-rails newer versions (Redmine 6 setups)
  elsif config.respond_to?(:fixture_paths=)
    config.fixture_paths = [fixtures_dir]
  end

  # keep compatibility across rspec-rails versions
  config.use_transactional_fixtures = true if config.respond_to?(:use_transactional_fixtures=)

  config.before(:suite) do
    WorkflowTransition.delete_all
    WorkflowPermission.delete_all
    WorkflowRule.delete_all if defined?(WorkflowRule)
    ProjectWorkflowScope.delete_all if defined?(ProjectWorkflowScope)
  end

  # Rails resets CurrentAttributes around a request through the executor, which
  # does not wrap an example. Without this an example would see the previous
  # example's cached data.
  config.before do
    RedmineProjectWorkflows::Current.reset if defined?(RedmineProjectWorkflows::Current)
  end
end
