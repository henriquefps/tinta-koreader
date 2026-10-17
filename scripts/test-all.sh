#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Tinta contributors
# Runs every test suite of the repo: the core, the UI (headless smokes) and the suite of every app under
# tinta.koplugin/apps/<id>/tests/ (so a new app, e.g. made by scripts/nova-app.sh, is picked up with no edit here).
# A suite missing from the tree is simply not run (the public tree has fewer apps than the maintainers' one).
# Run from anywhere. KOREADER_REF=<dir> also runs the store tests against KOReader's real SQLite binding.
cd "$(dirname "$0")/.." || exit 1
status=0
suites="tests/run.lua tests/tinta_ui_test.lua tests/tinta_ui_smoke.lua tests/tinta_ui_firstrun.lua tests/tinta_ui_external.lua tests/tinta_ui_scales.lua tinta.koplugin/tests/run.lua"
for t in tinta.koplugin/apps/*/tests/ui_smoke.lua tinta.koplugin/apps/*/tests/run.lua; do suites="$suites $t"; done
for t in $suites; do
    [ -f "$t" ] || continue
    out=$(QUIET=1 luajit "$t" 2>&1); rc=$?
    printf '%-50s %s\n' "$t" "$(printf '%s\n' "$out" | tail -1)"
    if [ $rc -ne 0 ]; then status=1; printf '%s\n' "$out" | grep -E 'FAIL' | head -20; fi
done
# the dev apps (apps/_*, loaded only with dev_apps) load in the headless smoke on their own, one at a time: as one more app they
# would move the launcher pages the main smoke is pinned to (SMOKE_APP=<id> runs a short flow for one app, e.g. one made by
# scripts/nova-app.sh). tests/fixtures/smoke-skip-apps.txt lists the apps the main smoke leaves out.
for id in $(grep -vE '^[[:space:]]*(#|$)' tests/fixtures/smoke-skip-apps.txt); do
    [ -f "tinta.koplugin/apps/$id/init.lua" ] || continue
    out=$(QUIET=1 SMOKE_APP="$id" luajit tests/tinta_ui_smoke.lua 2>&1); rc=$?
    printf '%-50s %s\n' "tests/tinta_ui_smoke.lua (SMOKE_APP=$id)" "$(printf '%s\n' "$out" | tail -1)"
    if [ $rc -ne 0 ]; then status=1; printf '%s\n' "$out" | grep -E 'FAIL' | head -20; fi
done
exit $status
