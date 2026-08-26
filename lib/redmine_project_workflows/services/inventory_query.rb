# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The rows of the inventory screen: one per (project, tracker, role), with
    # the state and the number of rules that apply, for each rule type.
    #
    # Two modes, because the two questions are different sizes:
    #
    #   deviations_only   the rows come from project_workflow_scopes, so the
    #                     result is as large as the number of decisions that
    #                     have actually been taken
    #   everything        the rows are the full product of the filtered
    #                     projects, trackers and roles
    #
    # The product is never materialised: #total is a multiplication and a page
    # is addressed arithmetically, so a page costs the same on an installation
    # with three projects and one with three thousand. Whatever the mode, one
    # page is at most five queries -- the deviating combinations, the scopes, one
    # count per rule type, and the users named by the scopes' audit columns --
    # and never one per row (G6).
    class InventoryQuery
      # What one cell of the table says: which of the three states of INV-3
      # this (project, tracker, role, rule type) is in, and how many rules of
      # its own the project holds for it.
      #
      # The count is the project's own rules and never the generic ones, so
      # that it always matches the matrix the cell links to. An inheriting
      # combination therefore reads "0", and the state label next to it -- not
      # the number -- is what says the generic workflow applies.
      #
      # +updated_by+ and +updated_on+ are the scope's audit trail (WP6): who last
      # changed these rules and when. Both are nil on an inheriting cell, which
      # has no scope row to carry them, and +updated_by+ is nil as well for a
      # write with no logged-in user behind it -- a rake task, a migration, the
      # backfill.
      Cell = Struct.new(:state, :rule_count, :updated_by, :updated_on)

      # +cells+ is keyed by rule type.
      Row = Struct.new(:project, :tracker, :role, :cells)

      def initialize(projects:, trackers:, roles:, rule_types:, deviations_only:)
        @projects = Array(projects)
        @trackers = Array(trackers)
        @roles = Array(roles)
        @rule_types = Array(rule_types)
        @deviations_only = deviations_only
      end

      def total
        @total ||=
          if deviations_only?
            deviating_triples.size
          else
            @projects.size * @trackers.size * @roles.size
          end
      end

      def rows(offset:, limit:)
        build_rows(page_triples(offset.to_i, limit.to_i))
      end

      private

      def deviations_only?
        @deviations_only
      end

      def page_triples(offset, limit)
        return [] if limit <= 0 || offset >= total || offset.negative?

        if deviations_only?
          deviating_triples[offset, limit] || []
        else
          product_slice(offset, limit)
        end
      end

      # The n-th entry of projects x trackers x roles, in that nesting order,
      # without building the product. The list of projects can be long; the
      # page never is.
      def product_slice(offset, limit)
        per_project = @trackers.size * @roles.size
        return [] if per_project.zero?

        (offset...[offset + limit, total].min).map do |index|
          project = @projects[index / per_project]
          within = index % per_project
          [project.id, @trackers[within / @roles.size].id, @roles[within % @roles.size].id]
        end
      end

      # Every (project, tracker, role) that has decided something for at least
      # one of the rule types under consideration, ordered the way the three
      # filtered lists are ordered -- in Ruby, because ordering it in SQL would
      # mean joining three tables to sort by name and position.
      def deviating_triples
        @deviating_triples ||=
          if empty_selection?
            []
          else
            order = position_maps
            ProjectWorkflowScope.where(
              project_id: ids(@projects), tracker_id: ids(@trackers),
              role_id: ids(@roles), rule_type: @rule_types
            ).distinct.pluck(:project_id, :tracker_id, :role_id).sort_by do |project_id, tracker_id, role_id|
              [order[0][project_id], order[1][tracker_id], order[2][role_id]]
            end
          end
      end

      def position_maps
        [@projects, @trackers, @roles].map do |records|
          records.each_with_index.to_h { |record, index| [record.id, index] }
        end
      end

      def empty_selection?
        @projects.empty? || @trackers.empty? || @roles.empty? || @rule_types.empty?
      end

      def ids(records)
        records.map(&:id)
      end

      def build_rows(triples)
        return [] if triples.empty?

        # The three columns of the page's triples, so that both queries below
        # ask for exactly the rows this page can show and no more.
        ids = (0..2).map { |column| triples.map { |triple| triple[column] }.uniq }
        scoped = scoped_combinations(*ids)
        own = own_counts(*ids)
        authors = authors_for(scoped)

        by_id = position_records
        triples.map do |triple|
          cells = @rule_types.index_with { |rule_type| cell_for(triple, rule_type, scoped, own, authors) }
          Row.new(by_id[0][triple[0]], by_id[1][triple[1]], by_id[2][triple[2]], cells)
        end
      end

      # Rules without a scope apply to nothing (INV-3), so an inheriting
      # combination counts none of them -- not even rows physically stored
      # against the project. WP1's backfill leaves none behind; one that arrives
      # later is a repair for the operator, not a number to show here.
      def cell_for(triple, rule_type, scoped, own, authors)
        audit = scoped[triple + [rule_type]]
        return Cell.new(:inherits, 0, nil, nil) if audit.nil?

        count = own[rule_type][triple] || 0
        updated_by_id, updated_on = audit
        Cell.new(count.positive? ? :own : :own_empty, count, authors[updated_by_id], updated_on)
      end

      def position_records
        [@projects, @trackers, @roles].map { |records| records.index_by(&:id) }
      end

      # Keyed by [project_id, tracker_id, role_id, rule_type]; the value is the
      # scope's audit pair. A key that is absent means the combination inherits,
      # which is the question this hash was asked before WP6 added the audit
      # columns to the answer -- so presence still carries that meaning, and a
      # scope whose audit columns are both null still has an entry.
      def scoped_combinations(project_ids, tracker_ids, role_ids)
        rows = ProjectWorkflowScope.where(
          project_id: project_ids, tracker_id: tracker_ids,
          role_id: role_ids, rule_type: @rule_types
        ).pluck(:project_id, :tracker_id, :role_id, :rule_type, :updated_by_id, :updated_at)
        rows.to_h { |row| [row[0, 4], row[4, 2]] }
      end

      # One query for every user named on the page, so a table of a hundred rows
      # loads at most a hundred users once rather than one per cell (G6). A
      # scope written with nobody logged in names none, and a user since deleted
      # leaves the id behind -- migration 004's foreign key nullifies it, but a
      # database restored around that is not worth a crash, so a missing id
      # simply has no author.
      def authors_for(scoped)
        ids = scoped.each_value.filter_map { |updated_by_id, _updated_on| updated_by_id }.uniq
        return {} if ids.empty?

        User.where(id: ids).index_by(&:id)
      end

      # INV-4: the query names the project ids of the rows on the page, so a
      # generic rule can never be counted into a project's total -- which is
      # the mistake the summary page made before WP3.
      def own_counts(project_ids, tracker_ids, role_ids)
        @rule_types.index_with do |rule_type|
          ProjectWorkflowScope.rule_model_for(rule_type).where(
            project_id: project_ids, tracker_id: tracker_ids, role_id: role_ids
          ).group(:project_id, :tracker_id, :role_id).count
        end
      end
    end
  end
end
