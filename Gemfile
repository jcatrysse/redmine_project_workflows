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
# `deface` is declared **without** a version requirement, and not at all when
# something evaluated earlier (Gemfile.local or a plugin loaded before this one)
# has declared it already.
#
# Every plugins/*/Gemfile is evaluated into the same Bundler DSL, and Bundler
# rejects the same gem declared twice with *different* requirements while it
# parses the Gemfile, before it resolves anything. `gem 'deface', '~> 1.9'`
# (audit F10) therefore broke every host with another plugin that says plain
# `gem 'deface'`: redmine_view_issue_description does, loads after this plugin,
# and `bundle install` stopped -- so Redmine did not boot (finding C1 in
# docs/REDMINE7-MIGRATION.md, measured on 7.0-stable-GEOxyz).
#
# What this covers, and what it does not:
# - a plain declaration later on is identical to ours, which Bundler accepts;
# - any declaration earlier on wins, whatever it says (the guard only checks the
#   name, so an earlier `require: false`, group or `~> 2.0` is taken as is);
# - a declaration *with* a requirement later on still makes Bundler refuse the
#   Gemfile. Nothing a plugin Gemfile can write avoids that; the neighbour has
#   to declare it plainly or guard it the same way.
#
# What the major constraint was for -- a new installation resolving a deface
# nobody has run -- is left to the host's Gemfile.lock and to CI, where
# spec/integration/deface_overrides_spec.rb asserts each of the five overrides
# still matches. spec/plugin_conventions_spec.rb pins the orders above.
source 'https://rubygems.org'

gem 'deface' unless dependencies.any? { |dependency| dependency.name == 'deface' }
