# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::TransitionWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:other_status) { issue_statuses(:issue_statuses_003) }

  it 'stores a single author/assignee row when both are enabled' do
    transitions = {
      status.id.to_s => {
        new_status.id.to_s => {
          'always' => '0',
          'author' => '1',
          'assignee' => '1'
        }
      }
    }

    described_class.replace_transitions(project, [tracker], [role], transitions)

    rows = WorkflowTransition.where(project_id: project.id)
    expect(rows.count).to eq(1)
    expect(rows.first).to have_attributes(author: true, assignee: true)
  end

  it 'stores separate always and author rows when both are enabled' do
    transitions = {
      status.id.to_s => {
        new_status.id.to_s => {
          'always' => '1',
          'author' => '1',
          'assignee' => '0'
        }
      }
    }

    described_class.replace_transitions(project, [tracker], [role], transitions)

    rows = WorkflowTransition.where(project_id: project.id).order(:author, :assignee)
    expect(rows.count).to eq(2)
    expect(rows.map { |row| [row.author, row.assignee] }).to contain_exactly([false, false], [true, false])
  end

  it 'replaces transitions only for the provided status/new status pairs' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: other_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    transitions = {
      status.id.to_s => {
        new_status.id.to_s => {
          'always' => '1',
          'author' => '0',
          'assignee' => '0'
        }
      }
    }

    described_class.replace_transitions(project, [tracker], [role], transitions)

    expect(
      WorkflowTransition.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: other_status.id,
        new_status_id: new_status.id,
        project_id: project.id
      )
    ).to exist
  end
end
