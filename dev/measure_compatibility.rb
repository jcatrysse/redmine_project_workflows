# frozen_string_literal: true

# Print this host's block of lib/redmine_project_workflows/compatibility.yml.
#
#   cd .redmine/7.0-stable-postgresql
#   RAILS_ENV=test bundle exec rails runner \
#     plugins/redmine_project_workflows/dev/measure_compatibility.rb
#
# Paste the output under `minors:` in the manifest -- after reading the drift the
# suite reports, never before. See the manifest's own header: updating a digest
# ahead of reading what changed is the one thing that makes the gate useless.
#
# It measures whatever CoreMethodDigest discovers on this host, so a new patch
# module or a new declared dependency appears here without this script changing.

digests = RedmineProjectWorkflows::Services::CoreMethodDigest.digests
missing = RedmineProjectWorkflows::Services::CoreMethodDigest.missing_dependencies

warn("declared dependencies this host does not define: #{missing.join(', ')}") if missing.any?

puts "  '#{RedmineProjectWorkflows::Compatibility.host_minor}':"
puts "    ruby: '#{RUBY_VERSION.split('.').first(2).join('.')}'"
puts "    rails: '#{Rails::VERSION::STRING.split('.').first(2).join('.')}'"
puts '    digests:'
digests.keys.sort.each { |name| puts "      '#{name}': '#{digests.fetch(name)}'" }
