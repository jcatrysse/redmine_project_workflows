# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # How much one administration save is allowed to rewrite (WP13, audit
    # finding F08).
    #
    # The transaction around a matrix save is deliberate and right: a failure
    # half way through would otherwise leave part of the selection rewritten and
    # the rest as it was. What was not bounded is what goes inside it. A
    # selection of *all projects* x *all trackers* x *all roles* rewrites every
    # cell of every combination while holding a coordination row for each, and
    # the row count -- unlike the statement count, which is constant per project
    # -- grows with the selection.
    #
    # Measured on a running host: 5 projects x 3 trackers x 3 roles x 36 cells is
    # 1,620 rows in 63 ms and 48 statements. A realistic large installation --
    # 500 projects, 5 trackers, 8 roles, 20 statuses -- extrapolates to roughly
    # **8 million rows** deleted and reinserted in one transaction, during which
    # every other administrator and every project manager saving their own matrix
    # waits. A front-end proxy timing out rolls the whole thing back with no
    # partial progress.
    #
    # **Not a background job.** Redmine 5.1's default ActiveJob backend is the
    # async adapter, which loses its queue when the process restarts. A workflow
    # write may not depend on that.
    #
    # So: keep the transaction, bound the selection. Two numbers, both plugin
    # settings, both in **workflow rules** -- the same unit the row and column
    # actions of WP5 already ask about, which is (cells submitted) x (workflows
    # the selection covers):
    #
    #   bulk_confirm_threshold        above this, a *row or column action* asks
    #                                 (WP5; one click, and what it changes is not
    #                                 visible until you look)
    #   bulk_save_confirm_threshold   above this, the *Save button* asks (client
    #                                 side, and only when the selection covers
    #                                 more than one workflow -- a single-workflow
    #                                 save is what Redmine has always done and
    #                                 must not grow a dialog)
    #   bulk_write_ceiling            above this, the save is refused before the
    #                                 transaction opens. 0 means no ceiling.
    #
    # **Why Save has a threshold of its own, and a much larger one.** Both were
    # `bulk_confirm_threshold` until the write path was measured on 2026-08-29.
    # At 50 rules the Save dialog fired on essentially *every* multi-workflow
    # save -- two workflows of a six-status matrix is already 216 rules -- so it
    # stopped carrying information and became something to click through. A row
    # or column action is one click whose effect you cannot see; a Save is a form
    # the operator has just filled in, on a page that already says how many
    # workflows one cell stands for. The surprise is smaller and the threshold
    # should be too.
    class WriteBudget
      # Raised instead of writing, when an action would go over the ceiling.
      #
      # An exception rather than a return value because the two callers that can
      # hit it -- the administration scope action and the project screen's -- do
      # not share a return shape with the matrix save, and because the refusal
      # has to abandon a transaction that is already open: ScopeWriter.enable
      # cannot know what it would write until it has read which combinations are
      # missing, and that read belongs inside the transaction that then writes
      # them (ADR-004).
      #
      # It carries the two numbers the message needs, so no caller recomputes
      # them.
      class TooLarge < StandardError
        attr_reader :projected, :ceiling

        def initialize(projected:, ceiling:)
          @projected = projected
          @ceiling = ceiling
          super("this action would write #{projected} workflow rules, above the ceiling of #{ceiling}")
        end
      end

      # Measured on 2026-08-29 (Redmine 7.0, PostgreSQL 16, in this container):
      # about 27,000 workflow rules a second, flat from 4,860 to 172,800 rules
      # and independent of how the selection is shaped. So the ceiling is roughly
      # **seven seconds** of writing, which is where a front-end proxy starts
      # timing out -- and a timeout is the worst outcome here, because it rolls
      # back everything and reports nothing. Deliberately far above any selection
      # an installation of ordinary size can produce: 50 projects x 3 trackers x
      # 3 roles x 36 cells is 16,200. Answered **A** by Jan on 2026-08-29.
      DEFAULT_WRITE_CEILING = 200_000

      # About a fifth of a second of writing at the rate above, and -- the number
      # that actually decides it -- roughly 46 workflows of a six-status matrix.
      # Fifty workflows rewritten at once is worth one question; two is not.
      DEFAULT_SAVE_CONFIRM_THRESHOLD = 5_000

      # The rules a save would rewrite: every cell it submitted, once per
      # workflow the selection covers.
      #
      # +scopes+ counts the generic workflow as one, exactly as
      # BulkActionsHelper#project_workflow_selection_scopes does, because the
      # generic workflow is one more population to rewrite.
      def self.projected_rules(scopes:, trackers:, roles:, cells:)
        scopes * trackers * roles * cells
      end

      # What *give own workflow* would copy: for each (tracker, role) pair, the
      # number of generic rules of that type times the number of combinations of
      # that pair the action would create (ADR-004).
      #
      # Exact rather than estimated, like the matrix save's projection: both
      # halves are in hand before anything is written -- +combinations+ is what
      # ScopeWriter.enable has just decided is missing, and the counts come from
      # the generic population itself.
      #
      # One grouped statement, and it names its population (INV-4):
      # +project_id: nil+ is the generic workflow, which is the only thing a copy
      # reads from.
      #
      # Answers 0 for the *empty* variant, which copies nothing -- so that action
      # is never refused, and at the rate ADR-004 measured it does not need to be.
      def self.projected_enable_rules(combinations:, rule_type:)
        return 0 if combinations.empty?

        sti_type = ProjectWorkflowScope.rule_model_for(rule_type).name
        per_pair = WorkflowRule.where(project_id: nil, type: sti_type,
                                      tracker_id: combinations.map { |_p, tracker_id, _r| tracker_id }.uniq,
                                      role_id: combinations.map { |_p, _t, role_id| role_id }.uniq)
                               .group(:tracker_id, :role_id).count
        combinations.sum { |_project_id, tracker_id, role_id| per_pair[[tracker_id, role_id]].to_i }
      end

      # Raises rather than answering, for the caller that is inside its own
      # transaction and wants the refusal to abandon it.
      def self.refuse_above_ceiling!(projected)
        raise TooLarge.new(projected: projected, ceiling: ceiling) if over_ceiling?(projected)

        projected
      end

      def self.ceiling
        setting('bulk_write_ceiling', DEFAULT_WRITE_CEILING)
      end

      def self.save_confirm_threshold
        setting('bulk_save_confirm_threshold', DEFAULT_SAVE_CONFIRM_THRESHOLD)
      end

      # 0 is "no ceiling", which is the escape hatch for an installation that has
      # measured its own database and wants the whole selection in one go.
      def self.over_ceiling?(projected)
        ceiling.positive? && projected > ceiling
      end

      # A plugin setting read as a count. Falls back to +default+ for a value an
      # administrator has cleared or typed something else into, and for the key
      # an older saved settings hash does not carry at all -- Redmine assigns the
      # settings hash exactly as it arrives, with no validation hook.
      def self.setting(key, default)
        value = Setting.plugin_redmine_project_workflows[key].to_s
        value.match?(/\A\d+\z/) ? value.to_i : default
      end
    end
  end
end
