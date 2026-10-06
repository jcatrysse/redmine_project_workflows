# frozen_string_literal: true

require_relative 'spec_helper'
require 'tmpdir'
require 'fileutils'

# WP16. The uninstall task is the one destructive thing this plugin ships, and
# what makes it survivable is its *order*: count what is about to be lost, say
# so, ask, write the backup and read it back, and only then reverse the
# migrations. Every one of those steps is only worth anything where it is, so
# this file asserts the order rather than the outcome.
#
# The migrations themselves are not run here -- `reverse_migrations` is the one
# thing stubbed, because an example that dropped the plugin's tables would take
# the rest of the suite with it. dev/check-uninstall.sh runs the real thing
# against a real database on all nine cells.
describe RedmineProjectWorkflows::Tasks do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, 'backup.json') }
  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: issue_statuses(:issue_statuses_001).id,
                               new_status_id: issue_statuses(:issue_statuses_002).id)
    allow(described_class).to receive(:reverse_migrations)
  end

  after do
    FileUtils.remove_entry(dir)
    %w[FILE CONFIRM FORCE SKIP_BACKUP OVERWRITE].each { |key| ENV.delete(key) }
  end

  # Returns what the task printed, whether it exited, and what it refused with.
  # `abort` raises SystemExit, so a helper that let it through would lose the
  # output printed before it -- which is the half these examples are about.
  #
  # Standard error is captured separately rather than mixed in: `abort` writes
  # its message there, and examples printing a refusal into the middle of the
  # suite's output read like failures. It is returned third so that the
  # examples which only want the first two can keep destructuring two.
  def capture
    original = [$stdout, $stderr]
    buffer = StringIO.new
    errors = StringIO.new
    $stdout = buffer
    $stderr = errors
    exited = false
    begin
      yield
    rescue SystemExit
      exited = true
    end
    [buffer.string, exited, errors.string]
  ensure
    $stdout, $stderr = original
  end

  # WP17. The uninstall task's counterpart: the restore is the one thing here
  # that runs unattended -- from an installer, a container entrypoint, a
  # colleague's script after a database restore -- and a run that could not put
  # a combination back has to say so in the only channel a script reads.
  describe '.restore' do
    let(:writer) { RedmineProjectWorkflows::Services::TransitionWriter }

    it 'prints what it did and exits zero when everything came back' do
      document = RedmineProjectWorkflows::Services::WorkflowBackup.document
      WorkflowRule.where.not(project_id: nil).delete_all
      ProjectWorkflowScope.where.not(project_id: nil).delete_all

      output, exited = capture { described_class.restore(document) }

      expect(exited).to be(false)
      expect(output).to include('1 project workflow restored')
    end

    it 'names the failure and exits non-zero when a combination could not be put back' do
      document = RedmineProjectWorkflows::Services::WorkflowBackup.document
      WorkflowRule.where.not(project_id: nil).delete_all
      ProjectWorkflowScope.where.not(project_id: nil).delete_all
      allow(writer).to receive(:replace_transitions_for_project_id)
        .and_raise(ActiveRecord::StatementInvalid, 'simulated: connection lost')

      output, exited = capture { described_class.restore(document) }

      expect(exited).to be(true)
      expect(output).to include('run the restore again to retry them')
      expect(output).to match(/project #{project.id}, tracker #{tracker.id}/)
    end
  end

  describe '.uninstall' do
    it 'reverses nothing and writes no file without CONFIRM=yes' do
      ENV['FILE'] = path

      _output, exited = capture { described_class.uninstall }

      expect(exited).to be(true)
      expect(described_class).not_to have_received(:reverse_migrations)
      expect(File.exist?(path)).to be(false)
    end

    # The count has to be taken before the migrations run, and the operator has
    # to be told what it is: a confirmation asked without a number is a
    # confirmation of nothing.
    it 'says what is about to be discarded before it asks' do
      ENV['FILE'] = path

      output, exited = capture { described_class.uninstall }

      expect(exited).to be(true)
      expect(output).to include('delete every workflow rule that names a project')
      expect(output).to include('1 project workflow, 1 rule')
    end

    it 'refuses without FILE=, before it exports anything' do
      ENV['CONFIRM'] = 'yes'

      _output, exited = capture { described_class.uninstall }

      expect(exited).to be(true)
      expect(described_class).not_to have_received(:reverse_migrations)
    end

    it 'writes a readable backup before it reverses anything' do
      ENV['FILE'] = path
      ENV['CONFIRM'] = 'yes'
      # The file has to exist and parse at the moment the migrations are asked
      # for, not merely by the end of the task.
      allow(described_class).to receive(:reverse_migrations) do
        expect(RedmineProjectWorkflows::Services::WorkflowBackup.read(path)['rules'].size).to eq(1)
      end

      capture { described_class.uninstall }

      expect(described_class).to have_received(:reverse_migrations)
    end

    it 'reverses the migrations with no backup when SKIP_BACKUP is given, and says so' do
      ENV['CONFIRM'] = 'yes'
      ENV['SKIP_BACKUP'] = '1'

      output, = capture { described_class.uninstall }

      expect(output).to include('no backup will be written')
      expect(described_class).to have_received(:reverse_migrations)
      expect(Dir.children(dir)).to be_empty
    end

    # WP17. The confirmation is a question put to a human, and a human takes
    # seconds to answer it. On a production installation that is long enough for
    # a colleague to save a workflow -- and the file already written is then not
    # what the migrations are about to destroy.
    it 'reverses nothing when a workflow changed while it waited for the confirmation' do
      ENV['FILE'] = path
      ENV['CONFIRM'] = 'yes'
      allow(described_class).to receive(:confirm!) do
        WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                   old_status_id: issue_statuses(:issue_statuses_002).id,
                                   new_status_id: issue_statuses(:issue_statuses_001).id)
      end

      _output, exited, refusal = capture { described_class.uninstall }

      expect(exited).to be(true)
      expect(described_class).not_to have_received(:reverse_migrations)
      expect(refusal).to include('no longer matches the database')
      expect(refusal).to include('Nothing has been destroyed')
    end

    it 'reverses the migrations when nothing changed while it waited' do
      ENV['FILE'] = path
      ENV['CONFIRM'] = 'yes'

      _output, exited = capture { described_class.uninstall }

      expect(exited).to be(false)
      expect(described_class).to have_received(:reverse_migrations)
    end

    it 'names the restore command it leaves behind' do
      ENV['FILE'] = path
      ENV['CONFIRM'] = 'yes'

      output, = capture { described_class.uninstall }

      expect(output).to include('redmine_project_workflows:restore')
      expect(output).to include(path)
    end
  end
end
