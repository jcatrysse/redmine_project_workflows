# frozen_string_literal: true

require_relative '../spec_helper'

# WP13, audit finding F08. How much one administration save is allowed to
# rewrite, and where the two numbers come from.
#
# The projection is arithmetic and the settings are strings an administrator
# typed, so this is where the two meet: what a save is counted as, and what
# happens to a value Redmine stored without validating it.
describe RedmineProjectWorkflows::Services::WriteBudget do
  after { Setting.clear_cache }

  describe '.projected_rules' do
    # Every cell, once per workflow the selection covers -- the same unit the row
    # and column actions of WP5 already ask about.
    it 'is cells x trackers x roles x scopes' do
      expect(described_class.projected_rules(scopes: 5, trackers: 3, roles: 3, cells: 36)).to eq(1620)
    end

    # The measured case from the finding, which is what the default ceiling was
    # chosen against: one project, three trackers, three roles, a six-status
    # matrix.
    it 'is 324 for one project of the measured shape' do
      expect(described_class.projected_rules(scopes: 1, trackers: 3, roles: 3, cells: 36)).to eq(324)
    end

    it 'is nothing when the selection is empty' do
      expect(described_class.projected_rules(scopes: 0, trackers: 3, roles: 3, cells: 36)).to eq(0)
    end
  end

  describe '.ceiling' do
    it 'is the declared default when nothing has been saved' do
      Setting.plugin_redmine_project_workflows = {}

      expect(described_class.ceiling).to eq(described_class::DEFAULT_WRITE_CEILING)
    end

    it 'is what an administrator saved' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '1000' }

      expect(described_class.ceiling).to eq(1000)
    end

    # Redmine assigns the plugin settings hash exactly as it arrives, with no
    # validation hook, so a value that is not a run of digits reaches this.
    it 'falls back to the default for a value that is not a whole number' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => 'lots' }

      expect(described_class.ceiling).to eq(described_class::DEFAULT_WRITE_CEILING)
    end
  end

  # Its own setting since 2026-08-29, and a much larger default: sharing
  # `bulk_confirm_threshold` fired the Save dialog on essentially every
  # multi-workflow save, because two workflows of a six-status matrix is already
  # 216 rules.
  describe '.save_confirm_threshold' do
    it 'is the declared default when nothing has been saved' do
      Setting.plugin_redmine_project_workflows = {}

      expect(described_class.save_confirm_threshold)
        .to eq(described_class::DEFAULT_SAVE_CONFIRM_THRESHOLD)
    end

    it 'is what an administrator saved' do
      Setting.plugin_redmine_project_workflows = { 'bulk_save_confirm_threshold' => '250' }

      expect(described_class.save_confirm_threshold).to eq(250)
    end

    it 'is not the row and column actions\' threshold' do
      Setting.plugin_redmine_project_workflows = { 'bulk_confirm_threshold' => '7' }

      expect(described_class.save_confirm_threshold)
        .to eq(described_class::DEFAULT_SAVE_CONFIRM_THRESHOLD)
    end

    # A Save that would rewrite 216 rules -- two workflows of a six-status
    # matrix -- is the case that made the shared threshold useless.
    it 'lets the ordinary multi-workflow save through without asking' do
      Setting.plugin_redmine_project_workflows = {}

      expect(described_class.save_confirm_threshold).to be > 216
    end
  end

  describe '.over_ceiling?' do
    before { Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '100' } }

    it 'is false at the ceiling exactly' do
      expect(described_class.over_ceiling?(100)).to be(false)
    end

    it 'is true one above it' do
      expect(described_class.over_ceiling?(101)).to be(true)
    end

    # 0 is the escape hatch: an installation that has measured its own database
    # and wants the whole selection in one go.
    it 'is false for every size when the ceiling is 0' do
      Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '0' }

      expect(described_class.over_ceiling?(10_000_000)).to be(false)
    end
  end
end
