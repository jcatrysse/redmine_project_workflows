# frozen_string_literal: true

require_relative '../spec_helper'

# WP19, finding F05 of docs/review/findings/2026-08-29-claude-revalidation.md.
#
# ADR-002's compatibility object knew, in four states, whether the Redmine under
# the plugin is one the plugin has been tested against and whether anything it
# copied out of Redmine has changed since. It said so in the application log,
# once per process, and on a diagnostics page nobody has to visit. The screens
# where somebody is about to change a workflow rule -- which is authorization
# configuration -- said nothing at all.
#
# Two things are asserted here and they are equally important. **Every screen**
# that writes shows the banner, because one that does not is the screen the
# warning was needed on; and a **verified** host shows nothing anywhere, because
# a banner that is always there is furniture and the next real one is not read.
#
# `Compatibility.state` is stubbed rather than driven through a synthetic
# manifest: what the four states are and when each is reached is
# spec/compatibility_spec.rb's subject, and what is under test here is which
# screens carry the answer.
describe 'the compatibility banner' do
  # Every screen of the plugin on which a workflow rule can be changed, plus the
  # summary and copy screens of the same administration area. A screen added
  # later without one fails here rather than being noticed on a drifted host.
  shared_examples 'a screen that carries the compatibility state' do
    it 'says nothing on a host the plugin is tested against' do
      allow(RedmineProjectWorkflows::Compatibility).to receive(:state).and_return(:verified)

      render_screen

      expect(response.body).not_to include('class="warning"')
    end

    %i[unverified unmeasured drifted].each do |state|
      it "names the state and links to the diagnostics page when the host is #{state}" do
        # Only `state`. `host_minor` drives `core_sprite_icons?` too, so a
        # fictional version there would make the plugin draw 6.x markup on a 5.1
        # host and fail these examples for a reason of their own making -- which
        # is the shape of finding F02 of 2026-08-28-claude-plugin-compat-5.1, in
        # a spec instead of in the product.
        allow(RedmineProjectWorkflows::Compatibility).to receive(:state).and_return(state)

        render_screen

        expect(response.body).to include(
          ERB::Util.html_escape(
            I18n.t(:"text_project_workflow_compatibility_banner_#{state}",
                   version: RedmineProjectWorkflows::Compatibility.host_minor)
          )
        )
        expect(response.body).to include('/project_workflow_diagnostics')
      end
    end
  end

  describe ProjectWorkflowRulesController, type: :controller do
    fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

    render_views

    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before { @request.session[:user_id] = 1 }

    context 'the summary' do
      def render_screen = get(:index)

      it_behaves_like 'a screen that carries the compatibility state'
    end

    context 'the transitions matrix' do
      def render_screen
        get :edit, params: { tracker_id: [tracker.id], role_id: [role.id] }
      end

      it_behaves_like 'a screen that carries the compatibility state'
    end

    context 'the field permissions matrix' do
      def render_screen
        get :permissions, params: { tracker_id: [tracker.id], role_id: [role.id] }
      end

      it_behaves_like 'a screen that carries the compatibility state'
    end

    context 'the copy screen' do
      def render_screen = get(:copy)

      it_behaves_like 'a screen that carries the compatibility state'
    end
  end

  # The project's own matrices, where a non-administrator writes. The link is
  # left off for them -- the diagnostics page requires an administrator, and a
  # link to a 403 would tell a project manager less than the sentence already
  # does -- so this group asserts the sentence and its absence, and the link
  # question is the group below.
  describe ProjectWorkflowsController, type: :controller do
    fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
             :member_roles, :enabled_modules, :projects_trackers

    render_views

    let(:project) { projects(:projects_001) }
    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before do
      role.add_permission!(:manage_project_workflow_rules)
      @request.session[:user_id] = 1
    end

    context 'the project transitions matrix' do
      def render_screen
        get :transitions, params: { project_id: project.id, tracker_id: tracker.id, role_id: role.id }
      end

      it_behaves_like 'a screen that carries the compatibility state'
    end

    context 'the project field permissions matrix' do
      def render_screen
        get :permissions, params: { project_id: project.id, tracker_id: tracker.id, role_id: role.id }
      end

      it_behaves_like 'a screen that carries the compatibility state'
    end

    it 'gives a non-administrator the sentence without the link they could not open' do
      allow(RedmineProjectWorkflows::Compatibility).to receive(:state).and_return(:drifted)
      @request.session[:user_id] = users(:users_002).id

      get :transitions, params: { project_id: project.id, tracker_id: tracker.id, role_id: role.id }

      expect(response.body).to include(
        ERB::Util.html_escape(
          I18n.t(:text_project_workflow_compatibility_banner_drifted,
                 version: RedmineProjectWorkflows::Compatibility.host_minor)
        )
      )
      expect(response.body).not_to include('/project_workflow_diagnostics')
    end
  end

  # The settings tab, which is where a project takes its own workflow on and
  # gives it back -- a write, on somebody else's controller.
  describe ProjectsController, type: :controller do
    fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
             :member_roles, :enabled_modules, :projects_trackers

    render_views

    let(:project) { projects(:projects_001) }

    before { @request.session[:user_id] = 1 }

    context 'the project settings tab' do
      def render_screen
        get :settings, params: { id: project.id, tab: 'project_workflows' }
      end

      it_behaves_like 'a screen that carries the compatibility state'
    end
  end
end
