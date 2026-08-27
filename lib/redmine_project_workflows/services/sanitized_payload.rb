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

      # Most payloads need nothing; PermissionWriter overrides this.
      def normalize_payload(payload)
        payload
      end
    end
  end
end
