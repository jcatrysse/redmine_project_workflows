# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # A status name, fitted into a box of fixed width (WP9).
    #
    # **SVG does not wrap.** There is no equivalent of a <p> with a width; a
    # <text> element is one line and runs off the end of whatever is behind it.
    # So the wrapping happens in Ruby, before anything is rendered, and it is an
    # estimate rather than a measurement: Ruby cannot ask a font how wide a glyph
    # is. The estimate is deliberately generous, so that a wrong guess overflows
    # into the gap between two boxes rather than into the next box.
    #
    # A class of its own because WorkflowGraphLayout crossed Metrics/ClassLength
    # -- relaxed to 200 in .rubocop.yml with a stated rationale, so crossing it
    # is a signal to extract -- and because "how a name is shortened" is a
    # decision worth being able to change, and to test, without a graph.
    class WorkflowGraphText
      # An em-width estimate for the font Redmine's own tables use. Two lines of
      # (132 - 16) / 7 = 16 characters is 32, and **Redmine caps an issue
      # status name at 30** (`validates_length_of :name, maximum: 30`), so the
      # truncation below is close to unreachable in practice: only a name that
      # cannot be broken on a space -- one word longer than sixteen characters,
      # or two whose first is -- reaches it. That is a reason to leave the box
      # width alone rather than a reason to drop the truncation, which is what
      # keeps a pathological name from running across its neighbour.
      CHAR_WIDTH = 7
      # The white space either side of the text inside a node.
      INSET = 8
      MAX_LINES = 2

      # Returns [lines, truncated]. +truncated+ is not a detail: it is what makes
      # the node's <title> worth rendering, because the full name is only there.
      def self.fit(text, width)
        limit = (width - (2 * INSET)) / CHAR_WIDTH
        lines = fold(text.to_s.split(/\s+/).reject(&:empty?), limit)
        return [[''], false] if lines.empty?
        return [lines, false] if lines.size <= MAX_LINES && lines.all? { |line| line.length <= limit }

        kept = lines.first(MAX_LINES)
        kept[-1] = "#{kept[-1][0, [limit - 1, 1].max]}…"
        [kept, true]
      end

      # A word longer than a whole line is put on one of its own and left to the
      # truncation above, rather than broken mid-word here: two different rules
      # for shortening a name would disagree sooner or later.
      def self.fold(words, limit)
        words.each_with_object([]) do |word, lines|
          if lines.empty? || (lines.last.length + 1 + word.length) > limit
            lines << word
          else
            lines[-1] = "#{lines.last} #{word}"
          end
        end
      end
      private_class_method :fold
    end
  end
end
