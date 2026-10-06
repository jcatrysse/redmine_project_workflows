# frozen_string_literal: true

module RedmineProjectWorkflows
  # Which tracker and which roles the workflow drawing is asked for (WP9).
  #
  # The one selection on ProjectWorkflowsController that is a *list*: the two
  # matrices edit a single tracker and a single role, and the drawing describes
  # several roles at once. Both finders intersect a request parameter with a list
  # built from the project and never query on the parameter itself (INV-7) --
  # Project.where(id: ['1e5']) resolves to project 1, so the shape of an id is
  # not something to rely on.
  #
  # Included into ProjectWorkflowsController, which is why every method here is
  # **private**: every public instance method of a controller is an action, so a
  # public method here would be routable and unauthorized (CLAUDE.md's
  # forbidden-constructs table). The same reason MatrixParams and
  # MatrixReporting give.
  module GraphSelection
    private

    # The drawing's selection: one tracker, and one or more roles out of the very
    # list the settings tab and the matrix offer (answer B of 2026-08-28 -- every
    # role the project screen already lists, not only the reader's own).
    #
    # A role the project does not offer, or a tracker it has not enabled, answers
    # 404 rather than drawing something else: silently narrowing a selection to
    # what happens to be allowed would draw one workflow under the heading of
    # another.
    def find_tracker_and_roles
      return if performed?

      options = RedmineProjectWorkflows::Services::ProjectOptions
      @tracker = options.trackers(@project).detect { |tracker| tracker.id.to_s == params[:tracker_id].to_s }
      return render_404 if @tracker.nil?

      @visible_roles = options.visible_roles(@project)
      # WP18: the one resolver, against the offered list, so no shape of a
      # parameter reaches a query and everything the request named that the
      # project does not offer is reported rather than dropped.
      selection = RedmineProjectWorkflows::Services::ExactSelection.resolve(
        params[:role_id], candidates: @visible_roles
      )
      # 404 where the request named something the project does not offer, and that
      # means *anything* it named, not merely all of it. Answering only on an empty
      # result made `role_id[]=<offered>&role_id[]=999999` render the offered role
      # under a heading that claims both, which is the silent narrowing the comment
      # above says does not happen (finding F05 of 2026-08-28-claude-audit, found
      # by the ChatGPT review Jan commissioned).
      #
      # A project that offers *no* role at all -- nobody is a member of it, and no
      # scope brought one in -- is not a missing page, and the screen says so in
      # the same sentence the settings tab uses for the same state. That is why the
      # empty-result case still asks whether anything was on offer.
      return render_404 unless selection.exact?

      @roles = selection.records.presence || own_roles
      render_404 if @roles.empty? && @visible_roles.any?
    end

    # What is drawn when the request asked for no role at all: the reader's own
    # roles, which is the union the status dropdown on an issue of theirs is
    # built from and therefore the answer to "what may I do". A reader who holds
    # none -- an administrator, or somebody with the permission through a group
    # -- gets the whole list rather than an empty drawing.
    def own_roles
      return [] if @visible_roles.empty?

      own = User.current.roles_for_project(@project).to_set(&:id)
      @visible_roles.select { |role| own.include?(role.id) }.presence || @visible_roles
    end
  end
end
