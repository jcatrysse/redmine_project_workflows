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
        reverse_migrations
        puts 'redmine_project_workflows: every migration reversed; the plugin directory can now be removed.'
        puts restore_recipe(path) if path
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
