# frozen_string_literal: true

#
# Guards that every Deface override still matches its anchor in the host
# Redmine's views. A silently unmatched override produces no error, only a
# missing project selector, so this must be asserted per supported version.
#
require_relative '../spec_helper'

# INV-9's two numbers, in the one place a spec reads them from. Change these only
# together with the assertion for the new override, and with CLAUDE.md and
# docs/design.md, which carry the same numbers in words -- the third example
# below is what stops those drifting apart.
INV9_COUNTS = { overrides: 5, files: 3 }.freeze
# The counts as the documents write them: prose, not digits.
INV9_COUNT_WORDS = { 1 => 'one', 2 => 'two', 3 => 'three', 4 => 'four', 5 => 'five',
                     6 => 'six', 7 => 'seven', 8 => 'eight', 9 => 'nine', 10 => 'ten',
                     11 => 'eleven', 12 => 'twelve', 13 => 'thirteen',
                     14 => 'fourteen', 15 => 'fifteen' }.freeze

# F08. INV-9 says there are five overrides in three files -- ten in nine files
# fewer than before ADR-003 -- and three places write that down: CLAUDE.md,
# docs/design.md and the comment below. The suite asserts each of the five
# against the rendered page with an assertion only that one can satisfy, and
# asserted the *count* nowhere: a sixth override added without an assertion
# passed every gate, silently, which is the exact shape INV-9 exists to
# prevent.
#
# This is a speed bump, and it should be described as one rather than as a proof.
# It cannot tell that override six has an assertion; what it does is turn a
# silent omission into a deliberate one, because adding an override now forces
# the author to touch the constant, and the review rule for touching it is "add
# the assertion in the same commit" (CLAUDE.md's forbidden-constructs table).
#
# Counting `Deface::Override.new` in the source rather than introspecting
# Deface's own registry: the registry would be stronger and would couple the gate
# to a Deface internal, which is the argument F12 makes against depending on that
# gem's shape. The names are checked for uniqueness in the same pass, because two
# overrides sharing a name is the other way this count can be right and the
# overrides wrong -- Deface keys on the name, so the second would replace the
# first.
# Redmine 5.1 draws icons from CSS classes; 6.0 and later from SVG sprites.
# Wherever the plugin renders markup core also renders, it has to match
# whichever the host under test uses.
#
# Asks the production predicate rather than restating its condition -- see the
# same helper in project_workflows_controller_spec.rb, and finding F02 of
# 2026-08-28-claude-plugin-compat-5.1. Two of this file's groups need it, so it
# lives here rather than in one of them.
module DefaceOverrideIconHelpers
  def core_renders_sprites?
    RedmineProjectWorkflows::VersionHelper.core_sprite_icons?
  end
end

describe 'the INV-9 override inventory' do
  let(:override_files) do
    Dir.glob(File.expand_path('../../lib/redmine_project_workflows/overrides/*.rb', __dir__))
  end

  it 'has exactly the number of overrides INV-9 names, in the number of files it names' do
    sources = override_files.map { |file| File.read(file) }

    expect(override_files.size).to eq(INV9_COUNTS[:files])
    expect(sources.sum { |source| source.scan('Deface::Override.new').size }).to eq(INV9_COUNTS[:overrides])
  end

  # Deface keys an override on its name, so two sharing one means the second
  # replaces the first -- a count that is still right over overrides that are
  # not.
  #
  # The name is taken from inside each Deface::Override.new call rather than by
  # grepping the file for `name:`. A plain grep used to find seventeen in fifteen,
  # because two of the deleted overrides rendered form fields whose own markup
  # carried `name: 'source_project_id'` and `name: 'target_project_ids[]'` -- and
  # a gate that counted those would have been wrong in the direction that hides a
  # missing override. The construct is kept now that they are gone: what made it
  # wrong can come back with any override that renders a form field.
  def override_names
    override_files.flat_map do |file|
      File.read(file).split('Deface::Override.new')[1..].map do |call|
        call[/name:\s*['"]([^'"]+)['"]/, 1]
      end
    end
  end

  it 'gives every override a distinct name' do
    names = override_names

    expect(names.compact.size).to eq(INV9_COUNTS[:overrides])
    expect(names.uniq.size).to eq(INV9_COUNTS[:overrides])
  end

  # Deface's registry is global across every installed plugin, so an unprefixed
  # name is a collision waiting for a neighbour to introduce it -- and the loser
  # of a collision is silent, which is INV-9's whole subject.
  it 'prefixes every override name with the plugin id' do
    expect(override_names).to all(start_with('redmine_project_workflows_'))
  end

  # The numbers in the three documents have to be the numbers here. Asserted
  # against the prose because that is where a reader looks first, and a stale
  # "five" beside a constant reading six is how INV-9 stopped being believable
  # the last three times a count in this repository drifted.
  #
  # Against the *phrase*, not the word. While the counts were fifteen and twelve
  # a bare `include('fifteen')` was a real assertion, because no document says
  # "fifteen" about anything else. ADR-003 took them to five and three, which are
  # ordinary English words that appear in both files for a dozen unrelated
  # reasons -- so the word alone would have gone on passing over any count
  # whatsoever. What is asserted is the sentence the reader actually reads.
  it 'is the count CLAUDE.md and docs/design.md write down' do
    root = File.expand_path('../..', __dir__)
    overrides = INV9_COUNT_WORDS.fetch(INV9_COUNTS[:overrides])
    files = INV9_COUNT_WORDS.fetch(INV9_COUNTS[:files])

    [File.read("#{root}/CLAUDE.md"), File.read("#{root}/docs/design.md")].each do |document|
      text = document.downcase.delete('*')
      expect(text).to match(/\b#{overrides} (?:view |deface )?overrides\b/)
      expect(text).to match(/\bin #{files} files\b/)
    end
  end
end

# Three of the five overrides are on core's own workflow screens, and they are
# what is left there after ADR-003: the cross-link into core's action menu, and
# the row and column actions on core's transition grid. Everything else the
# plugin used to inject into these views is gone, together with the ten
# overrides that injected it -- so the negative assertions below are as much a
# part of INV-9 as the positive ones.
describe WorkflowsController, type: :controller do
  include DefaceOverrideIconHelpers

  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules

  before { @request.session[:user_id] = 1 }

  let(:role)    { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:project) { projects(:projects_001) }

  def render_transitions
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id], used_statuses_only: '0' }
  end

  # The third override, and the one ADR-003 asks for by name ("core's workflow
  # screen points at the plugin's, and the plugin's points back"). Answered
  # **A** by Jan on 2026-08-28.
  #
  # Scoped to core's own action menu, and that scoping is the whole assertion.
  # `href="/project_workflow_rules"` appears on **every** administration page
  # whatever this override does, because the admin_menu entry WP12 registered is
  # in the `admin` layout -- so the unscoped version of this example stayed green
  # with the link deleted from the override and the page rendered without it.
  # Found by deleting it and watching the example not fail, which is the only way
  # this kind of near-miss ever shows up.
  it 'injects the cross-link into the action menu' do
    render_transitions

    expect(response).to have_http_status(:ok)
    expect(css_select('div.contextual a[href="/project_workflow_rules"]')).to be_present
  end

  # It reaches the field permissions screen too, which is the other of the two
  # core renders this partial from.
  it 'injects the cross-link into the field permissions action menu' do
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id] }

    expect(response).to have_http_status(:ok)
    expect(css_select('div.contextual a[href="/project_workflow_rules"]')).to be_present
  end

  # The inventory link went with the project dimension: "which projects have
  # taken a workflow over" is a question about projects, and it is asked from
  # the plugin's own action bar now. A second link here would be the override
  # that was never narrowed.
  it 'leaves the inventory link on the plugin\'s own screens' do
    render_transitions

    expect(css_select('div.contextual a[href="/project_workflow_inventories"]')).to be_empty
  end

  # WP5 / claude F06 / INV-9. The row and column actions, which are two overrides
  # on core's own workflows/_form -- the partial the plugin's matrices render as
  # well, so one pair serves both screens, and it is core's screen that owns the
  # anchors. Each assertion is one only that override can satisfy: the column
  # action's selector names a new status and the row action's an old one, and
  # only the row override can produce .old-status-0, which is the "new issue"
  # row.
  #
  # They keep working here because
  # RedmineProjectWorkflows::Patches::WorkflowsControllerHelperPatch puts
  # ProjectWorkflowMatrixHelper into this controller's helper chain. Without it
  # core's own workflow screen raises NoMethodError, which is why that patch is
  # the one thing ADR-003 leaves attached to this controller besides the queries.
  describe 'the row and column actions' do
    before { render_transitions }

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

  # ADR-003's subtraction, asserted rather than assumed. Ten overrides in nine
  # files were deleted; an override left registered by accident, or a partial
  # still rendered from somewhere, would put this markup back on a screen that
  # is meant to be Redmine's own -- and INV-9's count alone would not notice,
  # because it counts what is in the source rather than what reaches a page.
  describe 'what core\'s screens no longer carry' do
    it 'has no project selector or hidden project field on the transitions page' do
      render_transitions

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('project_id[]')
      expect(response.body).not_to include('id="project_id"')
    end

    it 'has no project selector or hidden project field on the field permissions page' do
      get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id] }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('project_id[]')
    end

    it 'has no scope panel, whatever the request asks for' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('project-workflow-scope')
    end

    it 'has no project selector on the summary page, and core\'s own count links' do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('id="project_id"')
      expect(response.body).to match(%r{href="[^"]*/workflows/edit\?[^"]*role_id=})
      expect(response.body).not_to match(%r{href="[^"]*/workflows/edit\?[^"]*project_id})
    end

    it 'has no project selectors on the copy page' do
      get :copy

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('source_project_id')
      expect(response.body).not_to include('target_project_ids')
    end
  end
end

# WP8 / INV-9. The fourth and fifth overrides, the only two outside the
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
  include DefaceOverrideIconHelpers

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
    # A no-op unless a neighbouring plugin gates core's issue pages; see
    # HostPluginPermissionHelpers.
    grant_host_issue_page_permissions(roles(:roles_001))
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
    if core_renders_sprites?
      expect(link).to include('<svg')
    else
      expect(link).not_to include('<svg')
    end
  end

  # The fifth override, and the reason it exists.
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

  # And the case that makes the second override more than a plugin corner: core
  # renders no select for **any** status with nothing leading out of it, on a
  # plain generic workflow with no plugin scope anywhere. `new_statuses_allowed_to`
  # appends the issue's own status only when the workflow permitted something, so
  # a dead-end status empties @allowed_statuses on a stock installation too --
  # and that is where somebody is most likely to want the panel, because there is
  # nothing else on the form to explain it.
  it 'injects the link at a dead end in the generic workflow, with no scope anywhere' do
    dead_end = issue_statuses(:issue_statuses_005)
    issue = Issue.create!(project: project, tracker: tracker, status: dead_end,
                          author_id: 2, subject: 'deface override spec')

    get :edit, params: { id: issue.id }

    expect(ProjectWorkflowScope.count).to eq(0)
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

  # The path that makes the tracker in the link mean anything. Core's status and
  # tracker selects call updateIssueFrom, which re-posts the form to
  # `update_issue_form_path` -- `edit_issue_path(issue, format: 'js')` for a saved
  # issue -- and re-renders issues/_form from the result. So the link has to come
  # back rebuilt with whatever the reader has just chosen; if it did not, the
  # panel would go on describing the tracker the form no longer shows.
  it 'rebuilds the link when the form is re-rendered for a changed tracker' do
    other_tracker = trackers(:trackers_002)
    project.trackers << other_tracker unless project.trackers.include?(other_tracker)
    issue = Issue.create!(project: project, tracker: tracker, status: new_status,
                          author_id: 2, subject: 'deface override spec')

    patch :edit, params: { id: issue.id, issue: { tracker_id: other_tracker.id } },
                 format: 'js', xhr: true

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("workflow_map?tracker_id=#{other_tracker.id}")
    expect(response.body).not_to include("workflow_map?tracker_id=#{tracker.id}")
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
