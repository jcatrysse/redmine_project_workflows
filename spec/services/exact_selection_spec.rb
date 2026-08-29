# frozen_string_literal: true

require_relative '../spec_helper'

# WP18, finding F03 of docs/review/findings/2026-08-29-claude-revalidation.md.
#
# The plugin had four selection resolvers with four strictnesses and the least
# strict was the one that writes. This is the one they became. Every example
# here is a shape a request can carry; the controller examples that use it are
# in spec/controllers/project_workflow_rules_controller_spec.rb and
# spec/controllers/project_workflows_controller_spec.rb.
describe RedmineProjectWorkflows::Services::ExactSelection do
  fixtures :projects, :roles, :trackers, :users

  let(:trackers) { Tracker.sorted.to_a }
  let(:first) { trackers.first }
  let(:second) { trackers.second }

  def resolve(param, **options)
    described_class.resolve(param, candidates: trackers, **options)
  end

  describe 'what it resolves' do
    it 'answers with the records a selection named, in candidate order' do
      selection = resolve([second.id.to_s, first.id.to_s])

      expect(selection.records).to eq([first, second])
      expect(selection).to be_exact
    end

    it 'takes a scalar as a selection of one' do
      expect(resolve(first.id.to_s).records).to eq([first])
    end

    it 'treats an id repeated in a selection as one selection, not a missing record' do
      selection = resolve([first.id.to_s, first.id.to_s])

      expect(selection.records).to eq([first])
      expect(selection).to be_exact
    end

    it 'ignores a blank value, which is what an unfilled selector submits' do
      selection = resolve(['', first.id.to_s, nil])

      expect(selection.records).to eq([first])
      expect(selection).to be_exact
    end

    it 'has nothing to resolve and nothing unresolved for no parameter at all' do
      selection = resolve(nil)

      expect(selection.records).to be_empty
      expect(selection).to be_exact
      expect(selection.presence).to be_nil
    end
  end

  # The half the finding is about. Each of these wrote a row and reported
  # "Successful update." before WP18.
  describe 'what it refuses' do
    it 'reports an id that names nothing rather than dropping it' do
      selection = resolve([first.id.to_s, '999999'])

      expect(selection).not_to be_exact
      expect(selection.unresolved).to eq(['999999'])
      expect(selection.records).to eq([first])
    end

    # The one that makes this worse than "dropped": Rails casts the value to the
    # column's type, so `where(id: ['1e5'])` is a query for id 1.
    it 'reports a float-shaped id rather than casting it to the record it rounds to' do
      selection = resolve(['1e5'])

      expect(selection).not_to be_exact
      expect(selection.unresolved).to eq(['1e5'])
      expect(selection.records).to be_empty
    end

    it 'reports a trailing-garbage id rather than casting it' do
      selection = resolve(["#{first.id}abc"])

      expect(selection).not_to be_exact
      expect(selection.records).to be_empty
    end

    it 'reports a negative id, which is a valid query for a row that does not exist' do
      selection = resolve(['-1'])

      expect(selection).not_to be_exact
      expect(selection.unresolved).to eq(['-1'])
    end

    it 'reports a word that is not one of this selector\'s keywords' do
      selection = resolve(['all'])

      expect(selection).not_to be_exact
      expect(selection.unresolved).to eq(['all'])
    end

    # A nested parameter is not a Hash by the time it reaches here, and it must
    # not raise: it is compared as a string against ids the server holds, so it
    # matches nothing and is reported like any other value that names nothing.
    it 'reports a nested parameter rather than raising' do
      selection = resolve([{ 'evil' => '1' }])

      expect(selection).not_to be_exact
      expect(selection.records).to be_empty
    end
  end

  describe 'keywords' do
    it 'keeps a keyword out of the ids and answers that it was chosen' do
      selection = resolve(['all', first.id.to_s], keywords: %w[all])

      expect(selection).to be_exact
      expect(selection).to be_keyword('all')
      expect(selection.records).to eq([first])
    end

    it 'does not answer for a keyword this selector does not accept' do
      selection = resolve(['global'], keywords: %w[all])

      expect(selection).not_to be_keyword('global')
      expect(selection).not_to be_exact
    end
  end

  # The one selector that may name a record its own screen does not offer: an
  # archived project, reached from the inventory by id. The shape check happens
  # before the relation, which is what keeps '1e5' from meaning project 1.
  describe 'resolving against a relation' do
    let(:project) { projects(:projects_001) }

    it 'resolves an id the relation holds' do
      selection = described_class.resolve([project.id.to_s], scope: Project.sorted)

      expect(selection.records).to eq([project])
      expect(selection).to be_exact
    end

    it 'resolves an archived project, which no selector offers' do
      project.update!(status: Project::STATUS_ARCHIVED)

      selection = described_class.resolve([project.id.to_s], scope: Project.sorted)

      expect(selection.ids).to eq([project.id])
    end

    it 'never lets a float-shaped id reach the query' do
      selection = described_class.resolve(['1e5'], scope: Project.sorted)

      expect(selection.records).to be_empty
      expect(selection.unresolved).to eq(['1e5'])
    end
  end
end
