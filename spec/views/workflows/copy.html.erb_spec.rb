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

  # Finding C01, answered B by Jan on 2026-08-26. A multiple select with nothing
  # selected submits no parameter at all, so a form that showed nothing in the
  # target project control still copied into the generic workflow -- and said so
  # nowhere. The generic workflow is preselected there now, so what runs is what
  # the form shows.
  describe 'the target project control' do
    # Which values a control has selected, read off the markup rather than
    # matched against it: Rails writes `selected` before `value` in one helper
    # and after it in the other, so an assertion naming both in one string
    # passes or fails on which helper drew the option.
    def selected_in(selector_id)
      select = rendered[%r{<select[^>]*id="#{selector_id}".*?</select>}m].to_s
      select.scan(/<option[^>]*>/)
            .select { |option| option.include?('selected') }
            .map { |option| option[/value="([^"]*)"/, 1] }
    end

    it 'preselects the generic workflow when nothing is selected' do
      render

      expect(selected_in('project_id_target')).to eq(['global'])
    end

    it 'leaves the source control alone' do
      render

      # Blank there already means the generic workflow and destroys nothing, and
      # the source tracker and role beside it are blank-by-default too -- that is
      # core's own convention for "not chosen yet".
      expect(selected_in('project_id_source')).to eq([''])
    end

    it 'keeps a submitted selection instead of adding the generic workflow to it' do
      controller.params[:target_project_ids] = [projects(:projects_001).id.to_s]

      render

      expect(selected_in('project_id_target')).to eq([projects(:projects_001).id.to_s])
    end
  end
end
