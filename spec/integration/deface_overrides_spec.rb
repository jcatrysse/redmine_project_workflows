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
INV9_COUNTS = { overrides: 15, files: 12 }.freeze

# F08. INV-9 says there are fifteen overrides in twelve files, and three places
# write that down -- CLAUDE.md, docs/design.md and the comment below. The suite
# asserts each of the fifteen against the rendered page with an assertion only
# that one can satisfy, and asserted the *count* nowhere: a sixteenth override
# added without an assertion passed every gate, silently, which is the exact
# shape INV-9 exists to prevent.
#
# This is a speed bump, and it should be described as one rather than as a proof.
# It cannot tell that override sixteen has an assertion; what it does is turn a
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
  # grepping the file for `name:`. A plain grep finds seventeen in fifteen
  # overrides, because two of the overrides render form fields whose own markup
  # carries `name: 'source_project_id'` and `name: 'target_project_ids[]'` -- and
  # a gate that counted those would have been wrong in the direction that hides a
  # missing override.
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
  # "fifteen" beside a constant reading sixteen is how INV-9 stopped being
  # believable the last three times a count in this repository drifted.
  it 'is the count CLAUDE.md and docs/design.md write down' do
    root = File.expand_path('../..', __dir__)
    words = { 15 => 'fifteen', 12 => 'twelve' }

    [File.read("#{root}/CLAUDE.md"), File.read("#{root}/docs/design.md")].each do |document|
      expect(document.downcase).to include(words.fetch(INV9_COUNTS[:overrides]))
      expect(document.downcase).to include(words.fetch(INV9_COUNTS[:files]))
    end
  end
end

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

  # What the *matrix* form will submit. The selector above it is a <select> of
  # the same name, so only the hidden inputs answer "what does Save carry".
  def hidden_project_values(body)
    body.scan(/<input\b[^>]*>/).filter_map do |tag|
      next unless tag.include?('type="hidden"') && tag.include?('name="project_id[]"')

      tag[/value="([^"]*)"/, 1]
    end
  end

  # Redmine 5.1 draws icons from CSS classes; 6.0 and later from SVG sprites.
  # Wherever the plugin renders markup core also renders, it has to match
  # whichever the host under test uses.
  def core_renders_sprites?
    ApplicationController.helpers.respond_to?(:sprite_icon)
  end

  # F16. The copy screen's two project labels had no `for` and did not wrap
  # their select, so a screen reader read the option list with no field name --
  # on the one screen where the two selects differ only in which is the source
  # and which the target, and where getting them the wrong way round deletes a
  # workflow. Asserted on the rendered page rather than on the partial, because
  # the ids come from the two render sites.
  it 'associates each label on the copy screen with its own select' do
    get :copy

    expect(response).to have_http_status(:ok)
    ids = css_select('select#project_id_source, select#project_id_target').map { |node| node['id'] }
    expect(ids).to contain_exactly('project_id_source', 'project_id_target')
    ids.each do |id|
      expect(css_select("label[for='#{id}']")).not_to be_empty, "no label is associated with ##{id}"
    end
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

  # F01. The hidden fields are the only thing that carries the project
  # selection from the selector form into the matrix form -- core puts the two
  # in separate `form_tag` blocks on all three supported versions -- and they
  # used to expand 'all' into every project id. The selection then stopped
  # being 'all' for the rest of the session: the redirect after Save carried
  # every id (an 8-10 KB Location header on a large installation, which nginx
  # rejects with a 414 at its default buffer size), and so did all four
  # scope-action links on the page that came back. The scope panel four files
  # away has kept the keyword verbatim since WP1 and is asserted to; these are
  # the same rule applied to the form that saves.
  it 'keeps the whole-selection keyword in the transitions save form' do
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         project_id: ['all'], used_statuses_only: '0' }

    expect(response).to have_http_status(:ok)
    expect(hidden_project_values(response.body)).to eq(['all'])
  end

  it 'keeps the whole-selection keyword in the field permissions save form' do
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                project_id: ['all'], used_statuses_only: '0' }

    expect(response).to have_http_status(:ok)
    expect(hidden_project_values(response.body)).to eq(['all'])
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

    # The grid below the panel shows what the selection *stores*, so a project
    # that inherits renders as an empty matrix -- which reads as "nothing is
    # permitted here" and is the opposite of the truth. The panel is the only
    # place that can say so, and it also has to say that Save will not change
    # such a combination, because it no longer does.
    it 'says why the grid is empty for a combination that inherits' do
      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t(:text_project_workflow_scope_inheriting_note, count: 1))
      )
    end

    it 'says nothing of the kind once the project has taken the combination over' do
      give_own_workflow(project, tracker, role)

      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(response.body).not_to include(
        ERB::Util.html_escape(I18n.t(:text_project_workflow_scope_inheriting_note, count: 1))
      )
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
