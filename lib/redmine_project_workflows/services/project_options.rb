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

      # The roles that have at least one member in this project and that take
      # part in a workflow at all.
      #
      # The builtin roles -- Non member and Anonymous -- are deliberately not
      # here: they have no members anywhere, so a project would never see them,
      # and giving a project its own workflow for the people who are *not* its
      # members is a decision for a system administrator on the administration
      # screens. Those roles therefore go on inheriting the generic workflow,
      # which is the state they are in today.
      def self.roles(project)
        role_ids = MemberRole.joins(:member).where(members: { project_id: project.id }).distinct.pluck(:role_id)
        return [] if role_ids.empty?

        Role.sorted.where(id: role_ids).select(&:consider_workflow?)
      end
    end
  end
end
