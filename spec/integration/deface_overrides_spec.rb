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

  it 'injects the project selector into the transitions page' do
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         project_id: ['global'], used_statuses_only: '0' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project_id[]')
  end

  it 'injects the project selector into the field permissions page' do
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                project_id: ['global'] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project_id[]')
  end

  it 'injects both project selectors into the copy page' do
    get :copy
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('source_project_id')
    expect(response.body).to include('target_project_ids')
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
