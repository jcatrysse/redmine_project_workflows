# frozen_string_literal: true

# The two permissions this plugin registers were renamed on 2026-08-28:
#
#   view_project_workflow    ->  view_project_workflow_rules
#   manage_project_workflow  ->  manage_project_workflow_rules
#
# Not cosmetic. `redmine_custom_workflows` registers a permission called
# `manage_project_workflow` with an empty action hash, `AccessControl` keeps a
# flat array and answers with the **first** registration, and plugins load in
# alphabetical directory order -- so on any Redmine carrying both plugins the
# neighbour won and every write action of this plugin answered 403, for
# administrators too. See finding F01 of
# `docs/review/findings/2026-08-28-claude-plugin-compat-5.1.md`; answered **B**
# by Jan, rename both so the pair stays symmetric.
#
# This migration carries the grants an administrator has already made across, so
# nobody has to re-tick a role. It touches `roles.permissions` -- a serialized
# array of symbols -- through the `Role` model rather than by hand, because the
# encoding is the model's: 5.1 declares `serialize :permissions,
# ::Role::PermissionsAttributeCoder` and 7.0 declares the same coder through the
# `coder:` keyword, and reproducing either here would be one more thing to keep
# in step with three Redmine series.
#
# Reversible (INV-8): `down` maps the names back. No column, table or index is
# involved either way, so `VERSION=0` still leaves the host stock.
class RenameProjectWorkflowPermissions < ActiveRecord::Migration[6.1]
  RENAMES = {
    view_project_workflow: :view_project_workflow_rules,
    manage_project_workflow: :manage_project_workflow_rules
  }.freeze

  def up
    RENAMES.each { |legacy, current| move(legacy, current) }
  end

  def down
    RENAMES.each { |legacy, current| move(current, legacy) }
  end

  private

  # The whole reason this migration is not a two-line `gsub` over a column.
  #
  # A role may hold `:manage_project_workflow` because of the **neighbour**, not
  # because of this plugin -- the collision is what the rename exists to end,
  # and on the installations where it bit, this plugin's write screens have
  # never worked, so there is nothing of ours in that grant to preserve.
  # Renaming it would quietly take the neighbour's permission away from that
  # role; adding ours beside it would quietly widen what the role may do. Both
  # are worse than leaving it alone and saying so.
  #
  # The test is not "is redmine_custom_workflows installed" but "does anything
  # else still claim this name", which is the question that actually decides
  # whether the stored symbol is ambiguous -- and which stays right if the
  # neighbour is renamed, removed, or replaced by some other plugin. By the time
  # a plugin migration runs, every plugin has registered.
  #
  # Known limit, stated rather than hidden: a legacy symbol left behind by a
  # plugin that has since been *uninstalled* reads as unambiguous here and will
  # be renamed. There is no way to tell that grant from one of ours, and the
  # alternative -- never migrating anything -- costs every installation its
  # role configuration to protect a case that leaves no trace.
  def claimed_elsewhere?(legacy)
    Redmine::AccessControl.permissions.any? { |permission| permission.name == legacy }
  end

  def move(from, to)
    legacy = RENAMES.key?(from) ? from : to
    if claimed_elsewhere?(legacy)
      say ambiguity_notice(legacy, going_up: legacy == from)
      return
    end

    Role.reset_column_information
    holders = Role.all.to_a.select { |role| holds?(role, from) }
    holders.each { |role| rename_on(role, from, to) }
    say "#{from} -> #{to} on #{holders.size} role(s)"
  end

  # The advice only makes sense on the way up; on a rollback there is nothing for
  # an administrator to grant.
  def ambiguity_notice(legacy, going_up:)
    notice = "another plugin still registers #{legacy}; leaving role grants of it alone."
    return notice unless going_up

    "#{notice} Grant #{RENAMES[legacy]} to the roles that should have it."
  end

  def holds?(role, permission)
    role.permissions.is_a?(Array) && role.permissions.include?(permission)
  end

  def rename_on(role, from, to)
    # A fresh array, not a mutation: `Role#permissions=` writes the attribute,
    # and only a write marks it dirty. `add_permission!` calls
    # `permissions_will_change!` precisely because it mutates in place.
    role.permissions = role.permissions - [from] + [to]
    # Roles written years ago by other plugins are not this migration's to
    # validate, and a validation this plugin does not own must not be able to
    # stop a rename half way through.
    role.save(validate: false)
  end
end
