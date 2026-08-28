# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What shape a workflow graph is, before anything has a coordinate (WP9).
    #
    # The first three phases of a layered drawing are about the graph and not
    # about the page: which statuses the entry node can reach, which edges close
    # a cycle, which column each status belongs in, and in what order the things
    # in one column should sit. None of that mentions a pixel. WorkflowGraphLayout
    # is the phase that does, and it was 356 lines before this came out of it --
    # +Metrics/ClassLength+ is relaxed to 200 in +.rubocop.yml+ with a stated
    # rationale, so crossing it is a signal to extract rather than a cop to
    # placate, and "the graph's shape" and "where things go on the page" are two
    # things rather than one.
    #
    # Everything here iterates a list that was sorted first. +order+ is the
    # query's own node order, and it is what makes the answer the same on every
    # Ruby, every database and every seed: which edge of a cycle is called the
    # returning one, and which of two tied nodes sits above the other, are both
    # decided by it rather than by whatever order a hash happened to have.
    class WorkflowGraphRanking
      # +main+ and +band+ are the nodes split by whether the entry node can reach
      # them; +rows+ is one list per layer, holding status ids and dummy keys in
      # the order they should be drawn; +pull+ says which things one layer to the
      # left a thing is joined to, which is what straightens the drawing;
      # +crossings+ is, per edge, the dummy keys it passes through; +back_keys+
      # is the edges that close a cycle.
      Result = Struct.new(:main, :band, :rows, :pull, :crossings, :back_keys, keyword_init: true)

      # A dummy occupies the cell a real node would have had in a layer an edge
      # merely crosses. It is a four-element Array so that it can never collide
      # with a status id, and so a spec can recognise one.
      def self.dummy_key(edge, layer)
        [:dummy, edge.old_status_id, edge.new_status_id, layer]
      end

      def initialize(nodes, edges, order:)
        @nodes = nodes
        @edges = edges
        @order = order
      end

      def result
        reachable = reachable_status_ids
        main, band = @nodes.partition { |node| reachable.include?(node.status_id) }

        back_keys = back_edge_keys(main, reachable)
        forward = @edges.reject { |edge| back_keys.include?(key_of(edge)) || !both_reachable?(edge, reachable) }

        layer_of = assign_layers(main, forward)
        chains = forward.to_h { |edge| [key_of(edge), chain_for(edge, layer_of)] }
        rows = order_rows(main, layer_of, chains)

        Result.new(main: main, band: band, rows: rows, pull: pull_from(chains),
                   crossings: crossings_from(chains), back_keys: back_keys)
      end

      private

      # Phase 0. Which statuses the entry node can get to at all, over every edge
      # -- returning arcs included, because an issue that can come back to a
      # status could get there in the first place. What is left over is the first
      # diagnostic and gets a band of its own rather than a layer.
      def reachable_status_ids
        out = adjacency(@edges)
        seen = Set.new([WorkflowGraphQuery::ENTRY_STATUS_ID])
        queue = [WorkflowGraphQuery::ENTRY_STATUS_ID]
        out.fetch(queue.shift, []).each { |target| queue << target if seen.add?(target) } until queue.empty?
        seen
      end

      def adjacency(edges)
        edges.each_with_object({}) { |edge, map| (map[edge.old_status_id] ||= []) << edge.new_status_id }
      end

      # Phase 1. Depth-first from the entry node; an edge whose target is on the
      # current stack closes a cycle and is *recorded* rather than dropped -- a
      # workflow is full of returns and a drawing that omits them is wrong rather
      # than tidy.
      def back_edge_keys(main, reachable)
        out = adjacency(@edges.select { |edge| both_reachable?(edge, reachable) })
        keys = Set.new
        state = {}
        main.map(&:status_id).each { |root| walk(root, out, state, keys) unless state.key?(root) }
        keys
      end

      # White / grey / black, as an explicit stack rather than recursion: a
      # hundred statuses in a chain would otherwise be a hundred frames deep, and
      # a SystemStackError is a poor way to find that out. A target that is grey
      # -- on the stack right now -- closes a cycle; one that is black is a cross
      # or forward edge and stays in the DAG.
      def walk(root, out, state, keys)
        stack = [[root, 0]]
        state[root] = :open
        until stack.empty?
          node, index = stack.last
          targets = (out[node] || []).sort_by { |target| @order[target] }
          next finish_node(stack, state, node) if index >= targets.size

          stack[-1] = [node, index + 1]
          target = targets[index]
          if state[target] == :open
            keys << [node, target]
          elsif state[target].nil?
            state[target] = :open
            stack << [target, 0]
          end
        end
      end

      def finish_node(stack, state, node)
        state[node] = :done
        stack.pop
      end

      # Phase 2. Longest path: a node sits one layer to the right of the furthest
      # of its forward predecessors. Every reachable node has at least one -- the
      # depth-first tree edge that discovered it, which is never a back edge -- so
      # nothing but the entry node starts at layer 0, and every layer from 0 to
      # the last holds something.
      #
      # Kahn's order over the forward edges, which is a DAG by construction after
      # phase 1. Anything the ordering cannot reach (which the cycle break should
      # make impossible) stays at layer 0 rather than being dropped: a node
      # missing from a drawing is worse than one in the wrong column.
      def assign_layers(main, forward)
        ids = main.map(&:status_id)
        out = adjacency(forward)
        incoming = ids.to_h { |id| [id, 0] }
        forward.each { |edge| incoming[edge.new_status_id] += 1 }
        layer = ids.to_h { |id| [id, 0] }

        queue = ids.select { |id| incoming[id].zero? }.sort_by { |id| @order[id] }
        until queue.empty?
          node = queue.shift
          relax(node, out, layer, incoming, queue)
        end
        layer
      end

      # One node's successors, in the query's node order: each moves at least one
      # layer to the right of it, and joins the queue once nothing else is left
      # pointing at it.
      def relax(node, out, layer, incoming, queue)
        (out[node] || []).sort_by { |target| @order[target] }.each do |target|
          layer[target] = [layer[target], layer[node] + 1].max
          queue << target if (incoming[target] -= 1).zero?
        end
      end

      # One edge as the sequence of (layer, key) it passes through: its own two
      # ends, and a dummy in every layer between them.
      def chain_for(edge, layer_of)
        from = layer_of[edge.old_status_id]
        to = layer_of[edge.new_status_id]
        middle = ((from + 1)...to).map { |layer| [layer, self.class.dummy_key(edge, layer)] }
        [[from, edge.old_status_id]] + middle + [[to, edge.new_status_id]]
      end

      # Phase 3. The median heuristic over four alternating sweeps, seeded with
      # the query's own node order so that a graph with no edges at all still
      # lays out in core's status order.
      #
      # An edge spanning more than one layer is represented by a dummy in each
      # layer it crosses, so the ordering keeps room for it. Bowing such an edge
      # over the intervening node is what a first version did, and it is the
      # difference between "usually tidy" and "always tidy".
      def order_rows(main, layer_of, chains)
        rows = seed_rows(main, layer_of, chains)
        neighbours = neighbours_from(chains)
        4.times { |sweep| sweep_once(rows, neighbours, sweep) }
        rows
      end

      # One list per layer, in the query's own node order, with each edge's
      # dummies appended to the layers it crosses.
      def seed_rows(main, layer_of, chains)
        rows = Hash.new { |hash, key| hash[key] = [] }
        main.sort_by { |node| @order[node.status_id] }
            .each { |node| rows[layer_of[node.status_id]] << node.status_id }
        chains.each_value { |chain| chain[1..-2].each { |layer, key| rows[layer] << key } }
        rows.keys.sort.to_h { |layer| [layer, rows[layer]] }
      end

      # Down the layers reading what points at a thing, then up the layers
      # reading what it points at, twice each.
      def sweep_once(rows, neighbours, sweep)
        side = sweep.odd? ? :down : :up
        layers = sweep.odd? ? rows.keys.sort.reverse : rows.keys.sort
        layers.each { |layer| rows[layer] = sort_by_median(rows[layer], neighbours[side]) }
      end

      # For every element of every layer, which elements of the layer before it
      # (:up) and after it (:down) it is joined to. A dummy chains to the next
      # dummy of the same edge, which is what makes a long edge behave like a
      # straight line under the median.
      def neighbours_from(chains)
        up = Hash.new { |hash, key| hash[key] = [] }
        down = Hash.new { |hash, key| hash[key] = [] }
        chains.each_value do |chain|
          chain.each_cons(2) do |(_from_layer, from_key), (_to_layer, to_key)|
            up[to_key] << from_key
            down[from_key] << to_key
          end
        end
        { up: up, down: down }
      end

      def pull_from(chains)
        neighbours_from(chains)[:up]
      end

      def crossings_from(chains)
        chains.transform_values { |chain| chain[1..-2].map { |(_layer, key)| key } }
      end

      # The median of a thing's neighbours' current positions. A thing with no
      # neighbour on that side keeps where it is, which stops a sweep from
      # shuffling an isolated node to the top; ties break on the current
      # position, so the sort does not depend on Ruby's sort being stable.
      def sort_by_median(row, neighbours)
        positions = row.each_with_index.to_h
        row.sort_by do |key|
          list = neighbours[key].filter_map { |neighbour| positions[neighbour] }.sort
          [list.empty? ? positions[key] : list[list.size / 2], positions[key]]
        end
      end

      def key_of(edge)
        [edge.old_status_id, edge.new_status_id]
      end

      def both_reachable?(edge, reachable)
        reachable.include?(edge.old_status_id) && reachable.include?(edge.new_status_id)
      end
    end
  end
end
