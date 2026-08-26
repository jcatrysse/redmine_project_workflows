# frozen_string_literal: true

# The workflow governing one issue, on the issue form (WP8).
#
# Redmine's status dropdown lists what may be done and says nothing about why,
# and with per-project workflows that gap gets worse rather than better: two
# projects on the same tracker now offer different choices. This is the screen
# behind the link beside that dropdown -- what the workflow allows from here,
# what leads here, and which of the three states of INV-3 the project is in for
# each of the reader's roles.
#
# **It needs no permission of its own.** It reveals the workflow governing an
# issue the reader is already looking at, so the authorization is the issue's
# own: Issue.visible for a saved one, and the project plus +add_issues+ for the
# new-issue form, where there is no issue yet. Nothing here writes, and the two
# screens the panel links to authorize again for themselves (INV-7).
#
# Deliberately not an action on ProjectWorkflowsController: every action there
# is behind +view_project_workflow+, and requiring that to read the workflow
# governing your own issue would hide the panel from the people it is for.
class ProjectWorkflowMapsController < ApplicationController
  menu_item :issues

  helper ProjectWorkflowsHelper
  helper ProjectWorkflowMapsHelper

  before_action :find_issue_or_project
  before_action :find_tracker

  def show
    # No tracker argument: the query reads everything off the one issue, and
    # +find_tracker+ has already applied the form's tracker to it. See the
    # query's own initialize for why that is not a parameter.
    @map = RedmineProjectWorkflows::Services::TransitionMapQuery.new(
      issue: @issue, user: User.current
    ).result

    respond_to do |format|
      # The link is remote, so this is the path a browser with JavaScript takes;
      # the HTML one is what it falls back to without, and is a page of its own
      # rather than a dead link.
      format.js
      format.html
    end
  end

  private

  # Two ways in, and which one decides the authorization.
  #
  # A saved issue is found through Issue.visible, which already carries project
  # visibility, the issue tracking module and the issue's own visibility rules --
  # so a reader who cannot see the issue gets 404, exactly as they would from
  # core's own issue page. params[:project_id] is not consulted on that path at
  # all: the project is the issue's, so no parameter can move the panel to
  # another project's workflow (INV-7).
  #
  # Without an issue there is no issue yet -- the new-issue form -- and the
  # question is whether the reader may create one here. An archived project or
  # one with the module disabled answers 403 through +allowed_to?+, not 404.
  def find_issue_or_project
    if params[:issue_id].present?
      @issue = Issue.visible.find_by(id: params[:issue_id])
      return render_404 if @issue.nil?

      @project = @issue.project
    else
      find_project_by_project_id
      return if performed?

      deny_access unless User.current.allowed_to?(:add_issues, @project)
    end
  end

  # The tracker the form currently shows, matched against the trackers the
  # project has enabled -- a parameter can only ever name one that is already on
  # that list, never reach a query on its own (INV-7, and Rails resolves
  # where(id: ['1e5']) to record 1).
  #
  # It falls back to the issue's own tracker rather than to a 404, because a
  # tracker can be taken off a project after an issue was filed under it and the
  # panel still has to describe that issue.
  def find_tracker
    return if performed?

    @tracker = offered_tracker || @issue&.tracker
    return render_404 if @tracker.nil?

    # The new-issue form has no issue to describe, so the map is drawn for the one
    # the reader is about to create: this project, this tracker, and themselves as
    # the author -- which is what the status list on that form is built from too.
    @issue ||= Issue.new(project: @project, tracker: @tracker, author: User.current)
    # The form reconciles a tracker change before it re-renders, and this is the
    # same reconciliation: Patches::IssuePatch#tracker= keeps the status when the
    # new tracker's own workflow uses it and falls back to that tracker's default
    # when it does not, which is what Issue#new_statuses_allowed_to picks as its
    # initial status. Applying it here is what keeps the map and the status list
    # reading from one object instead of two.
    @issue.tracker = @tracker if @issue.tracker_id != @tracker.id
  end

  def offered_tracker
    requested = params[:tracker_id].to_s
    offered = RedmineProjectWorkflows::Services::ProjectOptions.trackers(@project)
    offered.detect { |tracker| tracker.id.to_s == requested }
  end
end
