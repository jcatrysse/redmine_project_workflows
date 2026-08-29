# frozen_string_literal: true

require_relative '../../spec_helper'

# What the plugin's four administration screens actually render (WP12, ADR-003).
#
# Every example here was a Deface-override assertion until WP12: the project
# selector, the hidden fields that carry the selection into a save, the scope
# panel, the note above the matrix, the counter and the undo, and the summary
# page's cells all reached core's views through an anchor, and INV-9 asserted
# each one against the rendered page because an unmatched anchor is silent.
#
# They are not INV-9 assertions any more -- these are the plugin's own views,
# and a view that stops rendering something raises or shows a diff rather than
# failing silently. They moved rather than being deleted because what they
# assert is the screen, not the mechanism: the selection has to survive a save,
# an inheriting combination has to say why its grid is empty, and a cell that
# stands for forty workflows has to say so before somebody clicks it.
#
# Driven through the controller with `render_views` rather than as `type: :view`
# specs: three of the four screens need @statuses, @projects, the scope state and
# the selection flags, and assembling those by hand would assert the assembly
# rather than the screen.
describe ProjectWorkflowRulesController, type: :controller do
  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules

  before { @request.session[:user_id] = 1 }

  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:project) { projects(:projects_001) }

  # Redmine 5.1 draws icons from CSS classes; 6.0 and later from SVG sprites.
  # Wherever the plugin renders markup core also renders, it has to match
  # whichever the host under test uses. Asks the production predicate rather than
  # restating its condition -- finding F02 of
  # 2026-08-28-claude-plugin-compat-5.1.
  def core_renders_sprites?
    RedmineProjectWorkflows::VersionHelper.core_sprite_icons?
  end

  def get_transitions(params = {})
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         used_statuses_only: '0' }.merge(params)
  end

  def get_permissions(params = {})
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id] }.merge(params)
  end

  # What the *matrix* form will submit. The selector above it is a <select> of
  # the same name, so only the hidden inputs answer "what does Save carry".
  def hidden_project_values(body)
    body.scan(/<input\b[^>]*>/).filter_map do |tag|
      next unless tag.include?('type="hidden"') && tag.include?('name="project_id[]"')

      tag[/value="([^"]*)"/, 1]
    end
  end

  describe 'the project selector' do
    it 'is on the transitions page, with the generic workflow named in it' do
      get_transitions

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="project_id"')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflows_global)))
    end

    it 'is on the field permissions page' do
      get_permissions

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="project_id"')
    end

    it 'is on the summary page' do
      get :index

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="project_id"')
    end

    # WP0 / claude F04. Since Redmine 6.0 core renders sprite_icon('') inside
    # every .toggle-multiselect span, and toggleMultiSelectIconInit() calls
    # updateSVGIcon($(this).find('svg')[0], iconType) for each of them. A span
    # without an <svg> makes that argument undefined, getElementsByTagName
    # raises, and because the call sits inside $(document).ready every
    # initialisation registered after it is skipped. Redmine 5.1 has no
    # sprite_icon at all and core's own spans are empty there, so the plugin's
    # span has to match whatever core does on the host it is running on.
    #
    # Three spans on this page: core's own two, drawn by `options_for_workflow_select`
    # from a view of the plugin's, and the plugin's own beside the project
    # selector.
    it 'carries the toggle core draws beside its own two' do
      get_transitions
      spans = response.body.scan(%r{<span class="toggle-multiselect[^"]*">(.*?)</span>}m).flatten

      expect(spans.size).to eq(3)
      if core_renders_sprites?
        expect(spans).to all(include('<svg'))
      else
        expect(spans).to all(satisfy { |inner| inner.exclude?('<svg') })
      end
    end
  end

  # F01. The hidden fields are the only thing that carries the project selection
  # from the selector's form into the matrix form -- the two are separate
  # `form_tag` blocks, as they are on core's screens -- and they must never
  # expand 'all' into every project id. The selection would then stop being
  # 'all' for the rest of the session: the redirect after Save would carry every
  # id (an 8-10 KB Location header on a large installation, which nginx rejects
  # with a 414 at its default buffer size), and so would all four scope-action
  # links on the page that came back.
  describe 'the hidden fields that carry the selection into a save' do
    it 'are on the transitions page' do
      get_transitions(project_id: ['global'])

      expect(hidden_project_values(response.body)).to eq(['global'])
    end

    it 'are on the field permissions page' do
      get_permissions(project_id: ['global'])

      expect(hidden_project_values(response.body)).to eq(['global'])
    end

    it 'keep the whole-selection keyword on the transitions page' do
      give_own_workflow(project, tracker, role)

      get_transitions(project_id: ['all'])

      expect(hidden_project_values(response.body)).to eq(['all'])
    end

    it 'keep the whole-selection keyword on the field permissions page' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      get_permissions(project_id: ['all'])

      expect(hidden_project_values(response.body)).to eq(['all'])
    end
  end

  # WP1 / INV-3. The scope panel renders only when the selection contains at
  # least one real project: the generic workflow has no scope.
  describe 'the scope panel' do
    it 'reaches the transitions page when a project is selected' do
      get_transitions(project_id: [project.id.to_s])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('project-workflow-scope')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_inherits)))
      expect(response.body).to include('project_workflow_scopes')
    end

    it 'reaches the field permissions page when a project is selected' do
      get_permissions(project_id: [project.id.to_s])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('project-workflow-scope')
      expect(response.body).to include('project_workflow_scopes')
    end

    it 'offers the two enable actions while the project inherits' do
      get_transitions(project_id: [project.id.to_s])

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_empty)))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inherit)))
    end

    # The grid below the panel shows what the selection *stores*, so a project
    # that inherits renders as an empty matrix -- which reads as "nothing is
    # permitted here" and is the opposite of the truth. The panel is the only
    # place that can say so, and it also has to say that Save will not change
    # such a combination, because it does not (INV-3).
    it 'says why the grid is empty for a combination that inherits' do
      get_transitions(project_id: [project.id.to_s])

      expect(response.body).to include(
        ERB::Util.html_escape(I18n.t(:text_project_workflow_scope_inheriting_note, count: 1))
      )
    end

    it 'says nothing of the kind once the project has taken the combination over' do
      give_own_workflow(project, tracker, role)

      get_transitions(project_id: [project.id.to_s])

      expect(response.body).not_to include(
        ERB::Util.html_escape(I18n.t(:text_project_workflow_scope_inheriting_note, count: 1))
      )
    end

    it 'offers the empty and inherit actions once the project has a scope' do
      give_own_workflow(project, tracker, role)

      get_transitions(project_id: [project.id.to_s])

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_own_empty)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_clear)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inherit)))
    end

    # 'all' has to stay 'all' in the action links: expanding it would put every
    # project id in the URL.
    it 'keeps the whole-selection keyword in its links' do
      give_own_workflow(project, tracker, role)

      get_transitions(project_id: ['all'])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('project-workflow-scope')
      expect(response.body).to match(/project_workflow_scopes\?[^"']*project_id(%5B%5D|\[\])=all/)
    end

    it 'stays out of the way when only the generic workflow is selected' do
      get_transitions(project_id: ['global'])

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('project-workflow-scope')
    end
  end

  # WP3. The summary is a grid of trackers and roles counting whichever workflow
  # the selector names, and every count is a link into the matrix that counted
  # it -- so the link has to carry the selection, or the page would show one
  # workflow's numbers and open another's.
  describe 'the summary page' do
    it 'carries the selected project into every count link' do
      give_own_workflow(project, tracker, role)

      get :index, params: { project_id: [project.id.to_s] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to match(
        %r{href="[^"]*/project_workflow_rules/edit\?[^"]*project_id(%5B%5D|\[\])=#{project.id}}
      )
    end

    it 'names no project in the links when the selection is the generic workflow' do
      get :index

      expect(response.body).to match(%r{href="[^"]*/project_workflow_rules/edit\?[^"]*role_id=})
      expect(response.body).not_to match(%r{href="[^"]*/project_workflow_rules/edit\?[^"]*project_id})
    end

    # The count cells are the plugin's markup rather than core's, so an empty one
    # has to look the way core's does on the host it is running on: 5.1
    # substitutes an icon-not-ok span for a zero, 6.0 and later colour the number.
    it 'marks an empty cell the way the host does' do
      get :index
      cell = response.body[%r{<a title="#{I18n.t(:button_edit)}".*?</a>}m]

      expect(cell).to be_present
      if core_renders_sprites?
        expect(cell).to include('decoration-red')
      else
        expect(cell).to include('icon-not-ok')
      end
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
  end

  # The area's own action bar, on all four screens, and the second of ADR-003's
  # two cross-links: the plugin's screens point back at Redmine's own.
  describe 'the action bar' do
    it 'links to the inventory and across to Redmine\'s own workflow screens' do
      get_transitions

      expect(css_select('div.contextual a[href="/project_workflow_inventories"]')).to be_present
      expect(css_select('div.contextual a[href^="/workflows/edit"]')).to be_present
    end

    it 'leaves out the link to the screen you are already on' do
      get :index

      expect(css_select('div.contextual a[href="/project_workflow_rules"]')).to be_empty
      expect(css_select('div.contextual a[href="/project_workflow_rules/copy"]')).to be_present
    end

    # WP19, finding F07. The diagnostics page gave up its entry in Redmine's
    # administration menu -- ADR-003 costed one -- and is reached from here
    # instead, on all four screens: somebody who has just been told the host has
    # drifted is standing on one of them.
    it 'links to the diagnostics page from every screen of the area' do
      get_transitions
      expect(css_select('div.contextual a[href="/project_workflow_diagnostics"]')).to be_present

      get :index
      expect(css_select('div.contextual a[href="/project_workflow_diagnostics"]')).to be_present

      get :copy
      expect(css_select('div.contextual a[href="/project_workflow_diagnostics"]')).to be_present
    end
  end

  # WP5 / claude F06. The row and column actions come from the two Deface
  # overrides on core's own workflows/_form, which the plugin renders unchanged
  # -- so they are asserted as overrides in spec/integration/deface_overrides_spec.rb.
  # What is asserted here is that they arrive on *this* screen too, which is what
  # RedmineProjectWorkflows::Patches::WorkflowsControllerHelperPatch's sibling --
  # this controller's own `helper ProjectWorkflowMatrixHelper` -- is for.
  it 'renders the row and column actions on its own transitions matrix' do
    get_transitions

    expect(response.body).to include(
      'data-project-workflow-target="table.transitions-always .old-status-0:not(:disabled)"'
    )
    expect(response.body.scan('function projectWorkflowBulkApply').size).to eq(1)
  end

  # WP5. How much one cell stands for, and what "no change" means, above the
  # matrix. It says something only when a cell stands for more than one workflow
  # -- which is the case core's own no-change cells appear in.
  describe 'the note above the matrix' do
    def escaped(key)
      ERB::Util.html_escape(I18n.t(key, no_change: I18n.t(:label_no_change_option)))
    end

    it 'says how many workflows one cell stands for' do
      get_transitions(tracker_id: [tracker.id, other_tracker.id])

      sentence = I18n.t(:text_project_workflow_bulk_selection,
                        count: 2, trackers: 2, roles: 1, scopes: 1)

      expect(response.body).to include(ERB::Util.html_escape(sentence))
      expect(response.body).to include(escaped(:text_project_workflow_bulk_legend))
      expect(response.body).to include(escaped(:text_project_workflow_bulk_legend_actions))
    end

    it 'stays quiet when a cell is one workflow' do
      get_transitions

      expect(response.body).not_to include('project-workflow-bulk-note')
    end

    # Core renders "no change" cells on the field permissions page too, so the
    # sentence explaining them belongs there -- but that page has no row or
    # column actions, so the sentence about those must not follow it there.
    it 'reaches the field permissions page, without explaining a control it has not got' do
      get_permissions(tracker_id: [tracker.id, other_tracker.id])

      expect(response.body).to include('project-workflow-bulk-note')
      expect(response.body).to include(escaped(:text_project_workflow_bulk_legend))
      expect(response.body).not_to include(escaped(:text_project_workflow_bulk_legend_actions))
      expect(response.body).not_to include('project-workflow-bulk-action')
    end
  end

  # WP13, audit finding F09. A workflow written for an archived project governs
  # nothing -- nobody but an administrator can reach it and no issue in it can be
  # created or edited -- so offering one on a screen whose whole purpose is to
  # decide what to write is noise. Core's own project pickers scope to visible or
  # active projects; `Project.sorted` carries no status predicate at all.
  #
  # Only what is *offered* narrows, which is the half that matters: an id in the
  # request is still resolved, so the inventory's link into an archived project's
  # matrix goes on working.
  describe 'an archived project' do
    let(:archived) { projects(:projects_002) }

    before { archived.update!(status: Project::STATUS_ARCHIVED) }

    # Scoped to the control, not to the page: a project id is also a tracker id
    # and a role id, so a bare `include('value="2"')` over the whole body is
    # satisfied by markup that has nothing to do with this.
    def option_values(body, name)
      block = body[%r{<select\b[^>]*name="#{Regexp.escape(name)}"[^>]*>.*?</select>}m]
      block.to_s.scan(/<option[^>]*value="([^"]*)"/).flatten
    end

    it 'is not offered by the matrix selector' do
      get_transitions

      values = option_values(response.body, 'project_id[]')
      expect(values).to include(project.id.to_s)
      expect(values).not_to include(archived.id.to_s)
    end

    it 'is not offered by either of the copy form\'s project selectors' do
      get :copy, params: { source_tracker_id: tracker.id, source_role_id: role.id }

      expect(option_values(response.body, 'source_project_id')).not_to include(archived.id.to_s)
      expect(option_values(response.body, 'target_project_ids[]')).not_to include(archived.id.to_s)
    end

    # The link the inventory builds names the id, and it still opens: this is
    # what stops "not offered" from becoming "unreachable", which would leave an
    # archived project's own workflow with nowhere at all to remove it from.
    it 'still opens its own matrix when a request names it' do
      give_own_workflow(archived, tracker, role)

      get_transitions(project_id: [archived.id.to_s])

      expect(response).to have_http_status(:ok)
      expect(assigns(:selected_projects).map(&:id)).to eq([archived.id])
    end
  end

  # WP13, audit finding F08. The Save button asks before it rewrites more workflow
  # rules than the plugin setting allows, and the script that asks has to be on
  # the page for it to.
  describe 'the confirmation in front of Save' do
    def form_tag_in(body)
      body[/<form\b[^>]*id="workflow_form"[^>]*>/]
    end

    it 'carries the multiplier, the threshold and the question on the transitions form' do
      get_transitions(tracker_id: [tracker.id, other_tracker.id])

      form = form_tag_in(response.body)
      expect(form).to include('onsubmit="return projectWorkflowConfirmSave(this);"')
      expect(form).to include('data-project-workflow-multiplier="2"')
      expect(form).to include(%(data-project-workflow-threshold="#{
        RedmineProjectWorkflows::Services::WriteBudget::DEFAULT_SAVE_CONFIRM_THRESHOLD}"))
      expect(form).to include('data-project-workflow-save-confirm=')
    end

    # The Save button's threshold, not the row and column actions'. They shared
    # one until the write path was measured on 2026-08-29, and at 50 rules the
    # dialog fired on essentially every multi-workflow save.
    it 'does not use the row and column actions\' threshold' do
      Setting.plugin_redmine_project_workflows = { 'bulk_confirm_threshold' => '7',
                                                   'bulk_save_confirm_threshold' => '4321' }

      get_transitions(tracker_id: [tracker.id, other_tracker.id])

      expect(form_tag_in(response.body)).to include('data-project-workflow-threshold="4321"')
      # The row and column actions still carry theirs, on their own element.
      expect(response.body).to include('data-project-workflow-threshold="7"')
    ensure
      Setting.clear_cache
    end

    # The half that was missing in the first draft: the field permissions matrix
    # has no row or column actions, so nothing on it used to render the script --
    # and the handler would have called a function that is not there.
    it 'carries the same attributes on the field permissions form' do
      get_permissions(tracker_id: [tracker.id, other_tracker.id])

      form = form_tag_in(response.body)
      expect(form).to include('onsubmit="return projectWorkflowConfirmSave(this);"')
      expect(form).to include('data-project-workflow-multiplier="2"')
    end

    it 'puts the script on both pages, once each' do
      get_transitions
      expect(response.body.scan('function projectWorkflowConfirmSave').size).to eq(1)

      get_permissions
      expect(response.body.scan('function projectWorkflowConfirmSave').size).to eq(1)
    end
  end

  # WP6. What the last row or column action did, and a way back. Unlike the note
  # above it, this does not wait for a cell to stand for more than one workflow:
  # the actions are there whatever the size of the selection, and so is the cost
  # of clicking one by accident.
  describe 'the counter and the undo above the matrix' do
    it 'is on the transitions page for a selection of one workflow per cell' do
      get_transitions

      expect(response.body).to include('id="project-workflow-bulk-undo"')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_bulk_undo)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_bulk_unsaved)))
      # The two sentences the script fills in come down as data attributes, so
      # every string on the page stays in the locale files.
      expect(response.body).to include('data-project-workflow-changed')
      expect(response.body).to include('data-project-workflow-undone')
    end

    it 'is on the transitions page for a wide selection too' do
      get_transitions(tracker_id: [tracker.id, other_tracker.id])

      expect(response.body).to include('id="project-workflow-bulk-undo"')
    end

    # No row or column actions there, so nothing for a counter to count or an
    # undo to undo.
    it 'is absent from the field permissions page' do
      get_permissions(tracker_id: [tracker.id, other_tracker.id])

      expect(response.body).to include('project-workflow-bulk-note')
      expect(response.body).not_to include('id="project-workflow-bulk-undo"')
    end
  end

  # F16. The copy screen's two project labels had no `for` and did not wrap their
  # select, so a screen reader read the option list with no field name -- on the
  # one screen where the two selects differ only in which is the source and which
  # the target, and where getting them the wrong way round deletes a workflow.
  # Asserted on the rendered page rather than on the partial, because the ids
  # come from the two render sites.
  describe 'the copy screen' do
    it 'offers both project selectors' do
      get :copy

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="source_project_id"')
      expect(response.body).to include('name="target_project_ids[]"')
    end

    it 'associates each label with its own select' do
      get :copy

      ids = css_select('select#project_id_source, select#project_id_target').map { |node| node['id'] }
      expect(ids).to contain_exactly('project_id_source', 'project_id_target')
      ids.each do |id|
        expect(css_select("label[for='#{id}']")).not_to be_empty, "no label is associated with ##{id}"
      end
    end

    it 'offers "same as the target" on the source, and no multiselect toggle' do
      get :copy

      expect(response.body).to include("--- #{ERB::Util.html_escape(I18n.t(:label_copy_same_as_target))} ---")
      expect(response.body).to include('multiple="multiple"')
      expect(response.body).not_to include('toggle-multiselect')
    end

    # Finding C01, answered B by Jan on 2026-08-26. A multiple select with
    # nothing selected submits no parameter at all, so a form that showed nothing
    # in the target project control still copied into the generic workflow -- and
    # said so nowhere. The generic workflow is preselected there now, so what runs
    # is what the form shows.
    describe 'the target project control' do
      # Which values a control has selected, read off the markup rather than
      # matched against it: Rails writes `selected` before `value` in one helper
      # and after it in the other, so an assertion naming both in one string
      # passes or fails on which helper drew the option.
      def selected_in(selector_id)
        select = response.body[%r{<select[^>]*id="#{selector_id}".*?</select>}m].to_s
        select.scan(/<option[^>]*>/)
              .select { |option| option.include?('selected') }
              .map { |option| option[/value="([^"]*)"/, 1] }
      end

      it 'preselects the generic workflow when nothing is selected' do
        get :copy

        expect(selected_in('project_id_target')).to eq(['global'])
      end

      # Blank on the source already means the generic workflow and destroys
      # nothing, and the source tracker and role beside it are blank-by-default
      # too -- that is core's own convention for "not chosen yet".
      it 'leaves the source control alone' do
        get :copy

        expect(selected_in('project_id_source')).to eq([''])
      end

      it 'keeps a submitted selection instead of adding the generic workflow to it' do
        get :copy, params: { target_project_ids: [project.id.to_s] }

        expect(selected_in('project_id_target')).to eq([project.id.to_s])
      end
    end
  end

  # The two matrices are tabs of one screen, and the selection travels between
  # them: switching matrix keeps the workflow, the trackers and the roles you
  # were looking at.
  describe 'the tabs' do
    it 'carry the selection from one matrix to the other' do
      give_own_workflow(project, tracker, role)

      get_transitions(project_id: [project.id.to_s])

      expect(response.body).to match(
        %r{href="[^"]*/project_workflow_rules/permissions\?[^"]*project_id(%5B%5D|\[\])=#{project.id}}
      )
    end
  end
end
