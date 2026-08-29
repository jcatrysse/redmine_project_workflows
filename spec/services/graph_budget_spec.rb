# frozen_string_literal: true

require_relative '../spec_helper'

# WP14. The drawing is a feature an installation can turn off, and one it will
# not spend a second and a half of a request on.
describe RedmineProjectWorkflows::Services::GraphBudget do
  after { Setting.clear_cache }

  describe 'the switch' do
    it 'is on where nothing has been saved' do
      Setting.plugin_redmine_project_workflows = {}

      expect(described_class).to be_enabled
    end

    it 'is on for a settings hash saved before the key existed' do
      Setting.plugin_redmine_project_workflows = { 'bulk_confirm_threshold' => '50' }

      expect(described_class).to be_enabled
    end

    it 'is off only for an explicit 0, which is what the checkbox submits' do
      Setting.plugin_redmine_project_workflows = { 'graph_enabled' => '0' }

      expect(described_class).not_to be_enabled
    end

    it 'is on for the 1 the checkbox submits when it is ticked' do
      Setting.plugin_redmine_project_workflows = { 'graph_enabled' => '1' }

      expect(described_class).to be_enabled
    end
  end

  describe 'the ceiling' do
    it 'falls back to the default where nothing has been saved' do
      Setting.plugin_redmine_project_workflows = {}

      expect(described_class.edge_ceiling).to eq(described_class::DEFAULT_EDGE_CEILING)
    end

    # Redmine assigns the plugin settings hash exactly as it arrives and offers
    # no validation hook, so the fallback here is what answers for anything the
    # number field did not stop.
    it 'falls back to the default for a value that is not a whole number' do
      Setting.plugin_redmine_project_workflows = { 'graph_edge_ceiling' => 'lots' }

      expect(described_class.edge_ceiling).to eq(described_class::DEFAULT_EDGE_CEILING)
    end

    it 'takes the number that was saved' do
      Setting.plugin_redmine_project_workflows = { 'graph_edge_ceiling' => '10' }

      expect(described_class.edge_ceiling).to eq(10)
      expect(described_class.over_ceiling?(11)).to be(true)
      expect(described_class.over_ceiling?(10)).to be(false)
    end

    it 'treats 0 as no ceiling at all' do
      Setting.plugin_redmine_project_workflows = { 'graph_edge_ceiling' => '0' }

      expect(described_class.over_ceiling?(1_000_000)).to be(false)
    end

    # The measurement the default comes from: the layout's cost follows the
    # arrows, and 2,000 of them is about seven tenths of a second.
    it 'draws an ordinary workflow with the default in force' do
      Setting.plugin_redmine_project_workflows = {}

      expect(described_class.over_ceiling?(25)).to be(false)
      expect(described_class.over_ceiling?(1_600)).to be(false)
      expect(described_class.over_ceiling?(3_600)).to be(true)
    end
  end
end
