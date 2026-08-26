# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::InventoryQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }

  let(:projects_list) { [project, other_project] }
  let(:trackers_list) { [tracker, other_tracker] }
  let(:roles_list)    { [role, other_role] }

  def build(deviations_only: true, rule_types: ProjectWorkflowScope::RULE_TYPES,
            projects: projects_list, trackers: trackers_list, roles: roles_list)
    described_class.new(projects: projects, trackers: trackers, roles: roles,
                        rule_types: rule_types, deviations_only: deviations_only)
  end

  def transition(project_id)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: s1.id, new_status_id: s2.id,
                               project_id: project_id)
  end

  def all_rows(query)
    query.rows(offset: 0, limit: query.total)
  end

  describe 'the three states' do
    it 'reports a scope with rules as an own workflow' do
      give_own_workflow(project, tracker, role)
      transition(project.id)

      cell = all_rows(build).first.cells[ProjectWorkflowScope::TRANSITIONS]

      expect(cell.state).to eq(:own)
      expect(cell.rule_count).to eq(1)
    end

    it 'reports a scope without rules as an own empty workflow' do
      give_own_workflow(project, tracker, role)

      cell = all_rows(build).first.cells[ProjectWorkflowScope::TRANSITIONS]

      expect(cell.state).to eq(:own_empty)
      expect(cell.rule_count).to eq(0)
    end

    it 'reports a combination without a scope as inheriting' do
      cell = all_rows(build(deviations_only: false)).first.cells[ProjectWorkflowScope::TRANSITIONS]

      expect(cell.state).to eq(:inherits)
    end

    # INV-3: the two rule types are separate decisions, so one row can be in
    # two different states at once.
    it 'answers per rule type' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      row = all_rows(build).first

      expect(row.cells[ProjectWorkflowScope::PERMISSIONS].state).to eq(:own_empty)
      expect(row.cells[ProjectWorkflowScope::TRANSITIONS].state).to eq(:inherits)
    end
  end

  # INV-4. The generic rules are a different population and must never be
  # counted into a project's row -- which is exactly the defect WP3 repairs on
  # the summary page.
  it 'never counts a generic rule towards a project' do
    give_own_workflow(project, tracker, role)
    transition(nil)
    transition(nil)

    cell = all_rows(build).first.cells[ProjectWorkflowScope::TRANSITIONS]

    expect(cell.rule_count).to eq(0)
    expect(cell.state).to eq(:own_empty)
  end

  it 'never counts another project\'s rules' do
    give_own_workflow(project, tracker, role)
    transition(other_project.id)

    cell = all_rows(build).first.cells[ProjectWorkflowScope::TRANSITIONS]

    expect(cell.rule_count).to eq(0)
  end

  describe 'the two modes' do
    it 'lists only the combinations that decided something' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, other_tracker, other_role)

      rows = all_rows(build)

      expect(rows.size).to eq(2)
      expect(rows.map { |row| [row.project.id, row.tracker.id, row.role.id] })
        .to eq([[project.id, tracker.id, role.id],
                [other_project.id, other_tracker.id, other_role.id]])
    end

    it 'lists every combination when deviations are not the filter' do
      expect(build(deviations_only: false).total).to eq(2 * 2 * 2)
    end

    it 'reports nothing when no project decided anything' do
      query = build
      expect(query.total).to eq(0)
      expect(all_rows(query)).to eq([])
    end

    it 'restricts the deviations to the rule type asked for' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      expect(build(rule_types: [ProjectWorkflowScope::TRANSITIONS]).total).to eq(0)
      expect(build(rule_types: [ProjectWorkflowScope::PERMISSIONS]).total).to eq(1)
    end
  end

  describe 'paging' do
    # The full product is never built, so the arithmetic that addresses a page
    # of it is the thing that can be wrong. Walking it one row at a time has to
    # produce the same sequence as taking it in one slice.
    it 'walks the product in the order of the three lists' do
      query = build(deviations_only: false)
      one_at_a_time = (0...query.total).flat_map { |offset| query.rows(offset: offset, limit: 1) }

      expect(one_at_a_time.map { |row| [row.project.id, row.tracker.id, row.role.id] })
        .to eq(projects_list.flat_map do |a|
          trackers_list.flat_map { |b| roles_list.map { |c| [a.id, b.id, c.id] } }
        end)
    end

    it 'pages the deviations' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, other_tracker, other_role)
      query = build

      expect(query.rows(offset: 0, limit: 1).map { |row| row.project.id }).to eq([project.id])
      expect(query.rows(offset: 1, limit: 1).map { |row| row.project.id }).to eq([other_project.id])
    end

    it 'answers an offset past the end with nothing' do
      expect(build(deviations_only: false).rows(offset: 999, limit: 25)).to eq([])
    end

    it 'answers a limit of zero with nothing' do
      expect(build(deviations_only: false).rows(offset: 0, limit: 0)).to eq([])
    end
  end

  describe 'an empty filter' do
    it 'has nothing to list when no project is left' do
      give_own_workflow(project, tracker, role)
      query = build(projects: [])

      expect(query.total).to eq(0)
      expect(all_rows(query)).to eq([])
    end

    it 'has nothing to list when no tracker is left' do
      expect(build(deviations_only: false, trackers: []).total).to eq(0)
      expect(build(deviations_only: false, trackers: []).rows(offset: 0, limit: 25)).to eq([])
    end

    it 'has nothing to list when no role is left' do
      give_own_workflow(project, tracker, role)
      expect(build(roles: []).total).to eq(0)
    end
  end

  # G6: a page is a fixed number of statements whatever it contains, and never
  # one per row.
  it 'costs the same number of queries whatever the page holds' do
    give_own_workflow(project, tracker, role)
    give_own_workflow(other_project, other_tracker, other_role)
    transition(project.id)

    ignored = %w[SCHEMA TRANSACTION]
    counts = [1, 2].map do |limit|
      statements = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        statements += 1 unless ignored.include?(payload[:name])
      end
      begin
        query = build
        query.total
        query.rows(offset: 0, limit: limit)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
      statements
    end

    expect(counts.first).to eq(counts.last)
  end

  # WP6: who last changed this workflow, carried by the cell so the view asks
  # nothing itself.
  describe 'the audit trail' do
    let(:editor) { users(:users_002) }

    def stamped_scope(target = project)
      scope = give_own_workflow(target, tracker, role)
      scope.update_columns(updated_by_id: editor.id, updated_at: Time.now.utc) # rubocop:disable Rails/SkipsModelValidations
      scope
    end

    it 'carries who changed the rules and when' do
      stamped_scope
      transition(project.id)

      cell = all_rows(build).first.cells[ProjectWorkflowScope::TRANSITIONS]

      expect(cell.updated_by).to eq(editor)
      expect(cell.updated_on).to be_present
    end

    # An inheriting combination has no scope row, so there is nothing to name.
    it 'carries nothing for an inheriting combination' do
      stamped_scope

      cell = all_rows(build).first.cells[ProjectWorkflowScope::PERMISSIONS]

      expect(cell.state).to eq(:inherits)
      expect(cell.updated_by).to be_nil
      expect(cell.updated_on).to be_nil
    end

    # The backfill and every other write with nobody logged in leave the time
    # and no author.
    it 'carries a time but no author where the write had no user behind it' do
      give_own_workflow(project, tracker, role)

      cell = all_rows(build).first.cells[ProjectWorkflowScope::TRANSITIONS]

      expect(cell.updated_on).to be_present
      expect(cell.updated_by).to be_nil
    end

    # G6, and the reason the users are loaded in build_rows rather than in the
    # view: the plain query-count example above stamps nobody, so it would pass
    # even if this were one query per cell.
    it 'loads the users named on the page in one query however many rows there are' do
      stamped_scope
      stamped_scope(other_project)
      transition(project.id)

      # Force the three fixture lists before anything is counted. They are
      # memoised `let`s, so leaving them to `build` resolves them inside the
      # first counted block and nowhere else -- two SELECTs that look exactly
      # like an N+1 and are not.
      projects_list && trackers_list && roles_list

      ignored = %w[SCHEMA TRANSACTION]
      counts = [1, 2].map do |limit|
        statements = 0
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          statements += 1 unless ignored.include?(payload[:name])
        end
        begin
          query = build
          query.total
          query.rows(offset: 0, limit: limit)
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        statements
      end

      expect(counts.first).to eq(counts.last)
    end
  end
end
