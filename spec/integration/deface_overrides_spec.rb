# frozen_string_literal: true

#
# Guards that every Deface override still matches its anchor in the host
# Redmine's views. A silently unmatched override produces no error, only a
# missing project selector, so this must be asserted per supported version.
#
require_relative '../spec_helper'

describe WorkflowsController, type: :controller do
  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules

  before { @request.session[:user_id] = 1 }

  let(:role)    { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }

  # There are fifteen overrides across twelve files, and each needs an assertion
  # that only *it* can satisfy. `include('project_id[]')` was not one: the
  # selector and the hidden field both render that name, so either could have
  # stopped matching without the suite noticing. Thirteen of them are on the
  # workflow screens and are asserted here; the other two are on the issue form
  # and are asserted in the IssuesController group at the foot of this file.
  def hidden_project_field
    /<input[^>]*type="hidden"[^>]*name="project_id\[\]"/
  end

  # Redmine 5.1 draws icons from CSS classes; 6.0 and later from SVG sprites.
  # Wherever the plugin renders markup core also renders, it has to match
  # whichever the host under test uses.
  def core_renders_sprites?
    ApplicationController.helpers.respond_to?(:sprite_icon)
  end

  it 'injects the project selector into the transitions page' do
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         project_id: ['global'], used_statuses_only: '0' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="project_id"')
  end

  it 'injects the hidden project fields into the transitions page' do
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         project_id: ['global'], used_statuses_only: '0' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(hidden_project_field)
  end

  it 'injects the project selector into the field permissions page' do
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                project_id: ['global'] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="project_id"')
  end

  it 'injects the hidden project fields into the field permissions page' do
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                project_id: ['global'] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(hidden_project_field)
  end

  it 'injects both project selectors into the copy page' do
    get :copy
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('source_project_id')
    expect(response.body).to include('target_project_ids')
  end

  # WP1 / INV-9. The scope panel is anchored on div.autoscroll, the same element
  # the hidden project fields use. It renders only when a real project is
  # selected: the generic workflow has no scope, so an administrator who does
  # not use the plugin keeps core's screens unchanged.
  describe 'the scope panel' do
    let(:project) { projects(:projects_001) }

    it 'reaches the transitions page when a project is selected' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('project-workflow-scope')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_inherits)))
      expect(response.body).to include('project_workflow_scopes')
    end

    it 'reaches the field permissions page when a project is selected' do
      get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                  project_id: [project.id.to_s] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('project-workflow-scope')
      expect(response.body).to include('project_workflow_scopes')
    end

    it 'offers the two enable actions while the project inherits' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_empty)))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inherit)))
    end

    it 'offers the empty and inherit actions once the project has a scope' do
      give_own_workflow(project, tracker, role)

      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_own_empty)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_clear)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inherit)))
    end

    # 'all' has to stay 'all' in the action links: expanding it would put every
    # project id into the URL.
    it 'keeps the whole-selection keyword in its links' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: ['all'], used_statuses_only: '0' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('project-workflow-scope')
      expect(response.body).to match(/project_workflow_scopes\?[^"']*project_id(%5B%5D|\[\])=all/)
    end

    it 'stays out of the way when only the generic workflow is selected' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('project-workflow-scope')
    end
  end

  # WP3 / INV-9. The summary page carries three of the overrides: the header
  # above the grid, the link to the inventory in core's own action menu, and the
  # count cells, which core builds without a project and which therefore linked
  # to the generic matrix however the page was filtered.
  describe 'the summary page' do
    let(:project) { projects(:projects_001) }

    it 'gets the project selector above the grid' do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="project_id"')
    end

    it 'gets the link to the inventory' do
      get :index

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_inventory)))
      expect(response.body).to include('project_workflow_inventories')
    end

    # The count cells are the third override, and this is the assertion only
    # they can satisfy: the header's selector renders 'project_id' too, but it
    # never renders it inside a link to workflows/edit.
    it 'carries the selected project into every count link' do
      give_own_workflow(project, tracker, role)

      get :index, params: { project_id: [project.id.to_s] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(
        %r{href="[^"]*/workflows/edit\?[^"]*project_id(%5B%5D|\[\])=#{project.id}}
      )
    end

    it 'draws the inventory link the way the host draws icons' do
      get :index
      link = response.body[%r{<a class="icon icon-list".*?</a>}m]

      expect(link).to be_present
      if core_renders_sprites?
        expect(link).to include('<svg')
      else
        expect(link).not_to include('<svg')
      end
    end

    # The count cells are the plugin's markup now, so an empty one has to look
    # the way core's did on the host it is running on.
    it 'marks an empty cell the way the host does' do
      get :index
      cell = response.body[%r{<a title="Edit".*?</a>}m]

      expect(cell).to be_present
      if core_renders_sprites?
        expect(cell).to include('decoration-red')
      else
        expect(cell).to include('icon-not-ok')
      end
    end

    # ... and leaves core's own URL alone for an administrator who does not use
    # the plugin, which is the other half of the same override.
    it 'leaves the count links as core built them by default' do
      get :index

      expect(response.body).to match(%r{href="[^"]*/workflows/edit\?[^"]*role_id=})
      expect(response.body).not_to match(%r{href="[^"]*/workflows/edit\?[^"]*project_id})
    end
  end

  # The inventory link also reaches the two matrices, which render core's action
  # menu partial. The summary and copy pages do not render that partial; the
  # summary page gets the link from the plugin's own header instead.
  it 'injects the inventory link into the action menu' do
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         project_id: ['global'], used_statuses_only: '0' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project_workflow_inventories')
  end

  # WP0 / claude F04. Since Redmine 6.0 core renders sprite_icon('') inside
  # every .toggle-multiselect span, and toggleMultiSelectIconInit() calls
  # updateSVGIcon($(this).find('svg')[0], iconType) for each of them. A span
  # without an <svg> makes that argument undefined, getElementsByTagName
  # raises, and because the call sits inside $(document).ready every
  # initialisation registered after it is skipped. Redmine 5.1 has no
  # sprite_icon at all and core's own spans are empty there, so the plugin's
  # span has to match whatever core does on the host it is running on.
  describe 'the multiselect toggle the plugin injects' do
    def toggle_spans(body)
      body.scan(%r{<span class="toggle-multiselect[^"]*">(.*?)</span>}m).flatten
    end

    it 'matches core on the transitions page' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }
      spans = toggle_spans(response.body)

      expect(spans.size).to be >= 3
      if core_renders_sprites?
        expect(spans).to all(include('<svg'))
      else
        expect(spans).to all(satisfy { |inner| inner.exclude?('<svg') })
      end
    end

    it 'matches core on the field permissions page' do
      get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                  project_id: ['global'] }
      spans = toggle_spans(response.body)

      expect(spans.size).to be >= 3
      if core_renders_sprites?
        expect(spans).to all(include('<svg'))
      else
        expect(spans).to all(satisfy { |inner| inner.exclude?('<svg') })
      end
    end
  end

  # WP5 / claude F06 / INV-9. The row and column actions, which are two overrides
  # on core's own workflows/_form -- the partial the project matrices render as
  # well, so one pair serves both screens. Each assertion is one only that
  # override can satisfy: the column action's selector names a new status and
  # the row action's an old one, and only the row override can produce
  # .old-status-0, which is the "new issue" row.
  describe 'the row and column actions' do
    before do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }
    end

    it 'reaches every column of every transition grid' do
      status = issue_statuses(:issue_statuses_002)

      expect(response).to have_http_status(:ok)
      %w[always author assignee].each do |name|
        expect(response.body).to include(
          %(data-project-workflow-target="table.transitions-#{name} .new-status-#{status.id}:not(:disabled)")
        )
      end
    end

    it 'reaches the rows, the "new issue" row included' do
      expect(response.body).to include(
        'data-project-workflow-target="table.transitions-always .old-status-0:not(:disabled)"'
      )
      expect(response.body).to include(ERB::Util.html_escape(
                                         I18n.t(:label_project_workflow_bulk_row, name: I18n.t(:label_issue_new),
                                                                                  value: I18n.t(:general_text_Yes))
                                       ))
    end

    # The function the actions call, written once however many rows, columns and
    # grids the page has.
    it 'writes the function once for the whole page' do
      expect(response.body.scan('function projectWorkflowBulkApply').size).to eq(1)
    end

    it 'carries the confirmation threshold the plugin setting holds' do
      expect(response.body).to include(
        %(data-project-workflow-threshold="#{RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD}")
      )
    end
  end

  # WP5. How much one cell stands for, and what "no change" means, above the
  # matrix. It says something only when a cell stands for more than one
  # workflow -- which is the case core's own no-change cells appear in.
  describe 'the note above the matrix' do
    let(:other_tracker) { trackers(:trackers_002) }

    def escaped(key)
      ERB::Util.html_escape(I18n.t(key, no_change: I18n.t(:label_no_change_option)))
    end

    it 'says how many workflows one cell stands for' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id, other_tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }

      sentence = I18n.t(:text_project_workflow_bulk_selection,
                        count: 2, trackers: 2, roles: 1, scopes: 1)

      expect(response.body).to include(ERB::Util.html_escape(sentence))
      expect(response.body).to include(escaped(:text_project_workflow_bulk_legend))
      expect(response.body).to include(escaped(:text_project_workflow_bulk_legend_actions))
    end

    it 'stays quiet when a cell is one workflow' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }

      expect(response.body).not_to include('project-workflow-bulk-note')
    end

    # Core renders "no change" cells on the field permissions page too, so the
    # sentence explaining them belongs there -- but that page has no row or
    # column actions, so the sentence about those must not follow it there.
    it 'reaches the field permissions page, without explaining a control it has not got' do
      get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id, other_tracker.id],
                                  project_id: ['global'] }

      expect(response.body).to include('project-workflow-bulk-note')
      expect(response.body).to include(escaped(:text_project_workflow_bulk_legend))
      expect(response.body).not_to include(escaped(:text_project_workflow_bulk_legend_actions))
      expect(response.body).not_to include('project-workflow-bulk-action')
    end
  end

  # WP6. What the last row or column action did, and a way back. Unlike the note
  # above it, this does not wait for a cell to stand for more than one workflow:
  # the actions are there whatever the size of the selection, and so is the cost
  # of clicking one by accident.
  describe 'the counter and the undo above the matrix' do
    let(:other_tracker) { trackers(:trackers_002) }

    it 'is on the transitions page for a selection of one workflow per cell' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }

      expect(response.body).to include('id="project-workflow-bulk-undo"')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_bulk_undo)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_bulk_unsaved)))
      # The two sentences the script fills in come down as data attributes, so
      # every string on the page stays in the locale files.
      expect(response.body).to include('data-project-workflow-changed')
      expect(response.body).to include('data-project-workflow-undone')
    end

    it 'is on the transitions page for a wide selection too' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id, other_tracker.id],
                           project_id: ['global'], used_statuses_only: '0' }

      expect(response.body).to include('id="project-workflow-bulk-undo"')
    end

    # No row or column actions there, so nothing for a counter to count or an
    # undo to undo.
    it 'is absent from the field permissions page' do
      get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id, other_tracker.id],
                                  project_id: ['global'] }

      expect(response.body).to include('project-workflow-bulk-note')
      expect(response.body).not_to include('id="project-workflow-bulk-undo"')
    end
  end
end

# WP8 / INV-9. The fourteenth and fifteenth overrides, the only two outside the
# workflow screens: the link to the workflow panel, beside core's own status
# control on the issue form.
#
# Two of them because core renders that control two different ways -- a select
# when the workflow permits something, and a plain label when it does not, which
# is exactly what an own *empty* workflow produces. Both anchors are
# byte-identical in 5.1, 6.1 and 7.0, unlike the help icon rendered directly
# after the select, which 6.0 turned into an SVG sprite.
#
# The assertion only these can satisfy is the link's own path: nothing else on an
# issue form renders it. What tells the two apart is whether the status select is
# on the page at all.
describe IssuesController, type: :controller do
  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :enumerations,
           :issues, :issue_categories, :versions

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }

  before do
    @request.session[:user_id] = 2
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: roles(:roles_001).id, project_id: nil,
                               old_status_id: 0, new_status_id: new_status.id)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: roles(:roles_001).id, project_id: nil,
                               old_status_id: new_status.id, new_status_id: assigned.id)
  end

  it 'injects the link into the edit form of a saved issue' do
    issue = Issue.create!(project: project, tracker: tracker, status: new_status,
                          author_id: 2, subject: 'deface override spec')

    get :edit, params: { id: issue.id }

    expect(response).to have_http_status(:ok)
    path = issue_workflow_map_path(issue, tracker_id: tracker.id)
    expect(response.body).to include(ERB::Util.html_escape(path))
  end

  # The new-issue form has no issue to name, so the link carries the project and
  # the tracker instead -- and that is the other half of the same override.
  it 'injects the link into the new-issue form' do
    get :new, params: { project_id: project.id, issue: { tracker_id: tracker.id } }

    expect(response).to have_http_status(:ok)
    path = project_workflow_map_path(project, tracker_id: tracker.id)
    expect(response.body).to include(ERB::Util.html_escape(path))
  end

  it 'draws the link the way the host draws icons' do
    get :new, params: { project_id: project.id, issue: { tracker_id: tracker.id } }
    link = response.body[%r{<a[^>]*class="icon-only icon-workflows project-workflow-map-link".*?</a>}m]

    expect(link).to be_present
    if ApplicationController.helpers.respond_to?(:sprite_icon)
      expect(link).to include('<svg')
    else
      expect(link).not_to include('<svg')
    end
  end

  # The fifteenth override, and the reason it exists.
  #
  # An own empty workflow permits nothing, so `new_statuses_allowed_to` returns
  # [] -- it appends the issue's own status only when the workflow permitted
  # something -- and core then renders no select, no help icon and no modal, only
  # a plain label. The first override anchors on the select, so it renders
  # nothing here: the panel would have been unreachable in the one case it exists
  # for. This is the example that caught it.
  it 'injects the link where core renders no status select at all' do
    issue = Issue.create!(project: project, tracker: tracker, status: new_status,
                          author_id: 2, subject: 'deface override spec')
    give_own_workflow(project, tracker, roles(:roles_001))

    get :edit, params: { id: issue.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('id="issue_status_id"')
    path = issue_workflow_map_path(issue, tracker_id: tracker.id)
    expect(response.body).to include(ERB::Util.html_escape(path))
  end

  # ... and it must not double up where core *does* render the select, which is
  # what a second anchor on the same page would produce.
  it 'injects the link exactly once where core renders the select' do
    issue = Issue.create!(project: project, tracker: tracker, status: new_status,
                          author_id: 2, subject: 'deface override spec')

    get :edit, params: { id: issue.id }

    expect(response.body).to include('id="issue_status_id"')
    expect(response.body.scan('project-workflow-map-link').size).to eq(1)
  end

  # Out of scope on purpose: a selection can span projects and trackers, so one
  # map would be a lie about most of it. core's bulk-edit form has markup of its
  # own, and this is the assertion that it stays that way.
  it 'stays off the bulk-edit form' do
    issue = Issue.create!(project: project, tracker: tracker, status: new_status,
                          author_id: 2, subject: 'deface override spec')

    get :bulk_edit, params: { ids: [issue.id] }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('workflow_map')
  end
end
