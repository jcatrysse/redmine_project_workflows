# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # How much of a submitted matrix the writer's whitelist kept, and how much it
    # dropped -- in one place, so the two writers cannot answer it differently.
    #
    # Extended into both rule writers, beside MatrixScope, and for the same
    # reason: this is one rule that two writers need, and this repository has
    # already had four findings that were one rule held in one of two places.
    #
    # The count exists because MatrixSaveResult's two counts covered
    # all-or-nothing and not the middle: a save whose whitelist dropped *some*
    # entries had a positive +written+, so the screen reported a plain success and
    # said nothing about the refused part -- while the README promises that an
    # unacceptable value leaves the rule it names alone *and the screen says so*
    # (finding F06 of the 2026-08-27-bundled run).
    #
    # Each writer supplies the two halves that differ:
    #
    #   normalize_payload   whatever has to happen before counting (identity for
    #                       transitions; PermissionWriter reshapes first)
    #   leaf_count          submitted values at the depth its whitelist decides
    #                       at -- (cell, rule) for transitions, (status, field)
    #                       for permissions
    #   sanitize_payload    the whitelist itself
    module SanitizedPayload
      def sanitize_and_count(payload)
        payload = normalize_payload(payload)
        submitted = leaf_count(payload)
        sanitized = sanitize_payload(payload)
        [sanitized, submitted - leaf_count(sanitized)]
      end

      # What a save would rewrite, asked *before* anything is written (WP13,
      # audit F08): the submitted values at the depth this writer's whitelist
      # decides at, which is one per cell of the matrix the operator filled in.
      #
      # The same +leaf_count+ #sanitize_and_count uses, so the number the screen
      # refuses a save over and the number the writer would act on cannot drift
      # apart. It counts what was *submitted*, not what the whitelist would keep:
      # a save is bounded by the work it asks for, and a payload full of values
      # the whitelist drops is not a cheaper save, it is a stranger one.
      def submitted_leaf_count(payload)
        leaf_count(normalize_payload(payload))
      end

      # Most payloads need nothing; PermissionWriter overrides this.
      def normalize_payload(payload)
        payload
      end
    end
  end
end
