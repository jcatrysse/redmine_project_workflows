# frozen_string_literal: true

require_relative '../spec_helper'

# WP9. Where the boxes and the arrows go.
#
# The class under test touches no database, so this file builds its input by
# hand. That is the point of it being a pure function: a layered drawing is hard
# to assert anything about when the graph came out of a query, and every
# interesting case here -- a cycle, an unreachable status, an edge spanning three
# layers -- is a nuisance to arrange as workflow rows and trivial to write down.
#
# Two properties carry the weight:
#
# * **The viewBox contains every drawn path.** A returning arc bows below the
#   rows, and a viewBox built from the node positions alone clips it -- which
#   renders silently, with no error anywhere, and is only visible to somebody
#   looking at the picture. There is an example that fails on exactly that
#   implementation.
# * **The same input gives the same output.** Byte-identical, twice, including
#   the path data. This is what stops the drawing from depending on a hash
#   order, a planner or a random seed, which would show up as one red cell out
#   of nine.
describe RedmineProjectWorkflows::Services::WorkflowGraphLayout do
  let(:query) { RedmineProjectWorkflows::Services::WorkflowGraphQuery }

  # A node with no IssueStatus behind it: the layout never asks a status
  # anything but its name, and the name arrives through +labels+, so a plain
  # id is the whole of what it needs.
  def node(status_id, mentioned: true)
    query::Node.new(status_id: status_id, status: nil, mentioned: mentioned)
  end

  def edge(from, to, conditions: ['always'])
    query::Edge.new(old_status_id: from, old_status: nil, new_status_id: to, new_status: nil,
                    conditions: conditions, roles: [])
  end

  def graph(nodes, edges, role_states: [:own])
    states = role_states.each_with_index.map do |state, index|
      query::RoleState.new(role: Struct.new(:id, :name).new(index + 1, "Role #{index + 1}"), state: state)
    end
    query::Result.new(nodes: nodes, edges: edges, role_states: states)
  end

  # 0 is core's "new issue" node; 1..n stand in for statuses.
  def labels_for(*ids)
    ids.to_h { |id| [id, id.zero? ? 'New issue' : "Status #{id}"] }
  end

  def layout_for(nodes, edges, labels: nil, **options)
    ids = nodes.map(&:status_id)
    described_class.new(graph(nodes, edges, **options), labels: labels || labels_for(*ids)).result
  end

  # A -> B -> C, plus the entry node into A. Four layers, one node each.
  let(:chain_nodes) { [node(0), node(1), node(2), node(3)] }
  let(:chain_edges) { [edge(0, 1), edge(1, 2), edge(2, 3)] }

  describe 'layers' do
    it 'puts a chain in one column per step, left to right' do
      result = layout_for(chain_nodes, chain_edges)

      xs = result.drawn_nodes.sort_by { |placed| placed.node.status_id }.map(&:x)
      expect(xs).to eq(xs.sort)
      expect(xs.uniq.size).to eq(4)
      expect(result.drawn_nodes.map { |placed| placed.node.status_id }).to contain_exactly(0, 1, 2, 3)
    end

    it 'gives a node the layer of its longest path, not its shortest' do
      # 0 -> 1 -> 2 -> 3 and 0 -> 3. The direct edge must not pull 3 back to
      # layer 1: an arrow that runs backwards through the drawing is exactly
      # what layering exists to prevent.
      result = layout_for(chain_nodes, chain_edges + [edge(0, 3)])

      by_id = result.drawn_nodes.index_by { |placed| placed.node.status_id }
      expect(by_id[3].layer).to eq(3)
      expect(by_id[3].x).to be > by_id[2].x
    end

    it 'terminates on a cycle and draws every node of it' do
      # 0 -> 1 -> 2 -> 1: the second edge into 1 closes a loop. Without the
      # cycle break the longest-path pass does not terminate.
      result = layout_for([node(0), node(1), node(2)], [edge(0, 1), edge(1, 2), edge(2, 1)])

      expect(result.drawn_nodes.map { |placed| placed.node.status_id }).to contain_exactly(0, 1, 2)
      expect(result.edges.size).to eq(3)
    end

    it 'keeps the returning edge of a cycle rather than dropping it' do
      result = layout_for([node(0), node(1), node(2)], [edge(0, 1), edge(1, 2), edge(2, 1)])

      returning = result.edges.select(&:back)
      expect(returning.map { |routed| [routed.edge.old_status_id, routed.edge.new_status_id] }).to eq([[2, 1]])
    end
  end

  describe 'the band below the drawing' do
    it 'puts a status the entry node cannot reach below every layered node' do
      # 4 is named by a rule between 4 and 5 but nothing leads into 4 from the
      # entry, so neither is reachable and both belong in the band.
      nodes = chain_nodes + [node(4), node(5)]
      result = layout_for(nodes, chain_edges + [edge(4, 5)])

      band = result.band_nodes.map { |placed| placed.node.status_id }
      expect(band).to contain_exactly(4, 5)
      expect(result.band_top).to eq(result.band_nodes.map(&:y).min)
      expect(result.band_nodes.map(&:y).min).to be > result.drawn_nodes.map { |placed| placed.y + placed.height }.max
    end

    it 'puts a status no rule mentions in the band too' do
      nodes = chain_nodes + [node(9, mentioned: false)]
      result = layout_for(nodes, chain_edges)

      expect(result.band_nodes.map { |placed| placed.node.status_id }).to eq([9])
    end

    it 'has no band at all when everything is reachable' do
      result = layout_for(chain_nodes, chain_edges)

      expect(result.band_nodes).to be_empty
      expect(result.band_top).to be_nil
    end

    # Finding F04. The band used to be one flat row in query order, with every
    # edge among its members drawn as a bow underneath it -- so a band holding a
    # chain of four produced three near-identical arcs stacked under one row and
    # nothing could be told from any of them. It now gets the same three phases
    # the main graph gets, on its own sub-graph.
    #
    # Red against the previous commit: 4, 5, 6 and 7 all sat at y = band_top on
    # four increasing x values in query order, and every one of these edges came
    # back with +back+ true.
    it 'lays a chain inside the band out in columns of its own' do
      nodes = chain_nodes + [node(4), node(5), node(6)]
      band_edges = [edge(4, 5), edge(5, 6)]
      result = layout_for(nodes, chain_edges + band_edges)

      band = result.band_nodes.index_by { |placed| placed.node.status_id }
      expect(band.values.map(&:layer)).to contain_exactly(0, 1, 2)
      expect(band[4].x).to be < band[5].x
      expect(band[5].x).to be < band[6].x
    end

    it 'draws an edge inside the band as a forward arrow rather than a bow' do
      nodes = chain_nodes + [node(4), node(5)]
      result = layout_for(nodes, chain_edges + [edge(4, 5)])

      inside = result.edges.detect { |routed| routed.edge.old_status_id == 4 }
      expect(inside.back).to be(false)
    end

    it 'still bows an edge that returns inside the band' do
      # 4 -> 5 -> 4 is a cycle: one of the two closes it and has to come back
      # leftwards, which is the one thing a layered drawing cannot do with a
      # straight arrow.
      nodes = chain_nodes + [node(4), node(5)]
      result = layout_for(nodes, chain_edges + [edge(4, 5), edge(5, 4)])

      band_ids = [4, 5]
      inside = result.edges.select { |routed| band_ids.include?(routed.edge.old_status_id) }
      expect(inside.map(&:back)).to contain_exactly(false, true)
      expect(result.band_nodes.map { |placed| placed.node.status_id }).to contain_exactly(4, 5)
    end

    it 'still bows an edge that leaves the band for the drawing above it' do
      # The two blocks are stacked, so there is no left-to-right reading of an
      # edge between them however their columns happen to line up.
      nodes = chain_nodes + [node(4)]
      result = layout_for(nodes, chain_edges + [edge(4, 2)])

      expect(result.edges.detect { |routed| routed.edge.old_status_id == 4 }.back).to be(true)
    end

    it 'keeps the whole band below the drawing once the band has layers of its own' do
      nodes = chain_nodes + [node(4), node(5), node(6)]
      result = layout_for(nodes, chain_edges + [edge(4, 5), edge(5, 6)])

      lowest = result.drawn_nodes.map { |placed| placed.y + placed.height }.max
      expect(result.band_nodes.map(&:y).min).to be > lowest
      expect(result.band_top).to eq(result.band_nodes.map(&:y).min)
    end
  end

  describe 'an own empty workflow' do
    it 'lays out as the entry node and nothing else' do
      # Every status the tracker uses is in the graph as unmentioned, because
      # some other role's rules name them. The drawing is still one node: "no
      # role of yours may move an issue anywhere" is a sentence, not a band of
      # thirty boxes.
      nodes = [node(0)] + (1..5).map { |id| node(id, mentioned: false) }
      result = layout_for(nodes, [], role_states: [:own_empty])

      expect(result.nodes.map { |placed| placed.node.status_id }).to eq([0])
      expect(result.edges).to be_empty
      expect(result.band_nodes).to be_empty
    end

    it 'is empty when no role takes part in a workflow at all' do
      result = layout_for([], [], role_states: [])

      expect(result).to be_empty
      expect(result.view_box).to eq('0 0 0 0')
    end
  end

  describe 'the viewBox' do
    # The regression the plan names. A drawing with a long returning arc is the
    # case where sizing from the node positions is visibly wrong.
    let(:bowed) { layout_for(chain_nodes, chain_edges + [edge(3, 1)]) }

    it 'contains every point of every path' do
      _, _, width, height = bowed.view_box.split.map(&:to_i)

      bowed.edges.each do |routed|
        routed.points.each do |x, y|
          expect(x).to be_between(0, width), "x #{x} outside the viewBox for #{routed.d}"
          expect(y).to be_between(0, height), "y #{y} outside the viewBox for #{routed.d}"
        end
      end
    end

    it 'is taller than the nodes alone, because the returning arc bows below them' do
      # This is the assertion the naive implementation fails: without it, every
      # other example here passes on a viewBox that clips the arc.
      nodes_bottom = bowed.nodes.map { |placed| placed.y + placed.height }.max
      arc_bottom = bowed.edges.select(&:back).flat_map { |routed| routed.points.map(&:last) }.max
      _, _, _, height = bowed.view_box.split.map(&:to_i)

      expect(arc_bottom).to be > nodes_bottom
      expect(height).to be >= arc_bottom
    end

    it 'contains every node box' do
      _, _, width, height = bowed.view_box.split.map(&:to_i)

      bowed.nodes.each do |placed|
        expect(placed.x).to be >= 0
        expect(placed.y).to be >= 0
        expect(placed.x + placed.width).to be <= width
        expect(placed.y + placed.height).to be <= height
      end
    end

    it 'starts at the origin whatever the arcs did' do
      expect(bowed.view_box).to start_with('0 0 ')
    end

    # The band is a grid of its own since finding F04, so it has returning arcs
    # of its own, below a block that did not exist when the extent was written.
    it 'contains the band and its own returning arcs' do
      nodes = chain_nodes + [node(4), node(5), node(6)]
      banded = layout_for(nodes, chain_edges + [edge(4, 5), edge(5, 6), edge(6, 4)])
      _, _, width, height = banded.view_box.split.map(&:to_i)

      expect(banded.band_nodes.size).to eq(3)
      banded.edges.each do |routed|
        routed.points.each do |x, y|
          expect(x).to be_between(0, width), "x #{x} outside the viewBox for #{routed.d}"
          expect(y).to be_between(0, height), "y #{y} outside the viewBox for #{routed.d}"
        end
      end
      banded.nodes.each do |placed|
        expect(placed.y + placed.height).to be <= height
        expect(placed.x + placed.width).to be <= width
      end
    end
  end

  describe 'determinism' do
    it 'gives byte-identical output for the same input twice' do
      first = layout_for(chain_nodes, chain_edges + [edge(3, 1), edge(0, 3)])
      second = layout_for(chain_nodes, chain_edges + [edge(3, 1), edge(0, 3)])

      expect(second.view_box).to eq(first.view_box)
      expect(second.nodes.map { |placed| [placed.node.status_id, placed.x, placed.y] })
        .to eq(first.nodes.map { |placed| [placed.node.status_id, placed.x, placed.y] })
      expect(second.edges.map(&:d)).to eq(first.edges.map(&:d))
    end

    it 'does not depend on the order the edges arrive in' do
      # The query sorts its edges; this asserts the layout does not quietly rely
      # on having been handed them in any particular order beyond that.
      edges = chain_edges + [edge(3, 1)]
      expect(layout_for(chain_nodes, edges).edges.map(&:d))
        .to eq(layout_for(chain_nodes, edges.reverse).edges.map(&:d).reverse)
    end

    it 'produces only integers in its path data' do
      # A midpoint computed in floating point is a string that can differ in its
      # last digit between platforms, which would make "identical output" a claim
      # about a formatter rather than about the layout.
      layout_for(chain_nodes, chain_edges + [edge(3, 1)]).edges.each do |routed|
        expect(routed.d).to match(/\A[MC0-9 -]+\z/)
        expect(routed.d).not_to include('.')
      end
    end
  end

  describe 'the text in a node' do
    it 'wraps a long name onto two lines' do
      result = layout_for([node(0), node(1)], [edge(0, 1)], labels: { 0 => 'New issue', 1 => 'Waiting for input' })

      placed = result.nodes.detect { |candidate| candidate.node.status_id == 1 }
      expect(placed.lines.size).to eq(2)
      expect(placed.lines.join(' ')).to eq('Waiting for input')
      expect(placed.truncated).to be(false)
    end

    it 'truncates beyond two lines and says so, so the title is worth rendering' do
      long = "Waiting for the customer's answer about the invoice"
      result = layout_for([node(0), node(1)], [edge(0, 1)], labels: { 0 => 'New issue', 1 => long })

      placed = result.nodes.detect { |candidate| candidate.node.status_id == 1 }
      expect(placed.lines.size).to eq(2)
      expect(placed.truncated).to be(true)
      expect(placed.lines.last).to end_with('…')
    end

    it 'falls back to the status name when no label was passed' do
      status = Struct.new(:name).new('Resolved')
      nodes = [node(0), query::Node.new(status_id: 7, status: status, mentioned: true)]
      result = described_class.new(graph(nodes, [edge(0, 7)]), labels: { 0 => 'New issue' }).result

      placed = result.nodes.detect { |candidate| candidate.node.status_id == 7 }
      expect(placed.lines).to eq(['Resolved'])
    end
  end

  describe 'what a routed edge carries' do
    it 'marks a conditional move so the renderer can draw it differently' do
      result = layout_for([node(0), node(1), node(2)],
                          [edge(0, 1), edge(1, 2, conditions: %w[author])])

      by_pair = result.edges.index_by { |routed| [routed.edge.old_status_id, routed.edge.new_status_id] }
      expect(by_pair[[0, 1]].conditional).to be(false)
      expect(by_pair[[1, 2]].conditional).to be(true)
    end

    it 'draws a forward edge from the right of one box to the left of the next' do
      result = layout_for([node(0), node(1)], [edge(0, 1)])

      routed = result.edges.first
      by_id = result.nodes.index_by { |placed| placed.node.status_id }
      expect(routed.back).to be(false)
      expect(routed.points.first).to eq([by_id[0].x + by_id[0].width, by_id[0].center_y])
      expect(routed.points.last).to eq([by_id[1].x, by_id[1].center_y])
    end

    it 'draws a returning arc out of the bottom of one box and into the bottom of the other' do
      result = layout_for(chain_nodes, chain_edges + [edge(3, 1)])

      routed = result.edges.detect(&:back)
      by_id = result.nodes.index_by { |placed| placed.node.status_id }
      expect(routed.points.first).to eq([by_id[3].center_x, by_id[3].y + by_id[3].height])
      expect(routed.points.last).to eq([by_id[1].center_x, by_id[1].y + by_id[1].height])
    end
  end

  describe 'an edge spanning more than one layer' do
    let(:spanning) do
      result = layout_for(chain_nodes, chain_edges + [edge(0, 2)])
      [result, result.edges.detect do |candidate|
        candidate.edge.old_status_id.zero? && candidate.edge.new_status_id == 2
      end]
    end

    it 'is drawn as a forward arrow rather than a returning arc' do
      expect(spanning.last.back).to be(false)
    end

    it 'is routed through the layer it crosses rather than over the node in it' do
      # The dummy in the intervening layer is what buys this. Without it the
      # edge is one curve from end to end, and it passes straight through the
      # box of the node between -- which is what the ordering pass had made room
      # for, thrown away at routing time. Both halves are asserted: the path has
      # a point in that column at all, and none of them is on the node's line.
      result, routed = spanning
      crossed = result.nodes.detect { |placed| placed.node.status_id == 1 }
      inside_its_column = routed.points.select { |x, _| x > crossed.x && x < crossed.x + crossed.width }

      expect(inside_its_column).not_to be_empty
      expect(inside_its_column.map(&:last)).to all(satisfy { |y| y != crossed.center_y })
    end
  end
end
