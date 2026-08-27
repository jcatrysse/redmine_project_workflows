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
# `deface` is deliberately unpinned. There is no range to pin to -- deface has
# had exactly one release since 2022-04-01 -- the host owns Gemfile.lock, so a
# constraint in a plugin fragment cannot protect an existing installation, and it
# *can* import a neighbouring plugin's resolver conflict into a host that has
# none. The control that exists instead is
# spec/integration/deface_overrides_spec.rb, on nine cells.
source 'https://rubygems.org'

gem 'deface'
