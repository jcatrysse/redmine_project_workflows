# frozen_string_literal: true

require_relative '../spec_helper'

# WP11 / ADR-002. What the diagnostics page reports, asked of the service rather
# than of the rendered page, so that a failure names the fact rather than the
# markup. spec/controllers/project_workflow_diagnostics_controller_spec.rb is
# the other half: authorization, and that the page renders what is here.
describe RedmineProjectWorkflows::Services::Diagnostics do
  subject(:diagnostics) { described_class.new }

  describe 'the patch table' do
    # The discovery guard. ATTACHMENTS is a hand-kept list, and a hand-kept list
    # of thirteen is wrong on its first edit -- so this fails if a module is
    # added under Patches without an entry, which is the property that keeps the
    # page from silently reporting on twelve of fourteen patches.
    it 'names every module the plugin defines under Patches' do
      defined_patches = RedmineProjectWorkflows::Patches.constants.map(&:to_s).sort

      expect(described_class::ATTACHMENTS.map(&:first).sort).to eq(defined_patches)
    end

    it 'finds every one of them attached on this host' do
      expect(diagnostics.patch_checks.reject(&:ok)).to be_empty
    end

    # And the mirror image, so that "all attached" is a measurement rather than
    # a list of trues: a patch that is not attached is reported as not attached.
    # The module is real and is genuinely nowhere in Issue's ancestors.
    it 'reports a patch that is not attached' do
      stub_const("#{described_class}::ATTACHMENTS",
                 [['IssuePatch', :prepend, %w[Tracker]]])

      expect(diagnostics.patch_checks.map(&:ok)).to eq([false])
    end

    it 'reports a patch whose module no longer exists as not attached' do
      stub_const("#{described_class}::ATTACHMENTS", [['NoSuchPatch', :prepend, %w[Issue]]])

      expect(diagnostics.patch_checks.map(&:ok)).to eq([false])
    end
  end

  describe 'the permissions' do
    # Found by their actions, never by their names -- the failure this looks for
    # is a name that resolves to somebody else's registration, and a search by
    # name would find the impostor and report it as ours.
    it 'finds the two this plugin registers' do
      expect(diagnostics.registered_permissions.map(&:name))
        .to contain_exactly(:view_project_workflow_rules, :manage_project_workflow_rules)
    end

    it 'reports both as ours on a host where nothing else claims them' do
      expect(diagnostics.permission_checks.reject(&:ok)).to be_empty
      expect(diagnostics.permission_checks.map(&:claimants).uniq).to eq([1])
    end

    # Finding F01 of 2026-08-28-claude-plugin-compat-5.1, reproduced: a
    # neighbour registering the same name earlier wins, silently, and every
    # screen of this plugin then answers 403 to everybody. This is the shape
    # `redmine_custom_workflows` had -- the same name with an empty action hash.
    #
    # The registration is removed again in an `after`, because
    # Redmine::AccessControl's array is process-wide and a leak would break
    # every later example that asks about a permission.
    context 'when a neighbouring plugin has claimed one of the names' do
      let(:impostor) do
        Redmine::AccessControl::Permission.new(:view_project_workflow_rules, {}, {})
      end

      before { Redmine::AccessControl.permissions.unshift(impostor) }

      after { Redmine::AccessControl.permissions.delete(impostor) }

      it 'says so, and says how many plugins claim the name' do
        captured = diagnostics.permission_checks.find { |check| check.name == 'view_project_workflow_rules' }

        expect(captured.ok).to be(false)
        expect(captured.claimants).to eq(2)
      end

      it 'leaves the permission nobody else claims alone' do
        other = diagnostics.permission_checks.find { |check| check.name == 'manage_project_workflow_rules' }

        expect(other.ok).to be(true)
      end

      it 'is not ok overall' do
        expect(diagnostics.ok?).to be(false)
      end
    end
  end

  describe 'the Deface overrides' do
    # INV-9 counts five, in three files. This asserts the number the page lists
    # agrees with the number the plugin's own override files declare -- read from
    # disk, so the two cannot drift -- rather than restating five, which would be
    # a fourth place to keep the count.
    it 'lists exactly the overrides the plugin declares in its own files' do
      declared = Dir.glob(File.expand_path('../../lib/redmine_project_workflows/overrides/*.rb', __dir__))
                    .sum { |file| File.read(file).scan(/name:\s*'(redmine_project_workflows_[a-z_]+)'/).size }

      expect(diagnostics.registered_overrides.size).to eq(declared)
    end

    it 'names the view each one is registered against' do
      names, paths = diagnostics.registered_overrides.transpose

      expect(names).to all(start_with(described_class::OVERRIDE_PREFIX))
      expect(paths).to include('workflows/_action_menu', 'workflows/_form', 'issues/_attributes')
    end
  end

  describe 'the overall answer' do
    it 'is ok on a verified host with everything in place' do
      expect(diagnostics.state).to eq(:verified)
      expect(diagnostics.ok?).to be(true)
    end

    it 'names the database this host is configured with' do
      expect(diagnostics.database).to eq(ActiveRecord::Base.connection_db_config.adapter)
      expect(diagnostics.database).not_to be_blank
    end
  end
end
