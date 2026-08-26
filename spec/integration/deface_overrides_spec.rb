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

  # There are eight overrides across seven files, and each needs an assertion
  # that only *it* can satisfy. `include('project_id[]')` was not one: the
  # selector and the hidden field both render that name, so either could have
  # stopped matching without the suite noticing.
  def hidden_project_field
    /<input[^>]*type="hidden"[^>]*name="project_id\[\]"/
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

    def core_renders_sprites?
      ApplicationController.helpers.respond_to?(:sprite_icon)
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
