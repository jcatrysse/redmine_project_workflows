# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What a request selected, and what it named that does not exist.
    #
    # WP18, finding F03 of 2026-08-29-claude-revalidation. There were four
    # selection resolvers on this plugin with four different strictnesses, and
    # **the least strict was the one that writes**: the graph refused an id it
    # could not resolve, the copy screen refused, the scope routes checked the
    # shape as well as the record, and the administration matrix did
    # `klass.where(id: ids).to_a` and wrote whatever survived. Measured on a
    # running host: `tracker_id=1e5` wrote rules for tracker 1 and reported
    # *Successful update*.
    #
    # Two things make that possible and this class refuses both.
    #
    # **A value of the wrong shape is cast, not dropped.** `where(id: ['1e5'])`
    # resolves to id 1, because Rails casts the value to the column's type;
    # `'12abc'` means 12 for the same reason. So an id has to match `/\A\d+\z/`
    # before it is allowed anywhere near a query -- and where the candidates are
    # already in memory, it is compared as a string against ids the server holds
    # and no shape of it reaches a query at all.
    #
    # **A value that names nothing is silently absent from the result.** Asking
    # for two trackers and getting one back is indistinguishable from asking for
    # one, so a stale form naming a tracker deleted since it was rendered writes
    # the rest and reports success. Everything the request named and no record
    # answered is collected in +unresolved+, and the caller refuses *before* any
    # write -- which matters most where the write deletes first, as every matrix
    # save does.
    class ExactSelection
      # An id, and nothing else. Not a range, not a float, not a signed value:
      # `where(id: ['-1'])` is a perfectly good query for a row that does not
      # exist, and the point here is to answer "you named something that is not
      # an id" rather than to let the database answer it.
      ID = /\A\d+\z/

      Result = Struct.new(:records, :keywords, :unresolved, keyword_init: true) do
        # The whole contract in one word: the request named nothing this did not
        # find. A caller that writes asks this first.
        def exact? = unresolved.empty?

        def keyword?(name) = keywords.include?(name)

        def ids = records.map(&:id)

        # nil rather than [] for "nothing was selected", which is what the
        # matrix screens distinguish: no selection renders the selector, an
        # empty selection is not a state they have.
        delegate :presence, to: :records
      end

      # +candidates+ -- the list the server built, which the selection may not
      # go outside. The comparison is between strings and ids already in memory.
      #
      # +scope+ -- a relation, for a selection that may legitimately name a
      # record the screen does not offer. There is exactly one: an archived
      # project, reachable from the inventory by id though the selector does not
      # list it. The ids are shape-checked before they reach it.
      #
      # +keywords+ -- the non-numeric values this selector accepts, kept
      # explicit. 'all', 'global' and 'any' are selections, not ids, and a
      # resolver that did not know which of them this control speaks would
      # either reject a real selection or accept a meaningless one.
      def self.resolve(param, candidates: nil, scope: nil, keywords: [])
        values = Array.wrap(param).reject(&:blank?).map(&:to_s).uniq
        chosen, rest = values.partition { |value| keywords.include?(value) }
        ids = rest.grep(ID)
        records = records_for(ids, candidates, scope)
        Result.new(records: records, keywords: chosen,
                   unresolved: rest - records.map { |record| record.id.to_s })
      end

      # In candidate order, not request order: the candidates are the sorted
      # list a screen already renders, and a selection that came back in the
      # order the browser happened to submit would draw the same two trackers in
      # two different orders on two requests.
      def self.records_for(ids, candidates, scope)
        return [] if ids.empty?
        return candidates.select { |record| ids.include?(record.id.to_s) } if candidates

        scope.where(id: ids).to_a
      end
      private_class_method :records_for
    end
  end
end
