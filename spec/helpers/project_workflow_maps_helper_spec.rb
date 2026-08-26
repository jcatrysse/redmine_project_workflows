# frozen_string_literal: true

require_relative '../spec_helper'

# WP8. The two decisions the panel's helper makes that are easier to pin down
# here than through a rendered page: which words one move's condition gets, and
# whether a link into the workflow is offered at all.
describe ProjectWorkflowMapsHelper, type: :helper do
  fixtures :projects, :roles, :trackers, :users, :members, :member_roles,
           :enabled_modules, :projects_trackers

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }

  after { User.current = nil }

  describe 'what a move requires' do
    it 'names the unconditional case in the words every other screen uses' do
      expect(helper.project_workflow_map_conditions_label(['always']))
        .to eq(I18n.t(:label_project_workflow_condition_always))
    end

    # Not the comparison screen's "Also when the user is the author": there it
    # names a whole grid, here the conditions of one move have been collapsed, so
    # a move naming only the author grid is a move only the author may make.
    it 'says only, not also, for a move one identity gates' do
      expect(helper.project_workflow_map_conditions_label(['author']))
        .to eq(I18n.t(:label_project_workflow_map_condition_author))
      expect(helper.project_workflow_map_conditions_label(['assignee']))
        .to eq(I18n.t(:label_project_workflow_map_condition_assignee))
    end

    # One phrase rather than two joined by a comma: "only the author" beside
    # "only the assignee" reads as a contradiction.
    it 'joins both identities into one phrase' do
      expect(helper.project_workflow_map_conditions_label(%w[author assignee]))
        .to eq(I18n.t(:label_project_workflow_map_condition_author_or_assignee))
    end

    it 'lets the unconditional case win over a conditional one' do
      expect(helper.project_workflow_map_conditions_label(%w[always author]))
        .to eq(I18n.t(:label_project_workflow_condition_always))
    end
  end

  # A link that answers 403 is worse than none, which is why the last case exists.
  describe 'where this workflow is changed' do
    it 'offers nothing to somebody who may open neither screen' do
      User.current = users(:users_002)

      expect(helper.project_workflow_map_edit_link(project, tracker, role, :own)).to be_nil
    end

    it 'offers the project tab to somebody who may open it' do
      role.add_permission!(:view_project_workflow)
      User.current = users(:users_002)

      link = helper.project_workflow_map_edit_link(project, tracker, role, :own)

      expect(link).to include(ERB::Util.html_escape(
                                project_workflow_transitions_path(project, tracker_id: tracker.id,
                                                                           role_id: role.id)
                              ))
    end

    # A combination the project inherits is governed by the *generic* workflow,
    # so an administrator is sent to the screen that changes it.
    it 'sends an administrator to the generic matrix while the project inherits' do
      User.current = users(:users_001)

      link = helper.project_workflow_map_edit_link(project, tracker, role, :inherits)

      expect(link).to include('/workflows/edit')
      expect(link).to include("project_id%5B%5D=#{project.id}")
    end

    # Once the project answers for itself the generic workflow is not what
    # governs, so even an administrator goes to the project's own tab.
    it 'sends an administrator to the project tab once the project answers for itself' do
      User.current = users(:users_001)

      link = helper.project_workflow_map_edit_link(project, tracker, role, :own)

      expect(link).to include(ERB::Util.html_escape(
                                project_workflow_transitions_path(project, tracker_id: tracker.id,
                                                                           role_id: role.id)
                              ))
    end
  end

  describe 'the link on the issue form' do
    it 'carries the project and the tracker for an unsaved issue' do
      issue = Issue.new(project: project, tracker: tracker)

      expect(helper.project_workflow_map_link(issue))
        .to include(ERB::Util.html_escape(project_workflow_map_path(project, tracker_id: tracker.id)))
    end

    # Nothing to describe, so nothing rendered: the global new-issue form before
    # a project has been chosen.
    it 'renders nothing without a project' do
      expect(helper.project_workflow_map_link(Issue.new(tracker: tracker))).to be_nil
    end

    it 'renders nothing without a tracker' do
      expect(helper.project_workflow_map_link(Issue.new(project: project, tracker: nil))).to be_nil
    end
  end
end
