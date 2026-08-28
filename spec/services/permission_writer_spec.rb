# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::PermissionWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:other_status) { issue_statuses(:issue_statuses_002) }

  # See TransitionWriter's spec: a project write goes into a scope that already
  # exists and never creates one (INV-3), so every example that writes into a
  # project arranges the decision first.
  before { give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS) }

  it 'replaces permissions for selected fields without deleting unrelated rules' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'priority_id',
      rule: 'required',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => {
        'subject' => 'required'
      }
    }

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'priority_id',
        project_id: project.id
      )
    ).to exist
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'required')
  end

  it 'keeps permissions for other statuses intact' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: other_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => {
        'subject' => 'required'
      }
    }

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: other_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to exist
  end

  it 'accepts action controller parameters when replacing permissions' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = ActionController::Parameters.new(
      status.id.to_s => {
        'subject' => 'required'
      }
    )

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'required')
  end

  it 'skips deleting permissions when no fields are provided for a status' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => {}
    }

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to exist
  end

  it 'does not raise when permissions are nil' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    expect do
      described_class.replace_permissions(project, [tracker], [role], nil)
    end.not_to raise_error

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to exist
  end

  # WP0 / external F05. These were characterization examples: the writer used
  # to accept whatever the request contained, because insert_all runs no
  # validations and the plugin routes core's own generic write path through
  # this writer as well. INV-2: the whitelist is the validation.

  # Finding F04 of 2026-08-28-claude-audit. `MatrixParams#to_plain_hash` and
  # `WorkflowsControllerPatch#to_plain_hash` were both corrected to ask what a
  # payload **is** rather than what it answers to, because `Array` answers
  # `respond_to?(:to_h)` yes and then raises `TypeError`. These two writers were
  # the copies that did not move.
  #
  # Not reachable from either screen -- both controllers convert first -- but
  # INV-1 routes core's own `replace_permissions` through here, so a neighbouring
  # plugin, a rake task or a console reaches it. A validator that raises has not
  # rejected.
  describe 'a payload that is not a matrix at all' do
    # Red on the old code: TypeError, "wrong element type String at 0
    # (expected array)".
    it 'rejects an array rather than raising' do
      result = nil
      expect { result = described_class.replace_permissions(project, [tracker], [role], ['x']) }.not_to raise_error
      expect(result.written).to eq(0)
      expect(result.skipped).to eq(0)
      expect(result.rejected).to eq(0)
    end

    # Red on the old code in a different way: a String answered `respond_to?(:to_h)`
    # false and fell through untouched, so the whitelist raised NoMethodError on
    # it one method later.
    it 'rejects a string rather than raising' do
      result = nil
      expect { result = described_class.replace_permissions(project, [tracker], [role], 'x') }.not_to raise_error
      expect(result.written).to eq(0)
    end

    it 'rejects a scalar rather than raising' do
      result = nil
      expect { result = described_class.replace_permissions(project, [tracker], [role], 7) }.not_to raise_error
      expect(result.written).to eq(0)
    end

    it 'writes nothing for any of them' do
      described_class.replace_permissions(project, [tracker], [role], ['x'])
      described_class.replace_permissions(project, [tracker], [role], 'x')
      expect(WorkflowPermission.count).to eq(0)
    end
  end

  describe 'server-side validation' do
    let(:custom_field) do
      IssueCustomField.create!(name: 'Workflow writer spec field', field_format: 'string')
    end

    it 'rejects a rule value that core validation rejects' do
      expect do
        WorkflowPermission.create!(
          tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
          field_name: 'due_date', rule: 'bogus'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      WorkflowPermission.replace_permissions([tracker], [role],
                                             { status.id.to_s => { 'due_date' => 'bogus' } })

      expect(WorkflowPermission.where(project_id: nil, field_name: 'due_date')).not_to exist
    end

    it 'rejects a field name that does not exist' do
      WorkflowPermission.replace_permissions([tracker], [role],
                                             { status.id.to_s => { 'niet_bestaand_veld' => 'readonly' } })

      expect(WorkflowPermission.pluck(:field_name)).not_to include('niet_bestaand_veld')
    end

    it 'rejects a custom field id that does not exist' do
      described_class.replace_permissions(project, [tracker], [role],
                                          { status.id.to_s => { '999999' => 'readonly' } })

      expect(WorkflowPermission.pluck(:field_name)).not_to include('999999')
    end

    it 'accepts a custom field id that does exist' do
      described_class.replace_permissions(project, [tracker], [role],
                                          { status.id.to_s => { custom_field.id.to_s => 'readonly' } })

      expect(
        WorkflowPermission.where(project_id: project.id, field_name: custom_field.id.to_s)
      ).to exist
    end

    it 'rejects a status id that does not exist' do
      described_class.replace_permissions(project, [tracker], [role],
                                          { '999999' => { 'subject' => 'readonly' } })

      expect(WorkflowPermission.where(old_status_id: 999_999)).not_to exist
    end

    # A rejected value is dropped before the delete, not only before the
    # insert: an unacceptable rule must change nothing, not clear the rule it
    # names.
    it 'leaves the stored rule alone when an invalid rule arrives for it' do
      WorkflowPermission.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        field_name: 'subject', rule: 'readonly', project_id: project.id
      )

      described_class.replace_permissions(project, [tracker], [role],
                                          { status.id.to_s => { 'subject' => 'bogus' } })

      expect(
        WorkflowPermission.find_by(project_id: project.id, old_status_id: status.id,
                                   field_name: 'subject')&.rule
      ).to eq('readonly')
    end

    it 'still removes a rule when the request clears it' do
      WorkflowPermission.create!(
        tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
        field_name: 'subject', rule: 'readonly', project_id: project.id
      )

      described_class.replace_permissions(project, [tracker], [role],
                                          { status.id.to_s => { 'subject' => '' } })

      expect(
        WorkflowPermission.where(project_id: project.id, old_status_id: status.id,
                                 field_name: 'subject')
      ).not_to exist
    end
  end

  # WP1, amended by this session: see the transitions writer -- a project write
  # records that the rules changed and never creates the decision itself.
  describe 'the scope a project write records' do
    let(:inheriting_role) { roles(:roles_002) }

    it 'leaves the transitions scope alone, which is a decision of its own' do
      described_class.replace_permissions_for_project_id(
        project.id, [tracker], [role], { status.id.to_s => { 'due_date' => 'required' } }
      )

      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)).to be(false)
    end

    it 'writes nothing for a combination that still inherits, and says how many' do
      result = described_class.replace_permissions_for_project_id(
        project.id, [tracker], [inheriting_role], { status.id.to_s => { 'due_date' => 'required' } }
      )

      expect(result.skipped).to eq(1)
      expect(result.written).to eq(0)
      expect(WorkflowPermission.where(project_id: project.id, role_id: inheriting_role.id)).to be_empty
      expect(own_workflow?(project, tracker, inheriting_role, ProjectWorkflowScope::PERMISSIONS)).to be(false)
    end

    it 'creates none for a generic write' do
      expect do
        described_class.replace_permissions_for_project_id(
          nil, [tracker], [role], { status.id.to_s => { 'due_date' => 'required' } }
        )
      end.not_to change(ProjectWorkflowScope, :count)
    end

    it 'survives a save that clears every rule' do
      described_class.replace_permissions_for_project_id(
        project.id, [tracker], [role], { status.id.to_s => { 'due_date' => 'required' } }
      )
      described_class.replace_permissions_for_project_id(
        project.id, [tracker], [role], { status.id.to_s => { 'due_date' => '' } }
      )

      expect(WorkflowPermission.where(project_id: project.id)).to be_empty
      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
    end
  end
end
