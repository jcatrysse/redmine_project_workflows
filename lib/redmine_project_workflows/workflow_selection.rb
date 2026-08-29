# frozen_string_literal: true

module RedmineProjectWorkflows
  # How a request to a workflow administration screen names projects, and what
  # that resolves to.
  #
  # The vocabulary every one of those actions shares. Each answers the same
  # questions -- which projects did the request name, and which project ids does
  # the query carry (INV-4) -- and none of them may reach params for a project id
  # itself.
  #
  # Not under +Patches+ since ADR-003: this is the plugin's own controller code,
  # mixed into the plugin's own controller. It was written when those actions
  # lived inside a patch on core's WorkflowsController, which is the only reason
  # it was ever filed there.
  #
  # Nothing here renders except +invalid_selection?+, and that is
  # deliberately a predicate the *action* returns on rather than a before_action:
  # a callback that renders answers before the action can decide, and on core's
  # own controller it answered before anyone had checked who was asking
  # (finding G01).
  module WorkflowSelection
    # The parameters the plugin's administration screens read a project from.
    PROJECT_PARAM_KEYS = %i[project_id target_project_ids source_project_id].freeze
    # The two non-numeric values the matrix selector accepts.
    PROJECT_KEYWORDS = %w[global all].freeze

    # Everything below is private: the module is mixed into a controller, and
    # a public instance method there is an action.
    private

    # Whether this request is one the plugin has to handle itself.
    #
    # It reads the parameters, not the resolved project list: selecting only
    # the generic workflow resolves to an empty list of projects, and falling
    # through to core there makes `duplicate` copy generic to generic and
    # ignore the chosen source project entirely.
    def project_context?
      PROJECT_PARAM_KEYS.any? { |key| Array.wrap(params[key]).any?(&:present?) }
    end

    # Resolves the matrix selector. Values are 'global' (the generic
    # workflow), 'all', or project ids; anything else, and any id that does
    # not exist, is recorded for the caller to report. Nothing is rendered
    # here: render_404 renders and returns false rather than aborting, so the
    # decision belongs where the action can return straight after it.
    #
    # WP18: resolved through Services::ExactSelection, the one resolver the
    # plugin's screens share. Against a *relation* rather than the offered list,
    # which is this selector's one difference from the others -- only what is
    # offered narrows, and a link from the inventory into an archived project's
    # matrix has to go on working (WP13, audit F09). The shape check happens
    # before the relation, which is what keeps `project_id=1e5` from resolving
    # to project 1.
    def load_project_options
      @projects = RedmineProjectWorkflows::Services::ProjectOptions.selectable
      selection = RedmineProjectWorkflows::Services::ExactSelection.resolve(
        params[:project_id], scope: Project.sorted, keywords: PROJECT_KEYWORDS
      )
      record_unresolved(selection)

      @all_selected = selection.keyword?('all')
      # Global is selected when explicitly chosen, when 'all' is selected,
      # or when no project params are provided (default Redmine behavior).
      @global_selected = selection.keyword?('global') || selection.records.empty? || @all_selected

      @selected_projects = @all_selected ? @projects : selection.records
      @projects_for_update = @selected_projects
      # Only for a selection that named one project: 'all' on an installation
      # that happens to have a single project is still a whole-installation
      # selection, and @project drives the layout.
      @project = @selected_projects.first if !@all_selected && @selected_projects.one?
    end

    # The copy form's target selector, which is a different control from the
    # matrix selector above and accepts a different set of values: 'global'
    # or a project id, never 'all'. Returns the ids to write to -- nil for
    # the generic workflow -- and the values that were rejected, de-duplicated
    # and resolved in one query.
    def validated_target_project_ids
      selection = RedmineProjectWorkflows::Services::ExactSelection.resolve(
        params[:target_project_ids], scope: Project, keywords: %w[global]
      )
      resolved = selection.ids
      resolved.unshift(nil) if selection.keyword?('global')
      [resolved, selection.unresolved]
    end

    def selected_projects
      @projects_for_update || []
    end

    def selected_project_ids
      ids = selected_projects.map(&:id)
      ids << nil if @global_selected
      ids
    end

    # What the summary page's count links carry over. Nil when the selection
    # is the default -- the generic workflow and nothing else -- so that an
    # administrator who does not use the plugin gets exactly core's URL.
    def summary_selection_param_values
      return nil if @global_selected && !@all_selected && selected_projects.empty?

      selected_project_param_values
    end

    def selected_project_param_values
      return ['all'] if @all_selected

      values = selected_projects.map(&:id)
      values.unshift('global') if @global_selected
      values
    end

    # The population the matrix screens read. Without plugin parameters that
    # is the generic workflow alone, which is what core shows -- but stated
    # as an explicit predicate rather than left out (INV-4).
    def workflow_project_ids
      project_context? ? selected_project_ids : [nil]
    end

    # Everything the request named that no record answered, from every selector
    # on the screen -- projects, trackers, roles. One list, because one answer:
    # a request that named something that does not exist is refused before any
    # of it is written, and *which* selector held the bad value does not change
    # that (WP18, finding F03).
    def record_unresolved(*selections)
      @unresolved_selection_ids ||= []
      @unresolved_selection_ids += selections.compact.flat_map(&:unresolved)
    end

    # Renders the 404 and says so, for an action to return on. Every caller
    # runs after `require_admin`, which is the whole point.
    def invalid_selection?
      return false if @unresolved_selection_ids.blank?

      render_404
      true
    end
  end
end
