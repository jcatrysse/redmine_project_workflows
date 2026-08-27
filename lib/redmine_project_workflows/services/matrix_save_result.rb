# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What one matrix save did, as the two counts that decide what the screen may
    # claim about it.
    #
    #   written   (tracker, role) combinations whose rules this call rewrote
    #   skipped   combinations it refused, because the project still inherits
    #             the generic workflow (INV-3)
    #   rejected  individual submitted values the writer's whitelist dropped --
    #             counted in cells for permissions and in (cell, rule) leaves for
    #             transitions, which is the granularity at which the whitelist
    #             actually decides
    #
    # Two counts and not one. The writers used to return +skipped+ alone, and the
    # controller inferred the rest as (projects x trackers x roles) - skipped --
    # which cannot tell "wrote everything" from "there was nothing left to
    # write". A payload the writer's whitelist had dropped in its entirety
    # refuses nothing, because it never gets as far as the scope rows, so it
    # arrived at the flash as a successful save of the whole selection. The
    # dropping is deliberate and documented: an unacceptable value leaves the
    # rule it names alone rather than clearing it. Reporting it as applied undid
    # half of that (finding F06 of the 2026-08-27 run).
    #
    # +rejected+ is the honest completion of that fix rather than a new
    # mechanism. Two counts covered all-or-nothing and not the middle: a save
    # whose whitelist dropped *some* entries had a positive +written+, so it got
    # `notice_successful_update` and said nothing at all about the part that was
    # refused -- while the README promises that an unacceptable value leaves its
    # rule alone *and the screen says so* (finding F06 of the 2026-08-27-bundled
    # run). Reachable only through a hand-built request or an API client, like
    # the finding it descends from.
    #
    # Instances are summed across the projects of a selection, so +#++ is what
    # makes `project_ids.sum(MatrixSaveResult.none) { ... }` work.
    MatrixSaveResult = Struct.new(:written, :skipped, :rejected) do
      def self.none
        new(0, 0, 0)
      end

      # +rejected+ defaults to 0 rather than being required, because a Struct
      # member left off a `.new` arrives as nil and `nil.positive?` is a
      # NoMethodError in a flash-setting branch -- a 500 on a successful save.
      def initialize(written = 0, skipped = 0, rejected = 0)
        super
      end

      def +(other)
        self.class.new(written + other.written, skipped + other.skipped,
                       rejected + other.rejected)
      end

      def written?
        written.positive?
      end

      def skipped?
        skipped.positive?
      end

      def rejected?
        rejected.positive?
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
