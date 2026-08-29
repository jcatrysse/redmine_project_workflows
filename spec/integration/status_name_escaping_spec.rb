# frozen_string_literal: true

require_relative '../spec_helper'

# WP15 item 3 -- stored cross-site scripting through an issue status name.
#
# A status name is free text an administrator types and Redmine stores, and this
# plugin puts it on surfaces core does not: an inline SVG drawing, the table
# beneath it, the SVG's `<title>` tooltips, a JavaScript response that assembles
# the issue form's workflow panel as a string, and the `title` and `data-`
# attributes of the transitions matrix's row and column actions. Three of those
# are contexts in which "ERB escapes it" is an argument rather than a fact:
#
#   * inside an SVG document `<` opens a tag exactly as it does in HTML, so an
#     unescaped name is markup -- and the drawing puts names in `<title>`, in
#     `<tspan>` and in an `aria-label` attribute;
#   * the JavaScript response interpolates rendered HTML into a quoted string
#     literal, where the escaping that matters is `escape_javascript`'s rather
#     than ERB's;
#   * the row and column actions put a status name into a `title` attribute and
#     into a `data-` attribute that the plugin's own JavaScript reads back.
#
# Each surface is asserted twice over: the payload comes back escaped, and --
# the assertion that carries the weight -- the parsed response holds no element
# or event-handler attribute the payload could have created. The escaped form
# being present proves nothing on its own; a page that carried both would
# satisfy it.
#
# The payloads differ per surface because what is dangerous differs: a tag in
# HTML and SVG, a quote-and-close in an attribute, a string terminator in
# JavaScript.
module StatusNameEscapingHelpers
  SCRIPT_PAYLOAD = '<script>alert(1)</script>'
  ATTRIBUTE_PAYLOAD = 'x" onmouseover="alert(1)'
  JS_PAYLOAD = "x');alert(1);//"

  # Renamed rather than created, so that everything already pointing at the
  # status keeps pointing at it and one rename reaches every surface at once.
  # `update_columns` because core validates the name's length and this is about
  # what a database row can hold, not about what the form accepts -- a name can
  # also have been stored by an older Redmine, by a plugin, or by the API.
  def rename(status, name)
    # rubocop:disable Rails/SkipsModelValidations -- the point of the payload is
    # a name core's own form would refuse; what a *stored* one does to a page is
    # the question, and such a row can arrive from an older Redmine, the API, or
    # a neighbouring plugin.
    status.update_columns(name: name)
    # rubocop:enable Rails/SkipsModelValidations
    status.reload
  end

  # The same parser `css_select` uses, asked the question a browser would:
  # did any of this become executable?
  def expect_no_live_markup(body)
    document = Nokogiri::HTML(body)

    expect(document.css('script').map(&:text).join).not_to include('alert(1)')
    expect(document.css('[onmouseover]')).to be_empty
    expect(document.css('[onerror]')).to be_empty
  end
end

# The drawing, its tooltips and its table (WP9).
describe ProjectWorkflowsController, type: :controller do
  include StatusNameEscapingHelpers

  render_views

  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:open_status) { issue_statuses(:issue_statuses_001) }
  let(:target_status) { issue_statuses(:issue_statuses_002) }

  before do
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: open_status.id, new_status_id: target_status.id)
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
    role.add_permission!(:view_project_workflow_rules, :manage_project_workflow_rules)
    @request.session[:user_id] = 2
  end

  def graph_params
    { project_id: project.id, tracker_id: tracker.id, role_id: [role.id] }
  end

  describe 'a status named with a script tag' do
    before { rename(open_status, StatusNameEscapingHelpers::SCRIPT_PAYLOAD) }

    it 'escapes it everywhere on the drawing page' do
      get :graph, params: graph_params

      expect(response).to have_http_status(:ok)
      expect_no_live_markup(response.body)
      # Present, and present escaped: a page that simply dropped the name would
      # also have no live markup on it, and would be a different defect.
      expect(response.body).to include(ERB::Util.html_escape(StatusNameEscapingHelpers::SCRIPT_PAYLOAD))
    end

    # The three places inside the SVG that carry a name, each asserted as text
    # rather than as markup. `<title>` is the tooltip, `<tspan>` the label drawn
    # in the box, and `aria-label` what a screen reader is given.
    it 'keeps it out of the SVG document as markup' do
      get :graph, params: graph_params

      # The drawing's own <svg>, named by its class: on 6.0 and later the page
      # layout is full of sprite icons that are <svg> elements too, and the
      # first one on the page is one of those. An assertion scoped to the page
      # rather than to the element is the near-miss this repository keeps
      # meeting.
      document = response.body[%r{<svg[^>]*project-workflow-graph-svg.*?</svg>}m]
      expect(document).not_to be_nil, 'the drawing did not render'

      svg = Nokogiri::XML(document)
      # Well-formedness *is* the assertion: an unescaped `<` in a status name
      # opens a tag inside the drawing, and a parser is what notices.
      expect(svg.errors).to be_empty, "the drawing is not well-formed XML: #{svg.errors.first}"
      expect(svg.css('script')).to be_empty
      # The name reached the drawing -- as text in a title, a tspan, or both --
      # so the two assertions above are about a document that carries it. The
      # label in the box is truncated to fit, which is why only the title is
      # asserted whole.
      expect(svg.css('title').map(&:text).join(' '))
        .to include(StatusNameEscapingHelpers::SCRIPT_PAYLOAD)
    end

    it 'escapes it in the table beneath the drawing' do
      get :graph, params: graph_params

      # `#to_s` on the NodeSet, which serialises every node in it. `map(&:to_s)
      # .join` says the same and reads to Style/MapJoin as a redundant map --
      # over a NodeSet, whose #join does not exist, so the correction it offers
      # raises.
      cells = css_select('table.project-workflow-graph-transitions td.name').to_s
      expect(cells).not_to be_empty, 'the drawing rendered no transition table to assert about'
      expect(cells).not_to include('<script')
      expect(cells).to include('&lt;script&gt;')
    end
  end

  describe 'a status named so as to break out of an attribute' do
    before { rename(open_status, StatusNameEscapingHelpers::ATTRIBUTE_PAYLOAD) }

    it 'leaves no event handler on the drawing page' do
      get :graph, params: graph_params

      expect(response).to have_http_status(:ok)
      expect_no_live_markup(response.body)
    end

    # The row and column actions put the name into `title`, `aria-label` and a
    # `data-` attribute the plugin's own JavaScript reads back out.
    it 'leaves no event handler on the transitions matrix' do
      get :transitions, params: { project_id: project.id, tracker_id: tracker.id, role_id: role.id }

      expect(response).to have_http_status(:ok)
      expect_no_live_markup(response.body)
      # The actions are on the page, so the assertion above is about a page that
      # actually carries the name rather than about one that never rendered it.
      expect(response.body).to include('project-workflow-bulk')
    end
  end
end

# The issue form's panel, which arrives as JavaScript (WP8).
#
# `show.js.erb` is one `$('#ajax-modal').html('...')` with the rendered panel
# interpolated into the string literal. ERB's HTML escaping does nothing for the
# quote that would close that literal; `escape_javascript` is what does, and
# this is what says so.
describe ProjectWorkflowMapsController, type: :controller do
  include StatusNameEscapingHelpers

  render_views

  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :enumerations, :issues

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }

  before do
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                               old_status_id: new_status.id, new_status_id: assigned.id)
    RedmineProjectWorkflows::Services::Resolver.reset_cache!
    @request.session[:user_id] = 2
  end

  def an_issue
    Issue.create!(project: project, tracker: tracker, status: new_status,
                  author_id: 2, subject: 'status name escaping spec')
  end

  it "does not let a status name close the JavaScript response's string literal" do
    rename(assigned, StatusNameEscapingHelpers::JS_PAYLOAD)
    issue = an_issue

    get :show, params: { issue_id: issue.id }, format: :js, xhr: true

    expect(response).to have_http_status(:ok)
    # The one line the response is: everything the panel contains is inside a
    # single-quoted string, so an unescaped `'` would end it and everything
    # after would be code. `escape_javascript` writes `\'`.
    expect(response.body).not_to include("');alert(1)")
    expect(response.body).to include('alert(1)')
    expect(response.body).to match(/\\['"]/)
  end

  it 'does not let a status name open a tag in the panel it builds' do
    rename(assigned, StatusNameEscapingHelpers::SCRIPT_PAYLOAD)
    issue = an_issue

    get :show, params: { issue_id: issue.id }, format: :js, xhr: true

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('<script>alert(1)</script>')
    expect(response.body).to include('&lt;script&gt;')
  end

  # The same panel without JavaScript, which is a page of its own rather than a
  # dead link -- and therefore a surface of its own.
  it 'escapes a status name on the panel\'s HTML fallback' do
    rename(assigned, StatusNameEscapingHelpers::SCRIPT_PAYLOAD)
    issue = an_issue

    get :show, params: { issue_id: issue.id }

    expect(response).to have_http_status(:ok)
    expect_no_live_markup(response.body)
    expect(response.body).to include(ERB::Util.html_escape(StatusNameEscapingHelpers::SCRIPT_PAYLOAD))
  end
end
