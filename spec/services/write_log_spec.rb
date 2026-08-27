# frozen_string_literal: true

require_relative '../spec_helper'

# F19. An administration save can rewrite thousands of rules across every
# project in one transaction, and afterwards the only record was a flash message
# the operator had already navigated away from. `grep Rails.logger` over app/ and
# lib/ had one hit, in the Deface loader's rescue.
#
# The examples about *what may not be logged* matter more than the ones about
# format: the rule is ids and counts only, never issue content, never a request
# payload, never matrix data, and an actor id rather than a login.
describe RedmineProjectWorkflows::Services::WriteLog do
  # A real Logger over a StringIO rather than a double: what is being asserted is
  # the text that reaches a log file, and a double would let a formatting change
  # pass. (rspec-mocks also refuses to stub from an `around` hook, which is where
  # the first draft put this.)
  let(:sink) { StringIO.new }
  let(:lines) { sink.string.lines.map(&:chomp).reject(&:empty?) }

  before do
    logger = Logger.new(sink)
    logger.formatter = proc { |_severity, _time, _progname, message| "#{message}\n" }
    allow(Rails).to receive(:logger).and_return(logger)
  end

  it 'prefixes every line with the plugin id and names the action' do
    described_class.record('admin_matrix_save', written: 3)

    expect(lines).to contain_exactly('[redmine_project_workflows] admin_matrix_save written=3')
  end

  it 'renders an id list, with the generic workflow named rather than dropped' do
    described_class.record('admin_scope_action', projects: [nil, 7, 9])

    expect(lines.first).to include('projects=generic,7,9')
  end

  it 'renders a selection larger than the cap as a count' do
    described_class.record('admin_scope_action', projects: (1..50).to_a)

    expect(lines.first).to include('projects=count:50')
    expect(lines.first).not_to include('projects=1,2')
  end

  it 'drops a field that was not given' do
    described_class.record('project_matrix_save', project: 1, tracker: nil, role: 2)

    expect(lines.first).to eq('[redmine_project_workflows] project_matrix_save project=1 role=2')
  end

  # The rule this class exists to hold in one place. A field it does not
  # recognise is far more likely to be something that must not be logged than
  # something worth logging, so it says the class name and nothing else.
  it 'never writes the contents of a value it does not recognise' do
    matrix = { '1' => { '2' => { 'always' => '1' } } }

    described_class.record('project_matrix_save', payload: matrix, issue: 'Confidential subject line')

    expect(lines.first).to include('payload=Hash')
    expect(lines.first).not_to include('always')
    expect(lines.first).not_to include('Confidential')
  end

  it 'survives a Rails.logger that is not there' do
    allow(Rails).to receive(:logger).and_return(nil)

    expect { described_class.record('admin_matrix_save', written: 1) }.not_to raise_error
  end
end

# The service is only worth having if the four write paths call it. Asserted on a
# real save through the real controller, because "I added a logger" and "the
# write is logged" are different claims.
describe 'what a real save writes to the log' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:sink) { StringIO.new }
  let(:lines) { sink.string.lines.map(&:chomp).reject(&:empty?) }
  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  before do
    logger = Logger.new(sink)
    logger.formatter = proc { |_severity, _time, _progname, message| "#{message}\n" }
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe WorkflowsController, type: :controller do
    render_views false

    before { @request.session[:user_id] = 1 }

    it 'records an administration matrix save with its counts and no matrix' do
      give_own_workflow(project, tracker, role)

      patch :update, params: {
        role_id: [role.id], tracker_id: [tracker.id], used_statuses_only: '0',
        project_id: [project.id.to_s],
        transitions: { old_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      }

      line = lines.grep(/admin_matrix_save/).first
      expect(line).to be_present
      expect(line).to include('actor=1')
      expect(line).to include("projects=#{project.id}")
      expect(line).to include('written=1')
      # The matrix itself must not be there.
      expect(line).not_to include('always')
    end
  end
end
