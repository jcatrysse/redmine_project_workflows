# frozen_string_literal: true

# The cells of a workflow matrix, and the panel above it.
#
# These are the plugin's versions of two of Redmine's own cell helpers --
# +transition_tag+ and +field_permission_tag+ -- plus three helpers of the
# plugin's own. They are here rather than in a module under +Patches+ because
# since ADR-003 nothing of the plugin is mixed into core's +WorkflowsHelper+:
# the screens that need these cells are the plugin's own, and they reach the
# module through +helper+ in the ordinary way.
#
# Core's workflow controller reaches it that way too, through
# {RedmineProjectWorkflows::Patches::WorkflowsControllerHelperPatch} -- beside
# +WorkflowsHelper+, never inside it. Core's own +workflows/_form+ carries the
# row and column actions of WP5, which are one of the plugin's two surviving
# overrides there, and those call +project_workflow_bulk_actions+.
#
# **Still a copy of core, and still watched as one.** Both cell helpers
# reimplement a body core owns, so
# {RedmineProjectWorkflows::Services::CoreMethodDigest::TARGETS} carries an entry
# for this module against +WorkflowsHelper+ and the drift gate reports it exactly
# as it reports a prepended patch. Moving a copy out of +Patches+ must not move
# it out of the gate (INV-9's sibling reasoning: an unwatched copy is silent).
#
# Named explicitly by every controller that renders these views. Rails'
# include_all_helpers is built from the host application's helper paths and does
# not reach a plugin's app/helpers.
module ProjectWorkflowMatrixHelper
  include RedmineProjectWorkflows::VersionHelper
  # The row and column actions of WP5, which need to agree with the cells about
  # how many workflows one cell stands for -- see #workflow_permissions_matrix_size.
  include RedmineProjectWorkflows::BulkActionsHelper

  # Core's own body, with the matrix size asked of the plugin rather than
  # computed as @roles.size * @trackers.size: a selection here covers projects
  # as well, so a cell can stand for more workflows than core can count.
  def field_permission_tag(permissions, status, field, roles)
    name = field.is_a?(CustomField) ? field.id.to_s : field
    options = [['', ''], [l(:label_readonly), 'readonly']]
    options << [l(:label_required), 'required'] unless field_required?(field)
    html_options = {}

    if (perm = permissions[status.id][name])
      if perm.uniq.size > 1 || perm.size < workflow_permissions_matrix_size
        options << [l(:label_no_change_option), 'no_change']
        selected = 'no_change'
      else
        selected = perm.first
      end
    end

    hidden = field.is_a?(CustomField) &&
             !field.visible? &&
             !roles.detect { |role| role.custom_fields.to_a.include?(field) }

    if hidden
      options[0][0] = l(:label_hidden)
      selected = ''
      html_options[:disabled] = true
    end

    select_tag("permissions[#{status.id}][#{name}]", options_for_select(options, selected), html_options)
  end

  # The project selector above the administration matrices and the summary.
  #
  # Core draws the tracker and role selectors with
  # +WorkflowsHelper#options_for_workflow_select+, and this is the third of the
  # three, drawn to match: an "All" option first, a plain select until more than
  # one thing is chosen and a multiple one after that, and core's own
  # +.expandable+ class so that the toggle beside it works.
  #
  # It cannot *be* core's helper. That one builds its options out of records with
  # +#id+ and +#name+, and the generic workflow is neither a record nor a
  # project -- which is why the plugin used to prepend a normalising wrapper onto
  # +WorkflowsHelper+, and why that wrapper became finding F01 of the 2026-08-28
  # audit: a neighbouring plugin's +alias_method+ chain copies a prepended method
  # and loses its +super+, and both plugins' workflow screens raise. Drawing our
  # own selector on our own screen is what ADR-003 trades that hazard for.
  #
  # 'all' is a value, never an expansion. Putting every project id in the control
  # would put them all in the query string of the redirect after Save and of
  # every scope-action link on the page that came back -- about 11 KB on an
  # installation with 500 projects, which nginx answers with a 414 at its default
  # header buffer (finding F01).
  def project_workflow_project_select_tag(name = 'project_id[]', options = {})
    values = project_workflow_selected_values
    multiple = values.size > 1
    all_options = { value: 'all', selected: @all_selected.present? }
    all_options[:style] = 'display:none;' if multiple
    choices = [[l(:label_project_workflows_global), 'global']] +
              Array(@projects).map { |project| [project.name, project.id.to_s] }

    select_tag(name,
               content_tag('option', l(:label_all), all_options) + options_for_select(choices, values),
               { multiple: multiple }.merge(options))
  end

  # The project selection as it travels in a link or a hidden field, straight
  # from the request.
  #
  # 'all' is carried verbatim and never expanded (finding F01). Expanding it here
  # put every project id in the redirect after Save and in all four scope-action
  # links on the page that came back: roughly 11 KB of query string on an
  # installation with 500 projects, which nginx rejects with a 414 at its default
  # 8 KB header buffer. The controller expands it server-side already.
  #
  # An empty selection is the generic workflow, said explicitly rather than left
  # to a default further down: the hidden fields are the only thing carrying the
  # selection from the selector's form into the save, and a save that carried
  # nothing would silently mean something else than the screen showed.
  def project_workflow_selection_values
    values = Array(params[:project_id]).reject(&:blank?).presence || ['global']
    values.include?('all') ? ['all'] : values
  end

  # The state of the current selection, as text. Three states have to stay
  # tellable apart (INV-3), and "own empty workflow" is a valid, deliberate
  # configuration -- so it is named in words rather than marked as a
  # problem. No colour, and no markup Redmine does not already use.
  def project_workflow_scope_state_tag(state)
    text =
      case state.state
      when :inherits then l(:label_project_workflow_state_inherits)
      when :own then l(:label_project_workflow_state_own)
      when :own_empty then l(:label_project_workflow_state_own_empty)
      else
        # A mixed selection names only the states it actually contains --
        # "0 own empty workflows" is noise, not information.
        {
          label_project_workflow_count_own: state.own,
          label_project_workflow_count_own_empty: state.own_empty,
          label_project_workflow_count_inherits: state.inheriting
        }.reject { |_key, count| count.zero? }
         .map { |key, count| l(key, count: count) }.join(', ')
      end
    content_tag(:span, text, class: "project-workflow-scope-state #{state.state}")
  end

  # One cell of the summary grid. Core builds the link with a bare
  # {:action => 'edit', :role_id => ..., :tracker_id => ...}, which carries
  # no project; on the plugin's own summary the project selection is the whole
  # point of the page, so it travels with the link. The selection is nil when it
  # is the default -- the generic workflow alone -- and the URL then names no
  # project at all.
  def project_workflow_summary_count_link(count, tracker, role, selection)
    url = { action: 'edit', role_id: role, tracker_id: tracker }
    url[:project_id] = selection if selection.present?

    link_to(project_workflows_summary_count_body(count), url,
            title: l(:button_edit),
            class: project_workflows_summary_count_class(count))
  end

  # Core's own body, with two changes: the matrix size (see #field_permission_tag)
  # and the classes on the mixed-value <select>.
  def transition_tag(transition_count, old_status, new_status, name)
    tag_name = "transitions[#{old_status.try(:id) || 0}][#{new_status.id}][#{name}]"
    if old_status == new_status
      check_box_tag(tag_name, '1', true,
                    { :disabled => true,
                      :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}" })
    elsif transition_count.zero? || transition_count == workflow_permissions_matrix_size
      hidden_field_tag(tag_name, '0', :id => nil) +
        check_box_tag(tag_name, '1', transition_count != 0,
                      :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}")
    else
      # The same classes as a checkbox cell (claude F06). Core's own toggle
      # cannot reach a select whatever it is called -- it selects on
      # input[type=checkbox] -- but the plugin's row and column actions
      # select on the class alone, so one selector reaches both kinds of
      # cell and the mixed ones stop being the cells bulk editing skips.
      select_tag(
        tag_name,
        options_for_select(
          [
            [l(:general_text_Yes), '1'],
            [l(:general_text_No), '0'],
            [l(:label_no_change_option), 'no_change']
          ],
          'no_change'
        ),
        :class => "old-status-#{old_status.try(:id) || 0} new-status-#{new_status.id}"
      )
    end
  end

  private

  # What the selector shows as chosen, in the order the option list is built.
  # 'all' stands for itself and for nothing else -- see the caller.
  def project_workflow_selected_values
    return ['all'] if @all_selected.present?

    values = Array(@selected_projects).map { |project| project.id.to_s }
    values.unshift('global') if @global_selected
    values
  end

  # How many workflows one cell of the matrix stands for. Core computes
  # @roles.size * @trackers.size; the plugin adds the scopes the selection
  # covers. Kept under core's name because that is what core's own
  # workflows/_form partial asks for -- the plugin renders it unchanged -- and
  # answered by the module that also renders the row and column actions, so the
  # two can never disagree about the size of a cell.
  def workflow_permissions_matrix_size
    project_workflow_selection_size
  end
end
