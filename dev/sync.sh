#!/usr/bin/env bash
# Copy the working tree of this plugin into a Redmine host installation.
# A symlink is deliberately not used: the spec files resolve config/environment
# relative to their real path, which breaks through a symlink.
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_NAME="$(basename "$PLUGIN_DIR")"
DIR="${1:-${REDMINE_DIR:-$PLUGIN_DIR/.redmine/5.1-stable-postgresql}}"
mkdir -p "$DIR/plugins/$PLUGIN_NAME"
rsync -a --delete --exclude '.git/' --exclude '.redmine/' --exclude 'vendor/' \
  "$PLUGIN_DIR/" "$DIR/plugins/$PLUGIN_NAME/"
