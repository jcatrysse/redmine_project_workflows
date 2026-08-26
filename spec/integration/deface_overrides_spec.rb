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

  # There are eleven overrides across ten files, and each needs an assertion
  # that only *it* can satisfy. `include('project_id[]')` was not one: the
  # selector and the hidden field both render that name, so either could have
  # stopped matching without the suite noticing.
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
end
