# frozen_string_literal: true

#
# That the plugin is actually installed into the host it is running in, and the
# conventions that keep it that way.
#
require_relative 'spec_helper'

describe RedmineProjectWorkflows do
  it 'prepends a patch once, and only to a target that does not already have it' do
    target = Class.new
    patch = Module.new

    described_class.prepend_once(target, patch)
    described_class.prepend_once(target, patch)

    expect(target.ancestors).to include(patch)
    expect(target.ancestors.count { |ancestor| ancestor == patch }).to eq(1)
  end

  # WP0 / claude F05. The suite boots a real Redmine and applies nothing of its
  # own, so this is the assertion that the plugin is installed at all. It is
  # what catches an init.rb that registers its patches somewhere Rails never
  # calls -- Rails::Application::Configuration#to_prepare only appends to an
  # array that the :add_to_prepare_blocks initializer has already consumed by
  # the time any plugin's init.rb is loaded, so such a block never runs and
  # every patch below is missing.
  it 'is patched into the host that booted this suite' do
    expect(Issue.ancestors).to include(RedmineProjectWorkflows::Patches::IssuePatch)
    expect(WorkflowsController.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowsControllerPatch)
    expect(Project.ancestors).to include(RedmineProjectWorkflows::Patches::ProjectPatch)
    expect(WorkflowTransition.singleton_class.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowTransitionPatch)
    expect(WorkflowPermission.singleton_class.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowPermissionPatch)
    expect(WorkflowRule.singleton_class.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowRulePatch)
    # The settings tab is the one patch that is deliberately *not* a prepend --
    # see Patches::ProjectsHelperPatch#apply!, and the alias-chain examples in
    # spec/controllers/projects_settings_tab_spec.rb. It has to be in the
    # controller's helper chain, and nowhere near ProjectsHelper itself.
    expect(ProjectsController._helpers.ancestors)
      .to include(RedmineProjectWorkflows::Patches::ProjectsHelperPatch)
    expect(ProjectsHelper.ancestors)
      .not_to include(RedmineProjectWorkflows::Patches::ProjectsHelperPatch)
    # And the second of the two, for the same reason and since the same finding
    # (F01 of 2026-08-28-claude-audit). Two controllers carry it, because two
    # render the matrices: WorkflowsController owns the administration screens
    # and ProjectWorkflowsController renders core's `workflows/_form` for the
    # project ones. spec/controllers/workflows_helper_attachment_spec.rb is
    # where the alias-chain examples live.
    [WorkflowsController, ProjectWorkflowsController].each do |controller|
      expect(controller._helpers.ancestors)
        .to include(RedmineProjectWorkflows::Patches::WorkflowsHelperPatch)
    end
    expect(WorkflowsHelper.ancestors)
      .not_to include(RedmineProjectWorkflows::Patches::WorkflowsHelperPatch)
  end

  # A prepended patch that reimplements a core method inherits none of core's
  # own visibility declarations. Core says `private :workflow_rule_by_attribute`
  # right after its definition, and the patch's copy was public -- which widens
  # core's API on every host the plugin is installed on, quietly.
  it 'keeps core\'s visibility on the methods it reimplements' do
    expect(Issue.private_method_defined?(:workflow_rule_by_attribute)).to be(true)
    expect(Issue.public_method_defined?(:workflow_rule_by_attribute)).to be(false)
    # The other two are public in core and have to stay so.
    expect(Issue.public_method_defined?(:new_statuses_allowed_to)).to be(true)
    expect(Issue.public_method_defined?(:tracker=)).to be(true)
  end

  # The plugin injects a call to one of its own helpers into a partial that
  # *core* owns. Patches::IssuesControllerPatch puts that helper into
  # IssuesController's chain, and core renders issues/_attributes from
  # issues/_form only -- but a neighbouring plugin rendering issues/_form from a
  # controller of its own would reach the expression with no such helper and
  # raise NoMethodError on its own screen. Structural, because the negative case
  # needs a controller that does not exist in this suite.
  it 'guards the helper it injects into a core partial' do
    source = File.read(
      File.expand_path('../lib/redmine_project_workflows/overrides/issues_attributes_add_transition_map_link.rb',
                       __dir__)
    )
    calls = source.scan(/project_workflow_map_link\(@issue\)[^%]*/)

    expect(calls.size).to eq(2)
    calls.each { |call| expect(call).to include('respond_to?(:project_workflow_map_link)') }
  end

  # WP4. The permissions are declared inside Redmine::Plugin.register, which is
  # a different mechanism from the patches above and fails differently: a
  # permission that never reaches Redmine::AccessControl cannot be granted to
  # any role, so the settings tab would be invisible to everyone but an
  # administrator and no spec that logs one in would notice.
  it 'registers its two project permissions under the issue tracking module' do
    %i[view_project_workflow_rules manage_project_workflow_rules].each do |name|
      permission = Redmine::AccessControl.permission(name)

      expect(permission).not_to be_nil, "#{name} is not registered"
      expect(permission.project_module).to eq(:issue_tracking)
      # Both have to reach projects#settings: that is the action the tab is
      # rendered from, so without it a role holding only one of them could not
      # open the page the tab lives on.
      expect(permission.actions).to include('projects/settings')
      expect(permission.actions).to include('project_workflows/transitions')
    end
  end

  it 'lets only the managing permission write' do
    view = Redmine::AccessControl.permission(:view_project_workflow_rules)
    manage = Redmine::AccessControl.permission(:manage_project_workflow_rules)

    expect(view.actions).not_to include('project_workflows/update_transitions')
    expect(view.actions).not_to include('project_workflows/enable')
    expect(manage.actions).to include('project_workflows/update_transitions')
    expect(manage.actions).to include('project_workflows/update_permissions')
    %w[enable inherit clear].each do |action|
      expect(manage.actions).to include("project_workflows/#{action}")
    end
  end

  # WP5. The plugin's first setting. Redmine defines it from the register block,
  # so a setting declared in the wrong place would simply not exist -- and the
  # threshold would silently be the helper's fallback for everybody.
  it 'registers the bulk confirmation threshold as a plugin setting' do
    plugin = Redmine::Plugin.find(:redmine_project_workflows)

    expect(plugin).to be_configurable
    expect(plugin.settings[:partial]).to eq('settings/redmine_project_workflows')
    expect(Setting.available_settings).to have_key('plugin_redmine_project_workflows')
    expect(Setting.plugin_redmine_project_workflows).to have_key('bulk_confirm_threshold')
  end

  # The number is written down twice on purpose -- once as the setting's default
  # and once as the fallback for a settings hash saved before the key existed --
  # so this is the assertion that the two never drift apart.
  it 'declares the same default the helper falls back to' do
    declared = Redmine::Plugin.find(:redmine_project_workflows).settings[:default]

    expect(declared['bulk_confirm_threshold'].to_i)
      .to eq(RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD)
  end

  # WP6 added an action and forgot this mapping, and the symptom was a 403 for
  # everybody including administrators -- not an obvious "unmapped action" error.
  # So this is structural rather than a list: every action this controller
  # actually has must be named by at least one of the two permissions, and the
  # example fails the moment the next one is added without one.
  #
  # The difference against ApplicationController is what leaves the plugin's own
  # actions: action_methods on a controller includes everything public it
  # inherited as well.
  it 'names every action of its own controller in a permission' do
    actions = ProjectWorkflowsController.action_methods - ApplicationController.action_methods
    granted = %i[view_project_workflow_rules manage_project_workflow_rules].flat_map do |name|
      Redmine::AccessControl.permission(name).actions
    end

    expect(actions).not_to be_empty
    actions.each do |action|
      expect(granted).to include("project_workflows/#{action}"),
                         "project_workflows##{action} is reachable and no permission names it"
    end
  end

  # WP7. The version lives in init.rb and the release notes live in CHANGELOG.md,
  # and nothing but a habit kept them agreeing. Bumping one and forgetting the
  # other ships a plugin whose own changelog describes a different release, which
  # nobody notices until somebody asks what version they are running.
  #
  # The declared minimum Redmine version needs no assertion of its own: it is
  # checked by the nine-cell matrix itself. Raise it above a version CI runs and
  # `Redmine::Plugin.register` raises on that cell before a single example loads.
  it 'declares the same version its changelog most recently describes' do
    declared = Redmine::Plugin.find(:redmine_project_workflows).version
    changelog = File.read(File.expand_path('../CHANGELOG.md', __dir__))
    newest = changelog[/^## (\S+)/, 1]

    expect(newest).to eq(declared),
                      "init.rb declares #{declared}; CHANGELOG.md's newest entry is #{newest}"
  end

  # F02. TargetRailsVersion tells RuboCop which Rails APIs it may push code
  # towards, and it was set to 8.1 -- the Rails of the *newest* supported host.
  # A version-gated cop such as Rails/StrongParametersExpect then demands
  # `params.expect`, which does not exist before Rails 8.0: the contributor
  # complies, the lint job goes green, and the plugin raises NoMethodError on
  # Redmine 5.1. The property is that the value must be true of every supported
  # host, so this example enforces it from inside each of them, and the 5.1 cell
  # -- Rails 6.1 -- is the one that fails if it drifts upwards again.
  it 'points RuboCop at a Rails no newer than the host it is running in' do
    config = YAML.load_file(File.expand_path('../.rubocop.yml', __dir__))
    target = config.dig('AllCops', 'TargetRailsVersion').to_s

    expect(target).not_to be_empty
    expect(Gem::Version.new(target)).to be <= Gem::Version.new(Rails::VERSION::STRING),
                                        ".rubocop.yml targets Rails #{target}; this host runs " \
                                        "#{Rails::VERSION::STRING}, so the lint gate can approve " \
                                        'code this host cannot run'
  end

  # INV-2, and the forbidden-constructs table that spells it out: insert_all
  # runs no validations, so it is confined to the two rule writers, where a
  # whitelist checked against server-built lists stands in for them.
  #
  # 0.1.1 used it in ScopeWriter as well, to save round trips, with a comment
  # arguing that nothing in those rows comes from a request. The argument lost
  # twice: the rule is a gate rather than a default, and insert_all is the
  # skipping form of the statement -- a scope somebody else had just created
  # was dropped without a word and reported as created anyway. A grep is the
  # cheapest thing that keeps it from coming back.
  # Finding F02 of 2026-08-28-claude-audit, and the CI failure that followed the
  # first attempt at it. Two rules, both about one statement shape, both measured
  # rather than reasoned.
  #
  # The three raw-SQL sites built their timestamp as the standard
  # `TIMESTAMP '<literal>'` type keyword, which says what it means in a dialect
  # SQLite does not have: there migration 004 aborts with `no such column:
  # TIMESTAMP`, with 001..003 already committed. Redmine ships SQLite support.
  #
  # Dropping the keyword alone turned all three PostgreSQL cells red with
  # `PG::DatatypeMismatch: column "created_at" is of type timestamp without time
  # zone but expression is of type text`. Measured on PostgreSQL 16: a bare
  # literal in a **plain** select list is coerced against the target column, and
  # under **DISTINCT** it is not -- DISTINCT has to type the column to compare it,
  # and `unknown` resolves to `text` before the INSERT sees it.
  #
  # So: no type keyword anywhere, and no untyped literal inside a DISTINCT. Both
  # halves are greps, because the honest test is running the statement on the
  # adapter and this suite runs inside whichever host built it --
  # `dev/check-backfill.sh` is that test, on every cell, and it is what caught the
  # PostgreSQL failure. Each half is red on the shape it forbids.
  it 'builds no SQL literal with a type keyword the supported adapters do not share' do
    root = File.expand_path('..', __dir__)
    offenders = Dir.glob("#{root}/{app,lib,db}/**/*.rb").select do |file|
      File.read(file).lines.any? do |line|
        # A Ruby comment, not a SQL line that opens with an interpolation --
        # `#{now}` at the start of a heredoc line looks exactly like one, and the
        # first version of the sibling example below skipped precisely the lines
        # it existed to read.
        next false if line.strip.match?(/\A#(?!\{)/)

        line.match?(/\bTIMESTAMP\s+(?:'|\#\{)/i)
      end
    end

    expect(offenders.map { |file| file.sub("#{root}/", '') }).to be_empty
  end

  it 'puts no untyped literal in the select list of a DISTINCT' do
    root = File.expand_path('..', __dir__)
    offenders = Dir.glob("#{root}/{app,lib,db}/**/*.rb").filter_map do |file|
      # `#(?!\{)` and not `#`: a heredoc line that begins with `\#{now}` is SQL,
      # not a comment, and stripping it removed the only interpolation this
      # example looks for -- which is how the first version of it came back green
      # against the exact shape it forbids. Caught by reverting and running.
      body = File.read(file).gsub(/^\s*#(?!\{).*$/, '')
      # Everything between SELECT DISTINCT and the FROM that closes its select
      # list. A quote or an interpolation in there is a literal PostgreSQL will
      # resolve to text.
      lists = body.scan(/SELECT\s+DISTINCT\b(.*?)\bFROM\b/im).flatten
      file.sub("#{root}/", '') if lists.any? { |list| list.include?("'") || list.include?('#{') }
    end

    expect(offenders).to be_empty
  end

  it 'writes with insert_all only in the two rule writers' do
    root = File.expand_path('..', __dir__)
    callers = Dir.glob("#{root}/{app,lib,db}/**/*.rb").select do |file|
      File.read(file).match?(/\.insert_all\b/)
    end

    expect(callers.map { |file| file.sub("#{root}/", '') }).to contain_exactly(
      'lib/redmine_project_workflows/services/transition_writer.rb',
      'lib/redmine_project_workflows/services/permission_writer.rb'
    )
  end

  # F18. INV-4 says *any* query against `workflows` carries an explicit
  # project_id predicate, and one method deliberately breaks the letter of it:
  # WorkflowRule.copy_one_with_projects, whose delete_all spans both populations
  # and whose INSERT ... SELECT carries project_id through the select list,
  # because "duplicate this role including every project's workflow" is defined
  # that way.
  #
  # It had no record either way, so it was re-found every review and the
  # plausible repair -- scoping the DELETE alone -- is worse than the state,
  # because the INSERT two lines below still spans them. CLAUDE.md now names it
  # as the single exception; this pins the "single".
  #
  # A grep for the exception rather than for compliance, deliberately. Asserting
  # that no *other* statement lacks a predicate would need to parse relations
  # built across the query services, and a regex that tried would fail on the
  # ones that name project_id two method calls away. What can be checked cheaply
  # is that the *comment* naming the exception, and the method it names, still
  # exist and are still one.
  it 'has exactly one method carrying INV-4\'s deliberate exception' do
    root = File.expand_path('..', __dir__)
    marked = Dir.glob("#{root}/{app,lib,db}/**/*.rb").select do |file|
      File.read(file).include?("INV-4's one deliberate exception")
    end

    expect(marked.map { |file| file.sub("#{root}/", '') })
      .to contain_exactly('lib/redmine_project_workflows/patches/workflow_rule_patch.rb')
    expect(WorkflowRule).to respond_to(:copy_one_with_projects)
    expect(File.read("#{root}/CLAUDE.md")).to include('copy_one_with_projects')
  end

  # One Ruby statement, starting at +index+: the line, plus as many following
  # lines as it takes for its parentheses to balance. Six lines is the ceiling,
  # which is three more than the longest such call in this repository and stops
  # a stray parenthesis inside a string from swallowing a whole file.
  def statement_at(lines, index)
    statement = +''
    lines[index, 6].each do |line|
      statement << line
      break if statement.count('(') <= statement.count(')')
    end
    statement
  end

  # INV-4, from the other side: the grep the invariant's own wording invites.
  #
  # F02 of the second 2026-08-28 review found three query services holding a
  # relation on `workflows` narrowed by tracker and status but *not* by project,
  # with every branch adding the project_id afterwards. No branch executed the
  # half, so nothing mixed the two populations -- but a reviewer grepping for
  # exactly the forbidden construct found three hits inside the remedy and had
  # to read each one to clear it, and a fourth branch or a `to_a` moved one line
  # up would have turned a safe pattern into a silent wrong answer with no test
  # that would notice.
  #
  # The three are gone: the two resolver paths go through WorkflowPopulations
  # and StatusListQuery takes the project_id as a positional argument of the one
  # method that builds a relation. This is what keeps them gone.
  #
  # What is checked is the *statement*, not a fixed window of lines: a call
  # written across several lines names its project_id below the model, so the
  # match is grown until its parentheses balance and the project_id has to be
  # inside that. A base relation assigned on one line and given a project_id by
  # a later statement -- exactly the shape F02 found -- does not clear it, which
  # a line window would wrongly have done.
  #
  # It sees only the calls written as WorkflowRule/Transition/Permission.something,
  # which is the reviewer's own grep. A relation built through a variable is out
  # of its reach: WorkflowPopulations.relation is the one place that does that,
  # and it takes the project_id as a positional argument for this very reason.
  it 'builds no relation on workflows without a project_id in the same statement' do
    root = File.expand_path('..', __dir__)
    pattern = /\bWorkflow(?:Rule|Transition|Permission)\.(?:where|find|all|count|pluck)\b/
    offenders = Dir.glob("#{root}/{app,lib}/**/*.rb").flat_map do |file|
      lines = File.readlines(file)
      lines.each_index.filter_map do |index|
        next unless lines[index].match?(pattern)
        next if statement_at(lines, index).include?('project_id')

        "#{file.sub("#{root}/", '')}:#{index + 1}"
      end
    end

    expect(offenders).to be_empty
  end

  # F12. Redmine evals plugins/*/Gemfile into its own, so anything the plugin
  # names lands in the bundle of every installation, production included.
  # docs/DECISIONS.md:57 already recorded the rule -- the linter lives in
  # .github/lint/Gemfile because "the linter has no business in the host
  # application's runtime bundle" -- and the test gems were in a `group :test`
  # in the plugin's own Gemfile all the same.
  #
  # They are not needed there: dev/setup.sh writes both into the host's
  # Gemfile.local, which Redmine evals *before* the plugin fragments.
  #
  # Read as declarations rather than as text: the file's own comment explains
  # which gems were removed and names them, so a `include?('rspec-rails')` over
  # the whole file fails on the explanation. The first draft did exactly that.
  it 'names no test or lint gem in the Gemfile the host will eval' do
    lines = File.readlines(File.expand_path('../Gemfile', __dir__))
                .map { |line| line.sub(/#.*/, '').strip }.reject(&:empty?)
    declared = lines.filter_map { |line| line[/^gem\s+['"]([^'"]+)['"]/, 1] }

    expect(lines.grep(/^group\s+:(test|development)/)).to be_empty
    expect(declared).to contain_exactly('deface')
  end

  # And the gems it does *not* name still have to be there, or this example is
  # asserting that the suite cannot run -- which it plainly can, since it is
  # running. Stated so the deletion above cannot be read as having removed a
  # dependency rather than moved it.
  it 'still has the test gems the suite needs, from the host bundle' do
    expect(defined?(RSpec::Rails)).to be_truthy
    expect(ActionController::TestCase.new(nil)).to respond_to(:assigns)
  end

  # F19. Every workflow write logs one line, and the rule about *what* may be
  # logged -- ids and counts only, never issue content, request payloads or
  # matrix data -- lives in Services::WriteLog so there is one place to read it.
  # A direct Rails.logger call in a write path would route around that rule
  # silently, which is the whole reason the service exists rather than four
  # logger calls.
  it 'logs a write only through the service that holds the what-may-be-logged rule' do
    root = File.expand_path('..', __dir__)
    callers = Dir.glob("#{root}/{app,lib}/**/*.rb").select do |file|
      File.read(file).include?('Rails.logger')
    end

    expect(callers.map { |file| file.sub("#{root}/", '') }).to contain_exactly(
      # The Deface loader's rescue, which reports a file it could not load.
      'lib/redmine_project_workflows.rb',
      'lib/redmine_project_workflows/services/write_log.rb'
    )
  end

  # Reading a workflow is a read action, so it goes on working in a closed
  # project; managing one is not, so it stops there.
  it 'marks viewing as a read action and managing as a write' do
    expect(Redmine::AccessControl.permission(:view_project_workflow_rules)).to be_read
    expect(Redmine::AccessControl.permission(:manage_project_workflow_rules)).not_to be_read
    expect(Redmine::AccessControl.permission(:manage_project_workflow_rules)).to be_require_member
  end

  # Finding F01 of 2026-08-28-claude-plugin-compat-5.1, and the gate that turns
  # it from a wall of 53 unexplained 403s into one sentence.
  #
  # `Redmine::AccessControl` keeps its permissions in a flat array and
  # `.permission(name)` answers with the **first** registration of that name.
  # Plugins load in alphabetical directory order. So a neighbour registering the
  # same name earlier does not conflict, does not warn and does not raise -- it
  # simply wins, and the losing plugin's screens answer 403 to everybody,
  # administrators included, because `Project#allows_to?` is consulted before
  # `User#allowed_to?` reaches its `return true if admin?`. That is exactly what
  # `redmine_custom_workflows` did to `manage_project_workflow`.
  #
  # **Stated plainly: this example cannot fail on this plugin's own CI**, where
  # it is the only plugin installed and every name is trivially unique. It fires
  # when the suite is run on a host that also carries the neighbour -- which is
  # how the collision was found, and is the run worth repeating before a
  # release. Kept anyway, because the day it does fire it names the cause.
  it 'owns every permission name it registers, with nothing else claiming one' do
    %i[view_project_workflow_rules manage_project_workflow_rules].each do |name|
      claimants = Redmine::AccessControl.permissions.select { |permission| permission.name == name }

      expect(claimants.size).to eq(1),
                                "#{name} is registered #{claimants.size} times; " \
                                'AccessControl answers with the first, so one plugin silently loses'
      expect(claimants.first.actions).to include('project_workflows/transitions'),
                                         "#{name} resolves to another plugin's registration"
    end
  end
end

describe RedmineProjectWorkflows::VersionHelper do
  # Finding F02 of 2026-08-28-claude-plugin-compat-5.1. The predicate used to be
  # `respond_to?(:sprite_icon)`, and on Redmine 5.1 that answers *true* as soon
  # as any RedmineUP plugin is installed -- the `redmineup` gem back-ports a
  # `sprite_icon` onto ApplicationHelper, and `redmine_ai_triage` back-ports
  # another. A method name is not owned by Redmine.
  #
  # The two examples are red on different hosts and green on the same code, so
  # between them they are red on every supported version: the first fails on 5.1
  # against the old predicate (a context that *has* sprite_icon), the second
  # fails on 6.1 and 7.0 (a context that has *not*).
  let(:series_draws_sprites) { Redmine::VERSION::MAJOR >= 6 }

  it 'is not fooled by a neighbouring plugin defining sprite_icon' do
    context = Class.new do
      include RedmineProjectWorkflows::VersionHelper

      def sprite_icon(*_args, **_options)
        ''
      end
    end

    expect(context.new.project_workflows_svg_icons?).to eq(series_draws_sprites)
  end

  it 'is not fooled by a context that has no sprite_icon at all' do
    context = Class.new { include RedmineProjectWorkflows::VersionHelper }

    expect(context.new.project_workflows_svg_icons?).to eq(series_draws_sprites)
  end

  # The construct itself, not only its answer: a second `respond_to?` test
  # anywhere in the plugin would re-open F02 in a place this file's two examples
  # do not reach. Comments are allowed to name it -- the version helper's own
  # comment explains why it is wrong -- so this asks about code.
  it 'decides no host feature by asking whether sprite_icon is defined' do
    root = File.expand_path('..', __dir__)
    offenders = Dir.glob("#{root}/{app,lib}/**/*.{rb,erb}").select do |file|
      File.read(file).lines.any? do |line|
        line.include?('respond_to?(:sprite_icon)') && !line.strip.start_with?('#')
      end
    end

    expect(offenders.map { |file| file.sub("#{root}/", '') }).to be_empty
  end
end

describe 'the invisible custom field role map' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles,
           :enumerations

  let(:issue) { Issue.new(project: projects(:projects_001), tracker: trackers(:trackers_001)) }

  after { RedmineProjectWorkflows::Current.reset }

  # WP0 / external F09. A threaded application server reuses a thread across
  # requests, so a Thread.current cache outlives the request that filled it and
  # a configuration change is not seen until the thread is recycled. The review
  # called that branch dead code because Redmine bundles request_store -- true
  # up to 6.1, but Redmine 7.0 dropped the gem, so on 7.0 it was the only path
  # the cache ever took. See RedmineProjectWorkflows::Current.
  #
  # The point of the cache is that it lasts exactly one request: long enough
  # that rendering many issues costs one query rather than one per issue, and
  # no longer, so an administrator's change to a custom field is visible on the
  # next request rather than when the server happens to recycle the thread.
  it 'is cached within one request and not beyond it' do
    field = IssueCustomField.create!(name: 'Invisible map spec field', field_format: 'string',
                                     visible: false, role_ids: [roles(:roles_001).id])

    expect(issue.send(:invisible_custom_field_role_map)).to have_key(field.id)

    field.destroy!
    expect(issue.send(:invisible_custom_field_role_map)).to have_key(field.id)

    RedmineProjectWorkflows::Current.reset
    expect(Issue.new(project: projects(:projects_001), tracker: trackers(:trackers_001))
                .send(:invisible_custom_field_role_map)).not_to have_key(field.id)
  end
end
