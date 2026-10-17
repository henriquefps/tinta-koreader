#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Tinta contributors
# Creates a new Tinta app from the reference app (tinta.koplugin/apps/_modelo).
#   scripts/nova-app.sh <id> "<Nome>"
# <id>: [a-z0-9_]+, not starting with "_" (that prefix loads only with dev_apps), and no app with that id yet.
# Copies apps/_modelo to apps/<id>, renames the id and the name; scripts/test-all.sh finds the app's suite by itself.
# Guide: docs/sdk.md. The environment variable TINTA_ROOT (default: the repo of this script) says where to work.
root=${TINTA_ROOT:-$(cd "$(dirname "$0")/.." && pwd)} || exit 1
apps="$root/tinta.koplugin/apps"
tmpl="$apps/_modelo"

die() { printf 'nova-app: %s\n' "$1" >&2; exit 1; }

[ $# -eq 2 ] || die 'usage: scripts/nova-app.sh <id> "<Nome>"'
id=$1
name=$2

[ -n "$id" ] || die "empty id"
# (grep in the C locale: a [a-z] glob in case also matches capitals on some systems)
[ "$(printf '%s' "$id" | LC_ALL=C grep -Ec '^[a-z0-9_]+$')" = 1 ] || die "invalid id '$id': use only a-z, 0-9 and _"
case $id in _*) die "invalid id '$id': ids starting with _ load only with dev_apps (use a name without the underscore)" ;; esac
[ ! -e "$apps/$id" ] || die "apps/$id already exists"
[ -d "$tmpl" ] || die "template not found: $tmpl"
[ -n "$name" ] || die "empty name"
# the name goes inside Lua strings and a sed replacement: keep it to one plain line
case $name in
    *\"*|*\\*|*\|*|*\&*) die 'the name cannot contain " \ | or &' ;;
esac
[ "$(printf '%s' "$name" | wc -l | tr -d ' ')" = 0 ] || die "the name must be one line"
[ ${#name} -le 40 ] || die "the name is too long (40 characters at most)"

cp -R "$tmpl" "$apps/$id" || die "copy failed"
for f in $(find "$apps/$id" -type f -name '*.lua'); do
    sed -e "s|_modelo|$id|g" -e "s|Modelo|$name|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f" || die "rename failed in $f"
done
# the English name of the template is "Template": keep it as the Nome as well, so both languages show it
sed -e "s|name = \"Template\"|name = \"$name\"|" -e "s|Template: %d|$name: %d|" "$apps/$id/strings.lua" > "$apps/$id/strings.lua.tmp" \
    && mv "$apps/$id/strings.lua.tmp" "$apps/$id/strings.lua"

# descriptions and the header of init.lua describe the template, not the new app
sed -e "s|description = \".*\"|description = \"$name\"|" "$apps/$id/strings.lua" > "$apps/$id/strings.lua.tmp" \
    && mv "$apps/$id/strings.lua.tmp" "$apps/$id/strings.lua"
{
    printf -- '-- %s: Tinta app, created by scripts/nova-app.sh from the reference app. Guide: docs/sdk.md.\n' "$name"
    printf -- '-- init.lua = manifest + wiring to ctx · logic.lua = pure rules · view.lua = drawing · strings.lua = pt/en texts.\n'
    awk '/^local Logic/ { p = 1 } p' "$apps/$id/init.lua"
} > "$apps/$id/init.lua.tmp" && mv "$apps/$id/init.lua.tmp" "$apps/$id/init.lua"

entry="tinta.koplugin/apps/$id/tests/run.lua"   # scripts/test-all.sh finds every apps/*/tests/run.lua by itself

# the main headless smoke is pinned to the repo's own apps: the new app loads there only for SMOKE_APP=<id>
skip="$root/tests/fixtures/smoke-skip-apps.txt"
if [ -d "$root/tests/fixtures" ] && ! grep -qx "$id" "$skip" 2>/dev/null; then echo "$id" >> "$skip"; fi

cat <<MSG
Created tinta.koplugin/apps/$id ("$name").

Next steps:
  1. Run its tests:            luajit $entry
     the headless smoke:       SMOKE_APP=$id luajit tests/tinta_ui_smoke.lua
     and all of them:          KOREADER_REF=<koreader sources> scripts/test-all.sh
  2. Edit the manifest and the code in tinta.koplugin/apps/$id/ (init.lua, logic.lua, view.lua, strings.lua).
  3. Look at it: Menu → Apps lists it after the Tinta restarts (deploy: scripts/deploy.sh).
  4. Read docs/sdk.md (manifest, ctx, widget sizes, performance rules).
MSG
