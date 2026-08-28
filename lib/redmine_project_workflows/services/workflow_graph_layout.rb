# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Where the boxes and the arrows go (WP9). A pure function from a
    # WorkflowGraphQuery::Result to coordinates and path data, with no database,
    # no I18n and no host behind it -- so it can be specified exactly, and so the
    # one property that matters can be asserted: **the same input gives the same
    # output**, on every Ruby, every database and every random seed.
    #
    # Determinism is a requirement rather than a nicety. A layered drawing is
    # built from sweeps over collections, and a sweep over a collection whose
    # order came out of a query without an ORDER BY produces a different picture
    # per planner. That is the shape of failure that appears as one red cell out
    # of nine and is unreproducible locally. Every iteration here is over a list
    # the query already sorted, or over one sorted again on the spot.
    #
    # **All the arithmetic is integer arithmetic**, for the same reason: a
    # midpoint computed in floating point is a string that can differ in its last
    # digit between platforms, and "identical output" is then a claim about a
    # formatter rather than about the layout. Nothing here divides anything but
    # integers.
    #
    # Four phases. The first three are about the graph rather than about the
    # page -- break the cycles, assign layers, order within a layer -- and live
    # in WorkflowGraphRanking; this class is the fourth, which is where anything
    # first has a coordinate: even spacing, a straightening pass, the routing,
    # the text, and the extent the viewBox comes from.
    class WorkflowGraphLayout
      # The geometry. A node is a fixed size so that the layout stays a pure
      # function of the graph: letting a long status name widen its box would
      # make every coordinate depend on the text, and the drawing would reflow
      # when somebody renamed a status.
      NODE_WIDTH = 132
      NODE_HEIGHT = 44
      LAYER_GAP = 78
      ROW_GAP = 26
      # The band of statuses the entry node cannot reach sits below the drawing
      # with a gap wide enough for its label.
      BAND_GAP = 74
      PADDING = 14

      # The step between the two lines of a wrapped name. Here rather than in
      # WorkflowGraphText because it is a distance on the page, and the renderer
      # is what reads it.
      LINE_HEIGHT = 15

      # How deep a returning arc bows below the two nodes it joins. One step per
      # layer it spans, so two returns of different lengths do not lie on top of
      # each other.
      BOW_DEPTH = 26
      BOW_STEP = 9

      # One status, placed. +lines+ is the name already wrapped; +truncated+ says
      # the full name is only in the <title>, which is what makes the title worth
      # rendering. +band+ is the statuses the entry node cannot reach.
      PlacedNode = Struct.new(:node, :x, :y, :width, :height, :lines, :truncated,
                              :band, :layer, keyword_init: true) do
        def center_x
          x + (width / 2)
        end

        def center_y
          y + (height / 2)
        end
      end

      # One transition, routed. +d+ is the SVG path; +points+ is every point that
      # +d+ names, which is what the extent is measured over -- a cubic Bezier
      # lies inside the hull of its own control points, so an extent built from
      # them contains the curve.
      #
      # +back+ is an arc that returns leftwards or joins the band; the renderer
      # draws it the same way and it is here so that a spec can tell the two
      # kinds apart without parsing a path.
      RoutedEdge = Struct.new(:edge, :d, :points, :back, :conditional, keyword_init: true)

      # +view_box+ is the string the <svg> carries, and it comes from the
      # **drawn** extent: the node boxes and every point of every path. Sizing it
      # from the node positions alone clips the returning arcs, which renders
      # silently and is a bug with no symptom other than a missing arrow. There
      # is a spec for exactly that.
      Result = Struct.new(:nodes, :edges, :view_box, :width, :height, :band_top,
                          keyword_init: true) do
        delegate :empty?, to: :nodes

        def band_nodes
          nodes.select(&:band)
        end

        def drawn_nodes
          nodes.reject(&:band)
        end
      end

      # +labels+ maps a status id to the name to draw, and is how the one thing
      # this class cannot know -- what to call core's "new issue" pseudo-status
      # in the reader's language -- arrives without I18n being reachable from
      # here. A missing entry falls back to the status's own name, so a caller
      # that has nothing to say still gets a drawing.
      #
      # It is a plain hash rather than a callback so that the class stays a pure
      # function of two values a spec can write down.
      def initialize(graph, labels: {})
        @graph = graph
        @labels = labels
      end

      def result
        nodes = drawn_status_nodes
        return empty_result if nodes.empty?

        @by_id = nodes.index_by(&:status_id)
        @order = nodes.each_with_index.to_h { |node, index| [node.status_id, index] }
        edges = @graph.edges.select { |edge| @by_id.key?(edge.old_status_id) && @by_id.key?(edge.new_status_id) }

        place(nodes, edges)
      end

      private

      # An own empty workflow draws as the entry node and nothing else, with the
      # sentence the view puts beside it -- not as a frame holding every status
      # the tracker uses under some other role. "Every status is unmentioned" is
      # what an empty workflow *means*, and listing thirty of them buries the one
      # sentence that explains it (decided autonomously, 2026-08-28; reversible
      # by deleting this branch).
      def drawn_status_nodes
        return @graph.nodes.select(&:entry?) if @graph.empty_workflow?

        @graph.nodes
      end

      def empty_result
        Result.new(nodes: [], edges: [], view_box: '0 0 0 0', width: 0, height: 0, band_top: nil)
      end

      # --- placing -------------------------------------------------------------

      def place(nodes, edges)
        ranking = WorkflowGraphRanking.new(nodes, edges, order: @order).result
        placed, waypoints = coordinates(ranking)
        routed = route(edges, placed, waypoints, ranking)
        finish(placed.values.sort_by { |node| @order[node.node.status_id] }, routed, ranking.band.any?)
      end

      # Phase 4. Even spacing, then one straightening pass in which **only the
      # forward edges may pull**. A returning arc points at a node far to the
      # right; letting it tug drags the main path into a staircase, and the
      # drawing is visibly worse. Measured on the model, not assumed -- which is
      # why +pull+ is built from the forward chains alone.
      def coordinates(ranking)
        y_of = straighten(ranking, even_spacing(ranking.rows))
        placed = {}
        waypoints = {}
        ranking.rows.each do |layer, row|
          row.each { |key| assign(key, layer, y_of[key], placed, waypoints) }
        end
        place_band(placed, ranking.band)
        [placed, waypoints]
      end

      # A status id gets a box; a dummy key gets the centre of the cell a real
      # node would have occupied, which is what a long edge is routed through --
      # the whole reason the dummy was inserted into the ordering.
      def assign(key, layer, top, placed, waypoints)
        if key.is_a?(Integer)
          placed[key] = place_node(@by_id[key], layer, top)
        else
          waypoints[key] = [(layer * (NODE_WIDTH + LAYER_GAP)) + (NODE_WIDTH / 2), top + (NODE_HEIGHT / 2)]
        end
      end

      def even_spacing(rows)
        tallest = rows.values.map(&:size).max.to_i
        rows.each_with_object({}) do |(_layer, row), y_of|
          # Each layer centred against the tallest one, so a short layer sits
          # beside the middle of a long one rather than at its top.
          offset = ((tallest - row.size) * (NODE_HEIGHT + ROW_GAP)) / 2
          row.each_with_index { |key, position| y_of[key] = offset + (position * (NODE_HEIGHT + ROW_GAP)) }
        end
      end

      # Two passes left to right: a thing wants the median of what points at it,
      # and then the layer is swept downwards so that nothing overlaps and the
      # order the ranking chose is preserved. Integer division throughout, so the
      # answer is a string that cannot differ between platforms.
      def straighten(ranking, y_of)
        2.times do
          ranking.rows.each_value do |row|
            desired = row.map do |key|
              sources = ranking.pull[key].filter_map { |source| y_of[source] }.sort
              sources.empty? ? y_of[key] : sources[sources.size / 2]
            end
            apply_with_separation(row, desired, y_of)
          end
        end
        y_of
      end

      # Place a layer in its chosen order, each element at least one row below
      # the one before it. Nothing here may reorder a row: the order is the
      # ranking's answer and this only moves things.
      def apply_with_separation(row, desired, y_of)
        floor = nil
        row.each_with_index do |key, index|
          value = floor && desired[index] < floor ? floor : desired[index]
          y_of[key] = value
          floor = value + NODE_HEIGHT + ROW_GAP
        end
      end

      def place_node(node, layer, top)
        lines, truncated = fitted_name(node)
        PlacedNode.new(node: node, x: layer * (NODE_WIDTH + LAYER_GAP), y: top,
                       width: NODE_WIDTH, height: NODE_HEIGHT, lines: lines,
                       truncated: truncated, band: false, layer: layer)
      end

      # The band: the statuses the entry node cannot reach, in a row of their own
      # below everything else. A row rather than a column, because the band is
      # read as a list and a column would make the drawing twice as tall.
      def place_band(placed, band)
        return if band.empty?

        top = band_top_for(placed)
        band.each_with_index do |node, index|
          lines, truncated = fitted_name(node)
          placed[node.status_id] = PlacedNode.new(
            node: node, x: index * (NODE_WIDTH + LAYER_GAP), y: top,
            width: NODE_WIDTH, height: NODE_HEIGHT, lines: lines, truncated: truncated,
            band: true, layer: nil
          )
        end
      end

      def band_top_for(placed)
        return BAND_GAP if placed.empty?

        placed.values.map { |node| node.y + node.height }.max + BAND_GAP
      end

      # --- routing --------------------------------------------------------------

      # Forward arrows run left to right between the two sides of the boxes;
      # everything else -- a returning arc, and any edge touching the band --
      # bows below, one step deeper per layer it spans so that two returns of
      # different lengths stay apart.
      def route(edges, placed, waypoints, ranking)
        edges.filter_map do |edge|
          from = placed[edge.old_status_id]
          to = placed[edge.new_status_id]
          next if from.nil? || to.nil?

          back = ranking.back_keys.include?(key_of(edge)) || from.band || to.band || from.x >= to.x
          points = back ? bow_points(from, to) : forward_points(from, to, crossings(edge, waypoints, ranking))
          RoutedEdge.new(edge: edge, d: path_for(points), points: points, back: back,
                         conditional: Array(edge.conditions).exclude?('always'))
        end
      end

      # The dummy cells this edge passes through, left to right. Empty for an
      # edge between neighbouring layers, which is most of them.
      def crossings(edge, waypoints, ranking)
        (ranking.crossings[key_of(edge)] || []).filter_map { |key| waypoints[key] }
      end

      # Cubic segments whose control points sit halfway between one waypoint and
      # the next, so the arrow leaves and arrives horizontally.
      #
      # **An edge spanning more than one layer is routed through its dummies**,
      # not drawn as one curve from end to end. One curve is what a first version
      # did, and it bows straight over the node in the layer between -- which is
      # what the dummies were inserted into the ordering to make room for, so
      # ignoring them at routing time threw the room away. It is the difference
      # between "usually tidy" and "always tidy".
      def forward_points(from, to, crossings)
        anchors = [[from.x + from.width, from.center_y]] + crossings + [[to.x, to.center_y]]
        points = [anchors.first]
        anchors.each_cons(2) do |(from_x, from_y), (to_x, to_y)|
          middle = (from_x + to_x) / 2
          points.push([middle, from_y], [middle, to_y], [to_x, to_y])
        end
        points
      end

      # Down out of the bottom of one box, across, and up into the bottom of the
      # other. The arrowhead therefore arrives pointing upwards, which is what
      # tells a returning arc from a forward one at a glance.
      def bow_points(from, to)
        start_point = [from.center_x, from.y + from.height]
        end_point = [to.center_x, to.y + to.height]
        span = ((from.x - to.x).abs / (NODE_WIDTH + LAYER_GAP)) + 1
        base = [start_point.last, end_point.last].max + BOW_DEPTH + (span * BOW_STEP)
        [start_point, [start_point.first, base], [end_point.first, base], end_point]
      end

      # One M and one C per segment. +points+ is therefore always 1 + 3n long,
      # and every one of them is a point the extent has to contain.
      def path_for(points)
        head, *rest = points
        curves = rest.each_slice(3).map do |(c1x, c1y), (c2x, c2y), (end_x, end_y)|
          "C #{c1x} #{c1y} #{c2x} #{c2y} #{end_x} #{end_y}"
        end
        "M #{head[0]} #{head[1]} #{curves.join(' ')}"
      end

      def key_of(edge)
        [edge.old_status_id, edge.new_status_id]
      end

      def both_reachable?(edge, reachable)
        reachable.include?(edge.old_status_id) && reachable.include?(edge.new_status_id)
      end

      # --- the extent -----------------------------------------------------------

      # The viewBox comes from what is drawn: the boxes and every point of every
      # path. A cubic Bezier lies within the hull of its four points, so the
      # bowed arcs are contained rather than merely usually contained.
      #
      # The whole drawing is then translated so that its top left corner is the
      # origin, which keeps the viewBox a plain "0 0 w h" and means no consumer
      # has to deal with negative coordinates.
      def finish(placed, routed, band)
        min_x, min_y, width, height = extent(placed, routed)
        nodes = placed.map { |node| shift_node(node, min_x, min_y) }
        edges = routed.map { |edge| shift_edge(edge, min_x, min_y) }

        Result.new(nodes: nodes, edges: edges, view_box: "0 0 #{width} #{height}",
                   width: width, height: height,
                   band_top: band ? nodes.select(&:band).map(&:y).min : nil)
      end

      # Every corner of every box and every point of every path, padded. Both
      # halves are load-bearing: the paths alone miss a node nothing points at,
      # and the boxes alone clip the arcs.
      def extent(placed, routed)
        corners = placed.flat_map do |node|
          [[node.x, node.y], [node.x + node.width, node.y + node.height]]
        end
        points = corners + routed.flat_map(&:points)
        min_x, width = span(points.map(&:first))
        min_y, height = span(points.map(&:last))
        [min_x, min_y, width, height]
      end

      # One axis: where the drawing starts, and how far it runs, padded at both
      # ends. Returned as a pair so that extent stays two lines rather than eight
      # near-identical ones.
      def span(values)
        [values.min - PADDING, (values.max - values.min) + (2 * PADDING)]
      end

      def shift_node(node, min_x, min_y)
        node.class.new(**node.to_h, x: node.x - min_x, y: node.y - min_y)
      end

      def shift_edge(edge, min_x, min_y)
        points = edge.points.map { |x_value, y_value| [x_value - min_x, y_value - min_y] }
        edge.class.new(**edge.to_h, points: points, d: path_for(points))
      end

      # --- text -----------------------------------------------------------------

      # The name a node carries, wrapped to fit. Core's "new issue" pseudo-status
      # and a row naming a status that no longer exists are both nil records and
      # are told apart by the id -- but naming them is I18n's business, so the
      # caller passes the words in and this only falls back.
      def fitted_name(node)
        WorkflowGraphText.fit(@labels[node.status_id] || node.status&.name || "##{node.status_id}", NODE_WIDTH)
      end
    end
  end
end
