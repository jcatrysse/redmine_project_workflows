# frozen_string_literal: true

#
# The plugin's settings screen (WP5). It is core's screen rendering the plugin's
# partial, so what can go wrong is the wiring: a partial Redmine cannot find
# raises on the administration page, and a field name that does not match what
# core writes back saves nothing while looking as though it did.
#
require_relative '../spec_helper'

describe SettingsController, type: :controller do
  render_views
  fixtures :users, :email_addresses, :roles

  after { Setting.clear_cache }

  describe 'as an administrator' do
    before do
      @request.session[:user_id] = 1
      # Redmine puts its administration screens behind sudo mode, which is on by
      # default: the password is confirmed once and the session carries the
      # confirmation for a quarter of an hour. Without this the screen under test
      # answers with the password form instead of itself.
      @request.session[:sudo_timestamp] = Time.now.to_i
    end

    it 'renders the threshold field, with the number that is in force' do
      get :plugin, params: { id: 'redmine_project_workflows' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="settings[bulk_confirm_threshold]"')
      expect(response.body).to include(ERB::Util.html_escape(
                                         I18n.t(:label_project_workflow_bulk_confirm_threshold)
                                       ))
      expect(response.body).to include(
        %(value="#{RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD}")
      )
    end

    # Redmine's plugin settings have no validation hook -- SettingsController
    # assigns the submitted hash as it arrives -- so a value that is not a run
    # of digits is accepted, stored, and then silently ignored by the helper,
    # which falls back to the default. The field is what refuses it, and the
    # fallback stays for anything saved before this attribute existed.
    it 'refuses a threshold that is not a whole number, in the field itself' do
      get :plugin, params: { id: 'redmine_project_workflows' }

      field = response.body[/<input[^>]*name="settings\[bulk_confirm_threshold\]"[^>]*>/]
      expect(field).to include('type="number"')
      expect(field).to include('min="0"')
    end

    it 'falls back to the default for a value that was saved anyway' do
      Setting.plugin_redmine_project_workflows = { 'bulk_confirm_threshold' => 'lots' }

      helper = Object.new.extend(RedmineProjectWorkflows::BulkActionsHelper)

      expect(helper.project_workflow_bulk_confirm_threshold)
        .to eq(RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD)
    end

    it 'saves what was typed into it' do
      post :plugin, params: { id: 'redmine_project_workflows',
                              settings: { 'bulk_confirm_threshold' => '12' } }

      expect(Setting.plugin_redmine_project_workflows['bulk_confirm_threshold']).to eq('12')
    end

    # The field shows the value in force rather than an empty box, so saving the
    # page without touching it keeps the number rather than clearing it.
    it 'shows a saved value back' do
      Setting.plugin_redmine_project_workflows = { 'bulk_confirm_threshold' => '7' }

      get :plugin, params: { id: 'redmine_project_workflows' }

      expect(response.body).to include('value="7"')
    end
  end

  # Core's own authorization, asserted because this is an entry point the plugin
  # added: the screen exists only because the plugin declared a settings block.
  it 'is administrator-only' do
    @request.session[:user_id] = 2

    get :plugin, params: { id: 'redmine_project_workflows' }

    expect(response).to have_http_status(:forbidden)
  end

  it 'sends an anonymous visitor to the login page' do
    get :plugin, params: { id: 'redmine_project_workflows' }

    expect(response).to redirect_to(%r{/login})
  end
end
