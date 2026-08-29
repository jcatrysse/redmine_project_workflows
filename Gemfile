# frozen_string_literal: true

# Redmine evals plugins/*/Gemfile into its own, so anything named here lands in
# the bundle of every installation of this plugin -- production included. Only a
# runtime dependency belongs here.
#
# The test gems (rspec-rails, rails-controller-testing) used to be here in a
# `group :test` and are gone (finding F12). docs/DECISIONS.md already recorded
# the rule they broke, in its own words: the linter lives in
# .github/lint/Gemfile, outside the plugin root, because "the linter has no
# business in the host application's runtime bundle". The same sentence covers
# the test gems. dev/setup.sh writes both into the host's Gemfile.local, which
# Redmine evals *before* the plugin fragments (Gemfile:127 against :133 on
# 7.0-stable), and every documented way of building a host goes through that
# script.
#
# `deface` carries a major-version constraint, and no tighter one (audit F10).
#
# What the old, unpinned declaration got right and this keeps: the host owns
# Gemfile.lock, so nothing written here protects an installation that already
# resolved, and an exact pin in a plugin fragment can import a resolver conflict
# into a host that has none. What it did not cover is a **new** installation, or
# one running `bundle update`, where Bundler resolves whatever release exists
# that day -- and `init.rb` turns a deface that will not load into a LoadError
# that stops Redmine booting.
#
# `~> 1.9` is `>= 1.9, < 2.0`: the version every supported cell is tested against
# is the floor, and the next major -- the one release that may move the override
# API this plugin's five overrides hang on -- is excluded. It is strictly
# narrower than no constraint: it can only refuse a resolution that would have
# given this plugin a deface nobody has run it against, and a neighbour pinning
# anywhere inside the same major still resolves.
#
# The control that catches the other half -- an override that loads and quietly
# stops matching -- is still spec/integration/deface_overrides_spec.rb, on nine
# cells, and spec/plugin_conventions_spec.rb asserts this constraint admits the
# deface actually loaded and excludes 2.0.
source 'https://rubygems.org'

gem 'deface', '~> 1.9'
