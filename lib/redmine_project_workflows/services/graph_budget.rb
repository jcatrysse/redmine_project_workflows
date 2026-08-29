# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Whether the workflow drawing is offered at all, and how large a workflow it
    # will draw (WP14).
    #
    # **Why a switch.** The drawing is finished, it is pure functions with about
    # 800 lines of specs, and it is the plugin's clearest difference from Jira --
    # so a review's proposal to cut it was answered on 2026-08-28 with "it becomes
    # switchable instead". A feature that can be turned off is a feature nobody
    # has to defend on an upgrade: an installation that does not want it, or that
    # hits something on a Redmine nobody has tried yet, turns it off in
    # Administration -> Plugins and keeps every other screen. It is **on** by
    # default, because it is what the package was written for.
    #
    # **Why a ceiling, and why it counts arrows.** The layout is the expensive
    # part and its cost is driven by edges rather than by statuses. Measured on
    # 2026-08-29 (Redmine 7.0, PostgreSQL 16, in this container), one project, one
    # tracker, one role:
    #
    #   statuses  arrows   layout
    #   ---------------------------
    #   21           400     79 ms      complete workflow (every status -> every other)
    #   41         1,600    522 ms
    #   61         3,600  1,550 ms
    #   201          400     29 ms      sparse workflow (two moves per status)
    #   401          800     49 ms
    #
    # A workflow with four hundred statuses is cheap; one with sixty statuses and
    # every move permitted is a second and a half of one request. So the number to
    # bound is the arrows, and DEFAULT_EDGE_CEILING is about seven tenths of a
    # second of layout on that hardware.
    #
    # Above the ceiling the screen keeps the scope panel and the table -- the
    # table is the readable twin of the drawing and is linear -- and says why the
    # picture is not there. It is not an error and nothing is refused: no write is
    # involved, and the workflow is still completely readable.
    #
    # Distinct from the `<details>` disclosure a *dense* workflow already gets
    # (finding F03 of 2026-08-28): that one is about a drawing nobody can read and
    # it still computes the layout. This one is about a drawing nobody should wait
    # for, and it computes nothing.
    class GraphBudget
      # ~0.7 s of layout at the rates above, and far beyond any workflow an
      # installation of ordinary size has: Redmine's own default data is five
      # statuses and twenty-five arrows.
      DEFAULT_EDGE_CEILING = 2_000

      # On. The setting is stored as Redmine stores every checkbox, '1' or '0'.
      DEFAULT_ENABLED = '1'

      # Anything but an explicit '0' is on, including a settings hash saved before
      # this key existed -- Redmine assigns the plugin settings hash exactly as it
      # arrives and offers no validation hook, so the fallback lives here.
      def self.enabled?
        Setting.plugin_redmine_project_workflows['graph_enabled'].to_s != '0'
      end

      def self.edge_ceiling
        value = Setting.plugin_redmine_project_workflows['graph_edge_ceiling'].to_s
        value.match?(/\A\d+\z/) ? value.to_i : DEFAULT_EDGE_CEILING
      end

      # 0 is "no ceiling", the same escape hatch WriteBudget offers, for an
      # installation that has looked at its own numbers.
      def self.over_ceiling?(edge_count)
        edge_ceiling.positive? && edge_count > edge_ceiling
      end
    end
  end
end
