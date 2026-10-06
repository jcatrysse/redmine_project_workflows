# frozen_string_literal: true

#
# Migration 006, which carries an administrator's existing grants across the
# 2026-08-28 permission rename (finding F01 of
# docs/review/findings/2026-08-28-claude-plugin-compat-5.1.md).
#
# Exercised as a class rather than through `rake redmine:plugins:migrate`,
# because what is worth testing is what it does to `roles.permissions` -- a
# serialized array of symbols -- and not that Rails can run a migration. The
# up -> 0 -> up gate in dev/check-backfill.sh covers the other half.
#
require_relative '../spec_helper'
require_relative '../../db/migrate/006_rename_project_workflow_permissions'

describe RenameProjectWorkflowPermissions do
  fixtures :roles

  subject(:migration) { described_class.new }

  let(:legacy_names) { %i[view_project_workflow manage_project_workflow] }
  let(:role) { roles(:roles_001) }
  let(:unrelated) { %i[view_issues edit_issues] }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  # Every example below is about one of the migration's two worlds -- a legacy
  # name nothing else claims, or one a neighbour still claims -- so each
  # arranges the world it is about rather than inheriting whichever the host
  # happens to be. Without this the first group passes on a plain Redmine and
  # fails on one carrying redmine_custom_workflows, which is a spec that reports
  # the host rather than the code.
  before do
    unclaimed = Redmine::AccessControl.permissions
                                      .reject { |permission| legacy_names.include?(permission.name) }
    allow(Redmine::AccessControl).to receive(:permissions).and_return(unclaimed)
  end

  def grant(*permissions)
    role.permissions = permissions
    role.save!
    role
  end

  it 'renames both permissions and leaves everything else on the role alone' do
    grant(*unrelated, :view_project_workflow, :manage_project_workflow)

    migration.up

    expect(role.reload.permissions)
      .to match_array(unrelated + %i[view_project_workflow_rules manage_project_workflow_rules])
  end

  # The half that matters most: an administrator who gave a role the right to
  # read its project's workflow but not to change it must not come out of the
  # rename able to change it.
  it 'does not turn a viewing grant into a managing one' do
    grant(*unrelated, :view_project_workflow)

    migration.up

    expect(role.reload.permissions).to include(:view_project_workflow_rules)
    expect(role.permissions).not_to include(:manage_project_workflow_rules)
  end

  it 'leaves a role that never held either of them untouched' do
    grant(*unrelated)

    expect { migration.up }.not_to(change { role.reload.permissions })
  end

  # INV-8. The schema half is nothing -- this migration touches no column -- so
  # reversibility here means the data comes back as it was.
  it 'puts the old names back on the way down' do
    original = unrelated + %i[view_project_workflow manage_project_workflow]
    grant(*original)

    migration.up
    migration.down

    expect(role.reload.permissions).to match_array(original)
  end

  # The loop runs over every role, builtin ones included, and must leave the
  # ones it is not about exactly as they were.
  it 'touches only the roles that hold a legacy name' do
    other = roles(:roles_002)
    other.permissions = unrelated
    other.save!
    grant(*unrelated, :view_project_workflow)

    migration.up

    expect(role.reload.permissions).to include(:view_project_workflow_rules)
    expect(other.reload.permissions).to match_array(unrelated)
  end

  it 'is safe to run twice' do
    grant(*unrelated, :view_project_workflow, :manage_project_workflow)

    migration.up
    expect { migration.up }.not_to(change { role.reload.permissions })
  end

  # The case the migration exists to be careful about. On an installation
  # carrying `redmine_custom_workflows`, a role's `:manage_project_workflow` may
  # be that plugin's grant rather than this one's, and there is nothing in the
  # stored symbol to tell them apart. Renaming it would take the neighbour's
  # permission away; the migration leaves it where it is and says so.
  context 'when another plugin still registers the legacy name' do
    let(:neighbour) do
      Redmine::AccessControl::Permission.new(:manage_project_workflow, {}, {})
    end

    # On top of the outer stub, so this is "everything else, plus a neighbour
    # claiming the legacy manage name" on every host.
    before do
      allow(Redmine::AccessControl).to receive(:permissions)
        .and_return(Redmine::AccessControl.permissions + [neighbour])
    end

    it 'leaves the ambiguous grant alone' do
      grant(*unrelated, :view_project_workflow, :manage_project_workflow)

      migration.up

      expect(role.reload.permissions).to include(:manage_project_workflow)
      expect(role.permissions).not_to include(:manage_project_workflow_rules)
    end

    # The other name is not ambiguous, so it still moves. One collision does not
    # strand the pair.
    it 'still renames the permission nothing else claims' do
      grant(*unrelated, :view_project_workflow, :manage_project_workflow)

      migration.up

      expect(role.reload.permissions).to include(:view_project_workflow_rules)
      expect(role.permissions).not_to include(:view_project_workflow)
    end
  end
end
