# frozen_string_literal: true

require_relative '../spec_helper'

# The plugin's own matrix cell helpers. They live in `ProjectWorkflowMatrixHelper`
# and are attached to the helper chains of the three controllers that render a
# matrix -- never to `WorkflowsHelper` itself, for the reason
# `Patches::WorkflowsControllerHelperPatch` gives at length (finding F01 of
# 2026-08-28-claude-audit).
#
# A helper spec has no controller, so the layering is reproduced on the helper
# object: the module ahead of `WorkflowsHelper`, which is exactly the position
# `controller.helper` produces. Two of these methods reimplement a body core
# owns, so `spec/upstream/core_drift_spec.rb` watches core's originals; this file
# is about what the plugin's versions do.
describe ProjectWorkflowMatrixHelper, type: :helper do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:field_name) { 'subject' }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  before do
    # The real layering, on the helper object: core's WorkflowsHelper -- which
    # `helper :workflows` puts in every one of the three controllers' chains --
    # with the plugin's module ahead of it. #field_permission_tag calls core's
    # own `field_required?`, so leaving WorkflowsHelper out makes this file
    # assert against a chain no screen ever has.
    helper.singleton_class.include(WorkflowsHelper)
    helper.singleton_class.prepend(described_class)
    helper.instance_variable_set(:@roles, [role])
    helper.instance_variable_set(:@trackers, [tracker])
    helper.instance_variable_set(:@projects_for_update, [project, other_project])
  end

  it 'treats full project coverage as a checked transition' do
    html = helper.transition_tag(2, status, new_status, 'always')

    expect(html).to include('type="checkbox"')
  end

  it 'uses no-change when not all projects share the same permission' do
    permissions = {
      status.id => {
        field_name => ['readonly']
      }
    }

    html = helper.field_permission_tag(permissions, status, field_name, [role])

    expect(html).to include('no_change')
  end

  it 'treats full project and global coverage as a checked transition' do
    helper.instance_variable_set(:@global_selected, true)

    html = helper.transition_tag(3, status, new_status, 'always')

    expect(html).to include('type="checkbox"')
  end

  # WP1. Three states have to stay tellable apart (INV-3), and a mixed selection
  # names only the states it actually contains -- a zero count is noise.
  describe '#project_workflow_scope_state_tag' do
    def state_for(projects)
      RedmineProjectWorkflows::Services::ScopeState.new(
        project_ids: projects, tracker_ids: [tracker], role_ids: [role],
        rule_type: ProjectWorkflowScope::TRANSITIONS
      )
    end

    before do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
    end

    it 'names a uniform selection in words' do
      give_own_workflow(project, tracker, role)

      expect(helper.project_workflow_scope_state_tag(state_for([project])))
        .to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_own_empty)))
    end

    it 'leaves a zero count out of a mixed selection' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: status.id, new_status_id: new_status.id)
      give_own_workflow(other_project, tracker, role)

      html = helper.project_workflow_scope_state_tag(state_for([project, other_project]))

      expect(html).to include(I18n.t(:label_project_workflow_count_own, count: 1))
      expect(html).to include(I18n.t(:label_project_workflow_count_own_empty, count: 1))
      # Nothing in this selection inherits, so nothing says so.
      expect(html).not_to include(I18n.t(:label_project_workflow_count_inherits, count: 0))
    end
  end

  # WP5 / claude F06. Core puts a check-all toggle in every row and column
  # header of a transition grid, and it selects on input[type=checkbox] -- so it
  # never reached the cells a mixed selection renders as a <select>, which are
  # exactly the cells with the manual work in them. The classes make one
  # class-based selector reach both kinds of cell; the actions below are what
  # uses it.
  describe 'a cell the selection disagrees about' do
    it 'carries the same row and column classes as a checkbox cell' do
      html = helper.transition_tag(1, status, new_status, 'always')

      expect(html).to include('<select')
      expect(html).to include("old-status-#{status.id} new-status-#{new_status.id}")
    end

    it 'is a checkbox again once every workflow in the selection agrees' do
      html = helper.transition_tag(2, status, new_status, 'always')

      expect(html).to include('type="checkbox"')
      expect(html).to include("old-status-#{status.id} new-status-#{new_status.id}")
    end
  end

  # WP5. How much one cell stands for. Core counts roles times trackers; the
  # plugin adds the scopes the selection covers, and both cell helpers and the
  # row and column actions answer from the same method, so they cannot disagree
  # about whether a cell is mixed.
  describe '#project_workflow_selection_size' do
    it 'counts trackers, roles and the projects in the selection' do
      expect(helper.project_workflow_selection_size).to eq(2)
    end

    it 'counts the generic workflow as one more scope' do
      helper.instance_variable_set(:@global_selected, true)

      expect(helper.project_workflow_selection_size).to eq(3)
    end

    it 'is one for a selection that named no project at all' do
      helper.instance_variable_set(:@projects_for_update, [])
      helper.instance_variable_set(:@global_selected, true)

      expect(helper.project_workflow_selection_size).to eq(1)
    end

    # Not reachable from the screens -- the controller always sets both -- but a
    # zero here would make every empty cell look like a full one, so it answers
    # rather than raising.
    it 'survives a view that set neither list' do
      helper.instance_variable_set(:@roles, nil)
      helper.instance_variable_set(:@trackers, nil)
      helper.instance_variable_set(:@projects_for_update, nil)

      expect(helper.project_workflow_selection_size).to eq(0)
    end
  end

  describe '#project_workflow_bulk_actions' do
    it 'names the column it acts on, in that grid alone' do
      html = helper.project_workflow_bulk_actions('new', 'author', new_status.id, new_status.name)

      expect(html).to include("table.transitions-author .new-status-#{new_status.id}:not(:disabled)")
      expect(html).to include(ERB::Util.html_escape(I18n.t(:general_text_Yes)))
      expect(html).to include(ERB::Util.html_escape(I18n.t(:general_text_No)))
    end

    it 'names the row it acts on' do
      html = helper.project_workflow_bulk_actions('old', 'always', 0, 'New issue')

      expect(html).to include('table.transitions-always .old-status-0:not(:disabled)')
    end

    # Every action says what it does, in words, on the link itself: the visible
    # label is one word and the title is the whole sentence.
    it 'says what each action does' do
      html = helper.project_workflow_bulk_actions('old', 'always', status.id, status.name)

      expect(html).to include(ERB::Util.html_escape(
                                I18n.t(:label_project_workflow_bulk_row, name: status.name,
value: I18n.t(:general_text_Yes))
                              ))
      expect(html.scan('aria-label').size).to eq(html.scan('project-workflow-bulk-action').size)
    end

    it 'offers no change while a cell stands for more than one workflow' do
      html = helper.project_workflow_bulk_actions('new', 'always', new_status.id, new_status.name)

      expect(html).to include('data-project-workflow-value="no_change"')
      expect(html).to include('data-project-workflow-multiplier="2"')
    end

    # One workflow per cell is the project matrices' case, by construction. A
    # cell there cannot be mixed, so an action offering "no change" would name a
    # state the matrix can never be in.
    it 'leaves no change out when a cell is one workflow' do
      helper.instance_variable_set(:@projects_for_update, [project])

      html = helper.project_workflow_bulk_actions('new', 'always', new_status.id, new_status.name)

      # The function itself mentions no_change whatever the page does, so this
      # asks about the actions rather than about the whole answer.
      expect(html).not_to include('data-project-workflow-value="no_change"')
      expect(html).to include('data-project-workflow-multiplier="1"')
    end

    it 'writes the function once however many rows and columns ask for it' do
      html = (1..3).map { |i| helper.project_workflow_bulk_actions('new', 'always', i, "S#{i}") }.join

      expect(html.scan('function projectWorkflowBulkApply').size).to eq(1)
      expect(html.scan('project-workflow-bulk"').size).to eq(3)
    end
  end

  # WP5. The threshold above which a row or column action asks first. The
  # setting is a free-text field, and a settings hash saved before the key
  # existed does not carry it at all, so anything but a plain number falls back.
  describe '#project_workflow_bulk_confirm_threshold' do
    after { Setting.clear_cache }

    def with_setting(value)
      Setting.plugin_redmine_project_workflows = { 'bulk_confirm_threshold' => value }
    end

    it 'uses the number an administrator set' do
      with_setting('7')

      expect(helper.project_workflow_bulk_confirm_threshold).to eq(7)
    end

    it 'takes zero to mean ask every time' do
      with_setting('0')

      expect(helper.project_workflow_bulk_confirm_threshold).to eq(0)
    end

    it 'falls back when the field was cleared' do
      with_setting('')

      expect(helper.project_workflow_bulk_confirm_threshold)
        .to eq(RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD)
    end

    it 'falls back when the field holds something that is not a number' do
      with_setting('lots')

      expect(helper.project_workflow_bulk_confirm_threshold)
        .to eq(RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD)
    end

    it 'falls back for a settings hash saved before the key existed' do
      Setting.plugin_redmine_project_workflows = {}

      expect(helper.project_workflow_bulk_confirm_threshold)
        .to eq(RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD)
    end

    it 'reaches the action as the number the browser has to compare against' do
      with_setting('9')

      expect(helper.project_workflow_bulk_actions('new', 'always', new_status.id, new_status.name))
        .to include('data-project-workflow-threshold="9"')
    end
  end
end
