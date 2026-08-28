# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # How big a workflow drawing is (WP9).
    #
    # Its own object, small as it is, because the question it answers has a trap
    # in it that cost a session once and has a spec of its own: **a viewBox built
    # from the node positions clips every curve that bows outside them, and it
    # does so silently.** There is no error anywhere; the returning arcs are
    # simply not on the page. The answer is to measure over the boxes *and* every
    # point of every path -- a cubic Bezier lies inside the hull of its four
    # control points, so the points a path names are a sound bound on the curve
    # it draws.
    #
    # Both halves are load-bearing. The paths alone miss a node nothing points
    # at; the boxes alone clip the arcs.
    #
    # Integer arithmetic throughout, like the rest of the drawing: the numbers
    # here end up in a string, and a string that can differ in its last digit
    # between platforms turns "the same input gives the same output" into a claim
    # about a formatter.
    class WorkflowGraphExtent
      # +[min_x, min_y, width, height]+ over the placed boxes and the routed
      # paths, padded at all four sides.
      def self.of(placed, routed, padding:)
        corners = placed.flat_map do |node|
          [[node.x, node.y], [node.x + node.width, node.y + node.height]]
        end
        points = corners + routed.flat_map(&:points)
        min_x, width = span(points.map(&:first), padding)
        min_y, height = span(points.map(&:last), padding)
        [min_x, min_y, width, height]
      end

      # One axis: where the drawing starts, and how far it runs, padded at both
      # ends. Returned as a pair so that +of+ stays two lines rather than eight
      # near-identical ones.
      def self.span(values, padding)
        [values.min - padding, (values.max - values.min) + (2 * padding)]
      end
      private_class_method :span
    end
  end
end
