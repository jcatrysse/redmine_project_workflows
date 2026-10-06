# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # One line in the application log per workflow write, so that "this workflow
    # stopped behaving as expected" can be answered afterwards.
    #
    # Why (finding F19). An administration save can rewrite thousands of rules
    # across every project on the installation in one transaction, and afterwards
    # the only record was a flash message the operator had already navigated away
    # from, plus two audit columns that say *who* and not *how much*. `Rails.logger`
    # had exactly one caller in the whole plugin, in the Deface loader's rescue.
    # This is an operations gap rather than a defect -- and the case where it costs
    # somebody a day is precisely the one the review was about.
    #
    # In one place rather than four `Rails.logger.info` calls, because the rule
    # about *what may be logged* is the part worth holding in one place:
    #
    #   ids and counts only. Never issue content, never request payloads, never
    #   matrix data, never a user's name -- an actor id, not a login.
    #
    # A workflow matrix is configuration rather than personal data, but the
    # parameters it arrives in are a request body, and a log is the wrong place
    # for one.
    class WriteLog
      PREFIX = '[redmine_project_workflows]'
      # An administration selection can name every project on the installation.
      # Logging five thousand ids per save would make the log useless and large,
      # so past this many a field becomes a count alone.
      MAX_IDS = 20

      def self.record(action, **fields)
        logger = Rails.logger
        return unless logger

        logger.info("#{PREFIX} #{action} #{format_fields(fields)}".rstrip)
      end

      def self.format_fields(fields)
        fields.compact.map { |name, value| "#{name}=#{format_value(value)}" }.join(' ')
      end
      private_class_method :format_fields

      # Integers and id lists only. Anything else is rendered as its class name
      # rather than its value: a field this class does not recognise is far more
      # likely to be something that must not be logged than something worth
      # logging, so the default is to say nothing about it.
      def self.format_value(value)
        case value
        when Integer, Symbol then value.to_s
        when String then value.match?(/\A[\w-]{1,32}\z/) ? value : value.class.name
        when Array then format_ids(value)
        else value.class.name
        end
      end
      private_class_method :format_value

      def self.format_ids(values)
        ids = values.map { |value| value.respond_to?(:id) ? value.id : value }
        return "count:#{ids.size}" if ids.size > MAX_IDS

        # nil is a real member of a project id list -- it is the generic
        # workflow (INV-4) -- so it is rendered rather than dropped.
        ids.map { |id| id.nil? ? 'generic' : Integer(id).to_s }.join(',')
      rescue TypeError, ArgumentError
        "count:#{values.size}"
      end
      private_class_method :format_ids
    end
  end
end
