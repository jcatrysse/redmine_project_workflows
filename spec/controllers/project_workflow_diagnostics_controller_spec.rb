# frozen_string_literal: true

require 'tmpdir'
require_relative '../spec_helper'

describe ProjectWorkflowDiagnosticsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  render_views

  describe 'authorization' do
    # G5 / INV-7. The page names the installation's patches, permissions and
    # Redmine version, which is reconnaissance rather than project data, so it
    # is administrator-only -- there is no project for it to authorize against.
    it 'sends an anonymous visitor to the login page' do
      get :show

      expect(response).to redirect_to(/login/)
    end

    it 'refuses a logged-in non-administrator' do
      @request.session[:user_id] = 2

      get :show

      expect(response).to have_http_status(:forbidden)
    end

    it 'answers an administrator' do
      @request.session[:user_id] = 1

      get :show

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'the page' do
    before { @request.session[:user_id] = 1 }

    it 'says which Redmine this is and which ones the plugin is tested against' do
      get :show

      expect(response.body).to include(RedmineProjectWorkflows::Compatibility.host_version)
      RedmineProjectWorkflows::Compatibility.verified_minors.each do |minor|
        expect(response.body).to include(minor)
      end
    end

    it 'says that this Redmine is one the plugin is tested against' do
      get :show

      expect(response.body)
        .to include(ERB::Util.html_escape(
                      I18n.t(:text_project_workflow_diagnostics_verified,
                             version: RedmineProjectWorkflows::Compatibility.host_minor)
                    ))
    end

    it 'names both permissions and every patch' do
      get :show

      expect(response.body).to include('view_project_workflow_rules', 'manage_project_workflow_rules')
      RedmineProjectWorkflows::Services::Diagnostics::ATTACHMENTS.each do |patch_name, _style, _owners|
        expect(response.body).to include(patch_name)
      end
    end

    it 'lists the Deface overrides against the views they are registered on' do
      get :show

      expect(response.body).to include('redmine_project_workflows_action_menu_cross_link')
      expect(response.body).to include('workflows/_action_menu')
    end

    # The drift table is absent when there is nothing to say, rather than
    # present and empty: an empty table under a heading reads as a measurement
    # that failed.
    it 'draws no drift table on a verified host' do
      get :show

      expect(response.body).not_to include(I18n.t(:label_project_workflow_diagnostics_drift))
    end

    # And the state that cannot happen on a host the manifest lists. The
    # synthetic manifest is the seam spec/compatibility_spec.rb explains: the
    # digests are really measured here, only the table is fictional.
    context 'on a Redmine the manifest has never been measured against' do
      let(:manifest_path) { File.join(Dir.tmpdir, "compatibility-#{SecureRandom.hex(4)}.yml") }

      before do
        measured = RedmineProjectWorkflows::Services::CoreMethodDigest.digests
        digests = measured.merge('Issue#new_statuses_allowed_to' => 'x' * 64)
        File.write(manifest_path,
                   YAML.dump('sprite_icons_from' => '6.0',
                             'databases' => ['PostgreSQL'],
                             'dependencies' => RedmineProjectWorkflows::Compatibility.dependencies,
                             'minors' => { '99.9' => { 'ruby' => '3.3', 'rails' => '8.0',
                                                       'digests' => digests } }))
        RedmineProjectWorkflows::Compatibility.data_file = manifest_path
      end

      after { RedmineProjectWorkflows::Compatibility.reset! }

      it 'warns, names the method that changed, and says where Redmine defines it' do
        get :show

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t(:label_project_workflow_diagnostics_drift))
        expect(response.body).to include('Issue#new_statuses_allowed_to')
        expect(response.body).to include('app/models/issue.rb')
        expect(response.body).to include(I18n.t(:label_project_workflow_diagnostics_changed))
      end

      # A warning, never a refusal (ADR-002 decision 4): the screens an
      # administrator would use to put it right go on working.
      it 'leaves the workflow screens working' do
        get :show

        expect(response).to have_http_status(:ok)
      end
    end
  end

  # The entry point. The page is reachable only from the administration menu, so
  # a menu item that Redmine's MenuManager quietly refused would leave a page
  # nobody can find -- and the options differ by version: 6.0 and later read
  # `:icon` and draw a sprite, 5.1 ignores it and draws the picture behind the
  # CSS class. Asserted through the rendered administration page rather than
  # through MenuManager's own registry, because the registry cannot tell whether
  # the item survives rendering on this host.
  # G4. Every string the page renders is a key, in every locale the plugin
  # ships -- and the page is where a missing one would be least visible,
  # because an administrator opening it is already looking at something else.
  describe 'in every locale' do
    let(:admin) { users(:users_001) }
    # Only the ones this host actually offers, and that is a real difference
    # between the supported versions rather than a convenience. 6.1 and 7.0 set
    # `config.i18n.available_locales` from core's own config/locales/*.yml;
    # 5.1's application.rb does not. Measured on a 5.1 host under
    # RAILS_ENV=test: `I18n.load_path` holds 63 files including two nl.yml, and
    # `I18n.available_locales` is `[:en]` all the same -- so
    # `I18n.t(key, locale: 'nl')` raises InvalidLocale there and the page can
    # only ever render in English. Whether that also holds outside the test
    # environment was not measured; it is core's own configuration either way,
    # and it applies to core's own translations exactly as it does to this
    # plugin's.
    #
    # Asking the host keeps the example strong where it can be strong and
    # honest where it cannot: on 6.1 and 7.0 it renders all eight. The eight
    # files themselves are asserted by spec/locales_spec.rb on every cell.
    let(:locales) { %w[en nl de es fr it pl pt] & I18n.available_locales.map(&:to_s) }

    before { @request.session[:user_id] = admin.id }

    # update_columns rather than update!: the fixture user has no password and
    # would not validate, and the language is not what is under test here.
    after { admin.update_columns(language: 'en') } # rubocop:disable Rails/SkipsModelValidations

    it 'renders with no missing translation' do
      locales.each do |locale|
        admin.update_columns(language: locale) # rubocop:disable Rails/SkipsModelValidations

        get :show

        # First that the page really is in that language. Without this the
        # example is vacuous: a locale that never took effect renders in
        # English, where nothing is ever missing.
        expect(response.body)
          .to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_diagnostics, locale: locale))), locale
        expect(response.body).not_to include('translation missing'), locale
        expect(response.body).not_to include('translation_missing'), locale
      end
    end
  end
end

# The entry point. The page is reachable only from the administration menu, so a
# menu item Redmine's MenuManager quietly refused would leave a page nobody can
# find -- and the options differ by version: 6.0 and later read `:icon` and draw
# a sprite from core's own sheet, while 5.1's MenuItem ignores the option and
# draws the picture behind the CSS class. Asserted through the rendered
# administration page rather than through MenuManager's registry, because the
# registry cannot say whether the item survives rendering on this host.
describe AdminController, type: :controller do
  fixtures :projects, :users, :roles, :trackers, :issue_statuses, :enumerations

  render_views

  it 'draws the diagnostics entry on Redmine\'s own administration page' do
    @request.session[:user_id] = 1

    get :index

    expect(response.body).to include(project_workflow_diagnostics_path)
    expect(response.body).to include(I18n.t(:label_project_workflow_diagnostics))
  end
end
