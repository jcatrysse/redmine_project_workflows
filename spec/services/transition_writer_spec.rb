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

  # WP0 / external F05. insert_all runs no validations, so the whitelist in
  # the writer is the validation -- including core's
  # validates_presence_of :new_status, which the plugin's routing of
  # WorkflowTransition.replace_transitions had removed from the generic write
  # path too. INV-2.
  describe 'server-side validation' do
    it 'rejects a new status id that does not exist' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { '999999' => { 'always' => '1' } } })

      expect(WorkflowTransition.where(new_status_id: 999_999)).not_to exist
    end

    it 'rejects an old status id that does not exist' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { '999999' => { new_status.id.to_s => { 'always' => '1' } } })

      expect(WorkflowTransition.where(old_status_id: 999_999)).not_to exist
    end

    # 0 is not an IssueStatus: it is how core stores a transition out of the
    # "new issue" pseudo status, and it has to keep working.
    it 'accepts the new-issue pseudo status' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { '0' => { new_status.id.to_s => { 'always' => '1' } } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: 0,
                                 new_status_id: new_status.id)
      ).to exist
    end

    it 'rejects a rule name the matrix cannot produce' do
      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => { 'nobody' => '1' } } })

      expect(WorkflowTransition.where(project_id: project.id)).not_to exist
    end

    # A rejected value is dropped before the delete, not only before the
    # insert, so an unacceptable cell value cannot remove a transition.
    it 'leaves the stored transition alone when an unknown cell value arrives' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: false, assignee: false
      )

      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => { 'always' => 'bogus' } } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                                 new_status_id: new_status.id)
      ).to exist
    end

    # The controller strips 'no_change' before it reaches the writer, so a cell
    # the administrator left alone arrives as an empty rule hash. That used to
    # still contribute to the delete and then insert nothing, which turned
    # "leave this as it is" into "remove it".
    it 'leaves a transition alone when every rule for the cell says no change' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: false, assignee: false
      )

      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => {} } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                                 new_status_id: new_status.id)
      ).to exist
    end

    it 'still removes a transition when the request clears it' do
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        new_status_id: new_status.id, project_id: project.id, author: false, assignee: false
      )

      described_class.replace_transitions(project, [tracker], [role],
                                          { status.id.to_s => { new_status.id.to_s => { 'always' => '0' } } })

      expect(
        WorkflowTransition.where(project_id: project.id, old_status_id: status.id,
                                 new_status_id: new_status.id)
      ).not_to exist
    end
  end

  # WP1: a project write records the decision along with the rules (INV-3), and
  # a generic write has no decision to record.
  describe 'the scope a project write records' do
    it 'creates one for each tracker and role it wrote' do
      described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )

      expect(own_workflow?(project, tracker, role)).to be(true)
    end

    it 'creates none for a generic write' do
      described_class.replace_transitions_for_project_id(
        nil, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )

      expect(ProjectWorkflowScope.count).to eq(0)
    end

    # INV-3 again: clearing the last rule is not the same as returning the
    # project to the generic workflow, so the scope stays.
    it 'survives a save that removes every rule' do
      described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )
      described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'always' => '0' } } }
      )

      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(own_workflow?(project, tracker, role)).to be(true)
    end

    it 'creates none when the whole submission was rejected' do
      described_class.replace_transitions_for_project_id(
        project.id, [tracker], [role],
        { status.id.to_s => { new_status.id.to_s => { 'sometimes' => '1' } } }
      )

      expect(ProjectWorkflowScope.count).to eq(0)
    end
  end
end
