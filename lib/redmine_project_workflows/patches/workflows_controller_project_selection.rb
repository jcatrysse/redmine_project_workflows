# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # How a request to the workflow screens names projects, and what that
    # resolves to.
    #
    # Split out of WorkflowsControllerPatch, which is a set of replaced core
    # actions; this is the vocabulary those actions share. Every one of them
    # answers the same three questions -- is this a plugin request at all, which
    # projects did it name, and which project ids does the query carry (INV-4)
    # -- and none of them may reach params for a project id itself.
    #
    # Nothing here renders except +invalid_project_selection?+, and that is
    # deliberately a predicate the *action* returns on: core declares its
    # finders before +require_admin+, so a before_action that renders answers
    # before anyone has checked who was asking (finding G01).
    module WorkflowsControllerProjectSelection
      # The parameters the plugin adds to core's workflow screens.
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
      # not exist, is collected in @invalid_project_ids for the caller to
      # report. Nothing is rendered here: render_404 renders and returns false
      # rather than aborting, so the decision belongs where the action can
      # return straight after it.
      def load_project_options
        @projects = Project.sorted
        values = Array.wrap(params[:project_id]).reject(&:blank?).map(&:to_s).uniq
        @invalid_project_ids = values.reject { |value| project_id_value?(value) }
        project_ids = values - @invalid_project_ids

        @all_selected = project_ids.delete('all').present?
        # Global is selected when explicitly chosen, when 'all' is selected,
        # or when no project params are provided (default Redmine behavior).
        @global_selected = project_ids.delete('global').present? || project_ids.empty? || @all_selected

        @selected_projects = resolve_selected_projects(project_ids)
        @projects_for_update = @selected_projects
        # Only for a selection that named one project: 'all' on an installation
        # that happens to have a single project is still a whole-installation
        # selection, and @project drives the layout.
        @project = @selected_projects.first if !@all_selected && @selected_projects.one?
      end

      # The projects the selector named, in the order the selector lists them.
      # An id that does not resolve joins @invalid_project_ids rather than being
      # dropped, so that the action can answer 404 instead of silently showing a
      # different selection from the one that was asked for.
      def resolve_selected_projects(project_ids)
        return @projects if @all_selected
        return [] if project_ids.blank?

        selected = Project.where(id: project_ids).sorted.to_a
        @invalid_project_ids += project_ids - selected.map { |project| project.id.to_s }
        selected
      end

      def project_id_value?(value)
        PROJECT_KEYWORDS.include?(value) || value.match?(/\A\d+\z/)
      end

      # The copy form's target selector, which is a different control from the
      # matrix selector above and accepts a different set of values: 'global'
      # or a project id, never 'all'. Returns the ids to write to -- nil for
      # the generic workflow -- and the values that were rejected, de-duplicated
      # and resolved in one query.
      def validated_target_project_ids
        values = Array.wrap(params[:target_project_ids]).reject(&:blank?).map(&:to_s).uniq
        invalid, valid = values.partition { |value| value != 'global' && !value.match?(/\A\d+\z/) }
        global = valid.delete('global').present?

        existing_ids = valid.empty? ? [] : Project.where(id: valid).pluck(:id)
        invalid += valid - existing_ids.map(&:to_s)

        resolved = existing_ids
        resolved.unshift(nil) if global
        [resolved, invalid]
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

      # Renders the 404 and says so, for an action to return on. Every caller
      # runs after `require_admin`, which is the whole point.
      def invalid_project_selection?
        return false if @invalid_project_ids.blank?

        render_404
        true
      end
    end
  end
end
