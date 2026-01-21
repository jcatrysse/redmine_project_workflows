# frozen_string_literal: true

require_relative '../../spec_helper'

describe 'workflows/copy.html.erb', type: :view do
  fixtures :projects, :roles, :trackers

  before do
    assign(:roles, Role.sorted.select(&:consider_workflow?))
    assign(:trackers, Tracker.sorted)
    assign(:projects, Project.sorted)
    assign(:selected_projects, [])
    assign(:global_selected, true)
  end

  it 'renders project selectors for source and target sections' do
    render

    expect(rendered).to include('name="source_project_id"')
    expect(rendered).to include('name="target_project_ids[]"')
    expect(rendered).to include('id="project_id_source"')
    expect(rendered).to include('id="project_id_target"')
    expect(rendered).not_to include('toggle-multiselect')
    expect(rendered).to include("--- #{I18n.t(:label_copy_same_as_target)} ---")
    expect(rendered).to include('multiple="multiple"')
  end
end
