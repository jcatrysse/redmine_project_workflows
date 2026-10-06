# frozen_string_literal: true

module RedmineProjectWorkflows
  # The three release-engineering rake tasks, out of the rake file so that they
  # can be read, reviewed and tested like anything else. WP16.
  module Tasks
    PLUGIN_ID = :redmine_project_workflows

    class << self
      def required_file
        path = ENV['FILE'].presence
        abort 'redmine_project_workflows: FILE= is required (where to read or write the backup)' if path.nil?

        File.expand_path(path)
      end

      def summary(document)
        [
          "#{document['scopes'].size} project #{'workflow'.pluralize(document['scopes'].size)}, " \
          "#{document['rules'].size} #{'rule'.pluralize(document['rules'].size)}",
          "across #{document['names']['projects'].size} " \
          "#{'project'.pluralize(document['names']['projects'].size)}"
        ]
      end

      # The restore, as the rake task runs it -- here rather than in the rake
      # file so that its one decision can be tested.
      #
      # That decision: a run with a failed combination in it **exits non-zero**.
      # An operator reading the terminal sees the named lines either way, but a
      # restore is the thing that runs unattended -- from an installer, a
      # container entrypoint, a colleague's shell script after a database
      # restore -- and a silent zero there is how a half-restored installation
      # gets declared finished. Nothing above the failure was left half-written
      # (each combination is its own transaction), so re-running the same
      # command retries exactly what failed.
      def restore(document)
        report = Services::WorkflowRestore.call(
          document, overwrite: ENV['OVERWRITE'].present?, user: User.anonymous
        )
        puts report.lines.join("\n")
        return report unless report.failed?

        abort 'redmine_project_workflows: the restore did not complete. Nothing that failed was left ' \
              'half-written; run the same command again to retry it.'
      end

      # The scripted uninstall. It is the destructive one, so it says what it
      # is about to destroy *before* it asks, and refuses to run without an
      # answer typed in full.
      #
      # The order is the whole point. What is about to be lost is counted first,
      # because after `VERSION=0` there is nothing left to count; the backup is
      # written and read back before a migration runs, because a backup nobody
      # has opened is a belief rather than a backup; and a run refused at the
      # confirmation writes no file, so forgetting CONFIRM=yes does not leave a
      # half-finished backup in the way of the next attempt.
      #
      # `SKIP_BACKUP=1` is there for the operator who has a database dump and
      # knows it. It is not the default, and it says so on the way past.
      def uninstall
        # Before anything else, including the export: a missing FILE= is the
        # operator's mistake to hear about now rather than after they have
        # answered the confirmation.
        required_file if ENV['SKIP_BACKUP'].blank?
        document = Services::WorkflowBackup.document
        announce(document)
        confirm!
        path = write_backup(document)
        refuse_if_changed!(document)
        reverse_migrations
        puts 'redmine_project_workflows: every migration reversed; the plugin directory can now be removed.'
        puts restore_recipe(path) if path
      end

      # WP17. The window this closes is small and it is real: the export is
      # taken, the operator is shown a count and asked to type CONFIRM=yes, and
      # only then is anything destroyed. On a production installation nobody has
      # been asked to stop using, a colleague can save a workflow while that
      # question is on the screen -- and what the migrations then destroy is not
      # what the file holds. The file is the only way back, so a file that is
      # already out of date is the one thing this task must not proceed past.
      #
      # Compared rather than counted. Both collections are ordered by every
      # column that identifies a row, precisely so that two exports of the same
      # database are the same file, so a difference of any kind shows here --
      # including one that leaves the counts alone.
      #
      # What it does not close, said plainly: a write landing between this
      # comparison and the first statement of the migration. Closing that would
      # mean holding every combination locked across a schema change, which is a
      # worse thing to do to a production database than the risk it removes.
      # This narrows the window from "as long as a human takes to answer" to
      # "between two statements".
      def refuse_if_changed!(document)
        current = Services::WorkflowBackup.document
        return if current['scopes'] == document['scopes'] && current['rules'] == document['rules']

        abort 'redmine_project_workflows: a project workflow changed while this task was waiting for ' \
              "CONFIRM=yes, so the backup no longer matches the database. Nothing has been destroyed. \n" \
              'Run the task again to take a backup of what is there now.'
      end

      def announce(document)
        puts 'redmine_project_workflows: reversing every migration will'
        puts '  * delete every workflow rule that names a project'
        puts '  * drop project_workflow_scopes, and with it every own EMPTY workflow'
        puts '  * drop project_workflow_write_locks and the project_id column on workflows'
        puts '  * leave the generic workflow -- the one every project shares -- untouched'
        puts 'about to be discarded:'
        puts summary(document).map { |line| "  #{line}" }.join("\n")
        return if ENV['SKIP_BACKUP'].blank?

        puts 'SKIP_BACKUP=1: no backup will be written, and there is no way back from this ' \
             'except a database dump of your own.'
      end

      # Written from the document that was counted above, so the file holds
      # exactly what the operator was shown, and read back before anything is
      # destroyed.
      def write_backup(document)
        return nil if ENV['SKIP_BACKUP'].present?

        path = required_file
        Services::WorkflowBackup.write(path, document: document, force: ENV['FORCE'].present?)
        Services::WorkflowBackup.read(path)
        puts "redmine_project_workflows: backup written to #{path}"
        path
      end

      # Typed in full, and never defaulted. An operator who runs this by mistake
      # on the wrong RAILS_ENV has done the one thing in this plugin there is no
      # way back from except the file it writes.
      def confirm!
        return if ENV['CONFIRM'] == 'yes'

        abort 'redmine_project_workflows: refusing to reverse the migrations without CONFIRM=yes'
      end

      def reverse_migrations
        Redmine::Plugin.migrate(PLUGIN_ID.to_s, 0)
      end

      def restore_recipe(path)
        <<~TEXT
          To put the project workflows back, reinstall the plugin, migrate up, and:
            RAILS_ENV=#{Rails.env} bundle exec rake redmine_project_workflows:restore FILE=#{path}
        TEXT
      end
    end
  end
end
