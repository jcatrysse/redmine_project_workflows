# frozen_string_literal: true

require_relative '../spec_helper'

# F03. Would anything notice if Redmine changed a method this plugin has copied?
#
# Until this file, no. The plugin reimplements eighteen of core's methods --
# there is no `super` to fall through to, because core's queries carry no
# project_id predicate and running one would breach INV-4 whatever was done with
# the answer. That is the right design, and its standing cost is that a change
# under it is silent: the plugin's own specs assert the plugin's expected
# answers, not core's, so they stay green while the copy drifts.
#
# A nineteenth, Project#copy, is a **delegate** rather than a copy -- it
# remembers one thing and calls super. It is covered here all the same, and the
# table's header says why: if core changes how it reads `options[:only]`, or
# moves the `model_project_copy_before_save` hook out of that method, the copy
# form's workflow checkbox stops being honoured with nothing else to notice.
#
# It has already happened twice to Issue#new_statuses_allowed_to, both times
# semantically. 5.0 -> 5.1 replaced
# `user.admin ? Role.all.to_a : user.roles_for_project(project)` with
# `roles_for_workflow(user)`, which adds a consider_workflow? filter -- so a
# plugin carrying the 5.0 copy onto 5.1 would have offered status transitions
# for roles that take no part in a workflow. A silent permission widening in the
# method Issue#safe_attributes= calls on every issue save.
#
# Two kinds of example here, and they catch different things:
#
#   * the DIGEST examples notice that core's text changed, whatever it changed
#     to. Cheap, exact, and blind to meaning.
#   * the ORACLE examples call core's own implementation through
#     `super_method.bind` and assert the plugin agrees with it wherever no scope
#     applies. They notice a semantic divergence the digest cannot explain, and
#     they are the reason a digest bump is not just paperwork.
#
# Neither needs a gem, a network call or a CI change: the suite runs *inside* the
# host Redmine checkout, so core's source is already on disk in all nine cells.
describe 'Redmine core under the plugin' do
  # :projects_trackers because the divergence example saves an Issue, and
  # :enumerations because an Issue needs a priority.
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enumerations, :projects_trackers

  let(:digest_service) { RedmineProjectWorkflows::Services::CoreMethodDigest }
  let(:host_version) { "#{Redmine::VERSION::MAJOR}.#{Redmine::VERSION::MINOR}" }
  let(:table) { YAML.load_file(File.expand_path('core_method_digests.yml', __dir__)) }

  before { skip('this Ruby cannot read core\'s AST') unless digest_service.available? }

  describe 'the bodies the plugin has copied' do
    # An unknown minor is REPORTED, not failed. Failing there would mean the
    # plugin could not be tried on a new Redmine at all, which is exactly what
    # narrowing requires_redmine would have done -- and F03 rejected that,
    # because lib/redmine/plugin.rb raises PluginRequirementError with no rescue
    # around run_initializer, so an out-of-range Redmine stops the whole
    # application from booting until an administrator deletes the plugin
    # directory. An uncertain divergence is the better trade.
    it 'is a Redmine this table has measured' do
      skip("Redmine #{host_version} is not in the table -- see the file header") unless table.key?(host_version)

      expect(table.fetch(host_version)).not_to be_empty
    end

    it 'still holds every method the plugin shadows' do
      skip("Redmine #{host_version} is not in the table") unless table.key?(host_version)

      expect(digest_service.digests.keys.sort).to eq(table.fetch(host_version).keys.sort)
    end

    # One example per method rather than one comparing two hashes, so a red
    # suite names the method that drifted instead of printing two blocks of
    # hex. The message says what to do, because the wrong reaction here -- bump
    # the digest, move on -- is the one that makes this file worse than no file.
    it 'matches the digest measured for this Redmine, method by method' do
      skip("Redmine #{host_version} is not in the table") unless table.key?(host_version)

      expected = table.fetch(host_version)
      drifted = digest_service.digests.filter_map do |method_name, digest|
        next if expected[method_name] == digest

        core = core_source_location(method_name)
        "#{method_name}: expected #{expected[method_name].to_s[0, 12]}, " \
          "host has #{digest[0, 12]} (core's body at #{core})"
      end

      expect(drifted).to be_empty, lambda {
        "Redmine #{host_version} has changed a body this plugin copied:\n  " +
          drifted.join("\n  ") +
          "\n\nRead core's new version against the plugin's copy and decide whether the copy must " \
          'follow. Change the copy first, with a test; update ' \
          'spec/upstream/core_method_digests.yml in the same commit. Updating the digest first is ' \
          'the one thing that makes this gate useless.'
      }
    end

    def core_source_location(method_name)
      owner, name = method_name.split('#')
      owner.constantize.instance_method(name).super_method.source_location.join(':')
    rescue StandardError
      'unknown'
    end
  end

  # The other half, and the reason the digest is worth having: where no project
  # has taken a workflow over, the plugin must answer exactly what core answers.
  # `super_method` binds, private methods included, so core's own implementation
  # is available as an oracle.
  #
  # Scoped to a state with NO project rows, deliberately. Core's queries carry no
  # project_id predicate, so a project row anywhere -- a fixture leak, another
  # spec file's leftovers -- would make core read rules the plugin correctly
  # hides and turn these into false failures on all nine cells.
  describe 'the plugin against core as an oracle, where nothing is overridden' do
    let(:project) { projects(:projects_001) }
    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }
    let(:user) { users(:users_002) }
    let(:old_status) { issue_statuses(:issue_statuses_001) }
    let(:new_status) { issue_statuses(:issue_statuses_002) }

    def core_call(owner, name, receiver, *args)
      owner.instance_method(name).super_method.bind_call(receiver, *args)
    end

    # A second role the user holds that does NOT take part in a workflow:
    # Role#consider_workflow? is `add_issues || edit_issues`, so an ordinary role
    # without either is excluded from core's own role list.
    #
    # This is here on purpose, and it is what makes the oracle worth running.
    # Core's role list changed at 5.1 --
    # `user.admin ? Role.all.to_a : user.roles_for_project(project)` became
    # `roles_for_workflow(user)`, adding exactly this filter -- so a plugin
    # carrying the older form would offer the transitions of such a role. With
    # only ordinary roles in the fixture the two forms agree and the oracle
    # passes over the drift; a probe confirmed that before this role was added.
    let(:workflow_blind_role) do
      Role.create!(name: 'Observer for the drift oracle', permissions: [:view_issues])
    end
    let(:blind_status) { issue_statuses(:issue_statuses_004) }

    before do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
      member = Member.where(project: project, user: user).first_or_initialize
      member.roles = ([role] + member.roles.to_a + [workflow_blind_role]).uniq
      member.save!
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 author: false, assignee: false)
      # Reachable only through a role core excludes. If the plugin's copy ever
      # drops the consider_workflow? filter, this status appears in its answer
      # and not in core's.
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: workflow_blind_role.id, project_id: nil,
                                 old_status_id: old_status.id, new_status_id: blind_status.id,
                                 author: false, assignee: false)
    end

    # A SAVED issue with a current status, and every transition example uses it.
    #
    # This is not incidental. A new record resolves from core's
    # `old_status_id = 0` pseudo-status, so a transition out of `old_status`
    # matches nothing and both sides answer `[]` -- the first draft of these
    # examples compared two empty arrays and passed while the plugin's role list
    # was deliberately broken. Found by probing the gate rather than by reading
    # it, which is the only way that kind of vacuity gets found.
    let(:issue) do
      Issue.create!(project: project, tracker: tracker, status: old_status,
                    subject: 'drift oracle', author: user,
                    priority: IssuePriority.first || enumerations(:enumerations_004))
    end

    after do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
    end

    it 'offers the statuses core offers' do
      plugin_answer = issue.new_statuses_allowed_to(user).map(&:id).sort

      # Not vacuous: the generic transition really is reachable from here.
      expect(plugin_answer).to include(new_status.id)
      expect(plugin_answer).to eq(core_call(Issue, :new_statuses_allowed_to, issue, user).map(&:id).sort)
    end

    # The case core's own role list changed at 5.1, asserted from both sides: a
    # role the user holds that does not take part in a workflow contributes
    # nothing, to core and to the plugin alike.
    it 'excludes a role that takes no part in a workflow, exactly as core does' do
      plugin_answer = issue.new_statuses_allowed_to(user).map(&:id)

      expect(plugin_answer).not_to include(blind_status.id)
      expect(core_call(Issue, :new_statuses_allowed_to, issue, user).map(&:id))
        .not_to include(blind_status.id)
    end

    it 'reads the same field permissions core reads' do
      issue_under_test = issue
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: old_status.id, field_name: 'due_date', rule: 'required')
      issue = issue_under_test

      expect(issue.send(:workflow_rule_by_attribute, user)).to be_present
      expect(issue.send(:workflow_rule_by_attribute, user))
        .to eq(core_call(Issue, :workflow_rule_by_attribute, issue, user))
    end

    it 'rolls up the statuses core rolls up' do
      expect(project.rolled_up_statuses.map(&:id).sort)
        .to eq(core_call(Project, :rolled_up_statuses, project).map(&:id).sort)
    end

    # And the mirror image, which is what makes the three above meaningful: once
    # a project HAS taken a workflow over, the plugin must stop agreeing with
    # core -- core would read the project's rules into the generic answer, which
    # is INV-4's whole subject. An oracle suite that only asserted agreement
    # would pass over a plugin that had quietly become core again.
    it 'stops agreeing with core once a project has its own workflow' do
      other_status = issue_statuses(:issue_statuses_003)
      # The issue is created before the project rule exists -- a workflow rule
      # arranged first can make Issue#save! fail (docs/STATE.md's traps).
      issue.reload
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, new_status_id: other_status.id,
                                 author: false, assignee: false)
      RedmineProjectWorkflows::Services::Resolver.reset_cache!

      plugin_answer = issue.reload.new_statuses_allowed_to(user).map(&:id)
      core_answer = core_call(Issue, :new_statuses_allowed_to, issue, user).map(&:id)

      expect(plugin_answer).to include(other_status.id)
      expect(plugin_answer).not_to include(new_status.id)
      expect(core_answer).to include(new_status.id)
    end
  end
end
