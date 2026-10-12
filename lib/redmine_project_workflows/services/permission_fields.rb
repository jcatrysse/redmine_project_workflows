# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The rows of a Fields permissions matrix on this plugin's own screens: the
    # core fields the trackers have not disabled, then the fields other plugins
    # add (round 6, Jan 2026-10-12). One list, read by the project matrix, the
    # administration matrix and the comparison screen's "offered" set, so the
    # three cannot disagree.
    #
    # How another plugin adds a field, in its own init.rb -- in any plugin load
    # order, and without depending on this plugin being installed:
    #
    #   (Rails.configuration.x.project_workflow_permission_fields ||= []).concat(%w[impact_id urgency_id])
    #
    # Registering is not enough to be offered. A name must be a plain
    # lower-case identifier, not a core field and not a run of digits (custom
    # fields have rows of their own), and WorkflowPermission's own
    # validate_field_name -- the extension point the plugin uses to make the
    # name valid at all -- must accept it (INV-2). PermissionWriter asks the
    # same question before it writes, so an offered name is a writable name.
    #
    # The label is the field's `field_<name without _id>` translation, which is
    # how core and redmine_itil_priority label these rows, falling back to the
    # name itself.
    class PermissionFields
      CONFIG_KEY = :project_workflow_permission_fields
      IDENTIFIER = /\A[a-z_][a-z0-9_]*\z/

      class << self
        # [[field, label], ...] for the trackers of a matrix: core fields no
        # tracker of the selection has disabled, then the extra fields.
        def for_trackers(trackers)
          disabled = trackers.map(&:disabled_core_fields).reduce(:&) || []
          (Tracker::CORE_FIELDS_ALL - disabled).map { |field| [field, label(field)] } +
            extra_names.map { |field| [field, label(field)] }
        end

        # The names alone, for the comparison screen.
        def names_for_trackers(trackers)
          for_trackers(trackers).map(&:first)
        end

        def extra_names
          registered = Array(Rails.configuration.x.public_send(CONFIG_KEY)).map(&:to_s).uniq
          registered.select do |name|
            name.match?(IDENTIFIER) && Tracker::CORE_FIELDS_ALL.exclude?(name) && model_accepts?(name)
          end
        end

        # The model's own answer for a name the server already chose to ask
        # about. Only ever called with a plain identifier: core's check is
        # line-anchored (/^\d+$/) and would wave "5\nanything" through.
        def model_accepts?(name)
          return false unless name.match?(IDENTIFIER)

          probe = WorkflowPermission.new(field_name: name)
          probe.send(:validate_field_name)
          probe.errors[:field_name].empty?
        end

        private

        def label(field)
          ::I18n.t("field_#{field.delete_suffix('_id')}", default: field.delete_suffix('_id').humanize)
        end
      end
    end
  end
end
