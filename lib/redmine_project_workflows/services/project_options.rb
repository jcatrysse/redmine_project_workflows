# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Which trackers and roles a project may configure a workflow for.
    #
    # This is the list every project-scoped screen intersects its parameters
    # with (INV-7): a request can only ever name something that is on it, so
    # there is no shape of tracker_id or role_id that reaches a query without
    # having been matched against a record first.
    #
    # Narrower than the administration screens on purpose. Core's workflow
    # matrix lists every tracker and every role in the installation, because a
    # system administrator configures the generic workflow, which applies
    # everywhere. A project can only be asked about the trackers it has enabled
    # and the roles that somebody actually holds in it.
    class ProjectOptions
      # The trackers enabled for this project, in Redmine's own order.
      def self.trackers(project)
        project.trackers.sorted.to_a
      end

      # The roles this project may be *offered* a workflow of its own for: the
      # ones with at least one member in it that take part in a workflow at all.
      #
      # The builtin roles -- Non member and Anonymous -- are deliberately not
      # here: they have no members anywhere, and deciding the workflow for the
      # people who are *not* a project's members is a system administrator's job
      # on the administration screens (decided by Jan, 2026-08-26).
      #
      # What that decision does not say, and what the comment here used to claim,
      # is that such a role goes on following the generic workflow. It does not
      # have to: an administrator can give a project its own workflow for
      # Anonymous from Administration -> Workflow, and the last member holding an
      # ordinary role can leave. So this list answers "may the project take this
      # role over?" and .visible_roles answers "does the project already run its
      # own workflow for it?" -- see there (finding F05).
      def self.roles(project)
        role_ids = MemberRole.joins(:member).where(members: { project_id: project.id }).distinct.pluck(:role_id)
        return [] if role_ids.empty?

        Role.sorted.where(id: role_ids).select(&:consider_workflow?)
      end

      # The roles the project's own screens show and can act on: the ones above,
      # plus every role that already has a scope for this project.
      #
      # The second half is the repair F05 named. A workflow the project runs
      # itself but its Workflow tab does not list is in force and unreachable
      # from the one screen meant to explain it -- there is no line for the role
      # and no way to give it back. A role that arrived by that route is fully
      # visible and can be emptied or returned; the one thing it is not offered
      # is a *new* workflow of its own, which is the decision above.
      #
      # Not filtered by +consider_workflow?+, unlike the offered half. A role that
      # has since lost both issue permissions takes no part in a workflow, so its
      # scope is inert -- but it is also dropped from the administration
      # selector, which would leave the row with nowhere at all that can remove
      # it. Reporting what the scope table holds for this project is this
      # screen's job.
      #
      # Still a list the server builds from the project alone, so a request
      # parameter can only ever name something already on it (INV-7). And no
      # walk up the project tree: one query, this project's own scopes (INV-6).
      def self.visible_roles(project)
        offered = roles(project)
        scoped_ids = ProjectWorkflowScope.where(project_id: project.id).distinct.pluck(:role_id) -
                     offered.map(&:id)
        return offered if scoped_ids.empty?

        (offered + Role.sorted.where(id: scoped_ids).to_a).uniq.sort
      end
    end
  end
end
