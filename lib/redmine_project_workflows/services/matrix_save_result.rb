# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What one matrix save did, as the two counts that decide what the screen may
    # claim about it.
    #
    #   written   (tracker, role) combinations whose rules this call rewrote
    #   skipped   combinations it refused, because the project still inherits
    #             the generic workflow (INV-3)
    #
    # Two counts and not one. The writers used to return +skipped+ alone, and the
    # controller inferred the rest as (projects x trackers x roles) - skipped --
    # which cannot tell "wrote everything" from "there was nothing left to
    # write". A payload the writer's whitelist had dropped in its entirety
    # refuses nothing, because it never gets as far as the scope rows, so it
    # arrived at the flash as a successful save of the whole selection. The
    # dropping is deliberate and documented: an unacceptable value leaves the
    # rule it names alone rather than clearing it. Reporting it as applied undid
    # half of that (finding F06).
    #
    # Instances are summed across the projects of a selection, so +#++ is what
    # makes `project_ids.sum(MatrixSaveResult.none) { ... }` work.
    MatrixSaveResult = Struct.new(:written, :skipped) do
      def self.none
        new(0, 0)
      end

      def +(other)
        self.class.new(written + other.written, skipped + other.skipped)
      end

      def written?
        written.positive?
      end

      def skipped?
        skipped.positive?
      end

      # Nothing written and nothing refused: the submission named no change this
      # writer could apply. Either every control was left at "(No change)", or
      # every value it did carry failed the whitelist -- and the screen has to
      # say so rather than report a save.
      def nothing_applied?
        !written? && !skipped?
      end
    end
  end
end
