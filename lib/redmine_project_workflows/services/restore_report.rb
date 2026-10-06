# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What a restore did, in the terms an operator has to check it against.
    RestoreReport = Struct.new(:scopes, :rules, :rejected, :skipped_existing, :skipped_differing,
                               :skipped_missing, :orphan_rules, :failed, keyword_init: true) do
      # Four outcomes, told apart, because they used to share two words.
      # "Left alone" covered both "this project already had exactly this" and
      # "this project has a workflow of its own that differs from the backup",
      # and after an interrupted restore it also covered "this combination was
      # prepared and never written" -- which is the case an operator most
      # needs to see (finding F01 of 2026-08-29-claude-revalidation).
      def lines
        [
          "#{scopes} project #{'workflow'.pluralize(scopes)} restored, " \
          "#{rules} #{'rule'.pluralize(rules)} read from the backup",
          "#{rejected} #{'value'.pluralize(rejected)} refused by validation and not written",
          *skipped_lines,
          "#{orphan_rules} #{'rule'.pluralize(orphan_rules)} not restored: " \
          'no recorded decision in the backup names them',
          *failure_lines,
          *skipped_missing
        ]
      end

      # The one number that decides whether OVERWRITE=1 would change anything.
      # "Left alone" on its own does not: an operator restoring onto an
      # installation that already carries the same workflows and one who is
      # about to lose three projects' worth of edits read the identical line.
      def skipped_lines
        line = "#{skipped_existing} left alone: the project already has a workflow there"
        return [line] if skipped_existing.zero?

        [line,
         "  of those, #{skipped_differing} #{skipped_differing == 1 ? 'differs' : 'differ'} " \
         'from the backup; OVERWRITE=1 replaces those and keeps their decisions']
      end

      def failed?
        failed.any?
      end

      # Named individually rather than counted: a restore that could not put
      # one project back is a thing somebody has to act on, and a number does
      # not say which project.
      def failure_lines
        return [] if failed.empty?

        ["#{failed.size} #{'combination'.pluralize(failed.size)} failed and were rolled back; " \
         'run the restore again to retry them'] + failed
      end
    end
  end
end
