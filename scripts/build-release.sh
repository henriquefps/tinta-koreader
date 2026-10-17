#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Tinta contributors
# Builds the release zip: dist/tinta-<version>.zip with the folder tinta.koplugin/ inside, without the tests (tests/ of the
# plugin and of every app) and without the dev apps (apps/_modelo, _exemplo_json, _test_*, anything starting with "_").
#   scripts/build-release.sh [version]     version defaults to "v" + TINTA_VERSION of tinta.koplugin/core/version.lua
# The release workflow passes the tag (v1.2.3); the result is dist/tinta-v1.2.3.zip. Needs zip. Run from anywhere.
root=$(cd "$(dirname "$0")/.." && pwd) || exit 1
cd "$root" || exit 1
version=$1
if [ -z "$version" ]; then
    v=$(sed -n 's/^M\.TINTA_VERSION = "\(.*\)".*/\1/p' tinta.koplugin/core/version.lua)
    [ -n "$v" ] || { echo "build-release: cannot read TINTA_VERSION from tinta.koplugin/core/version.lua" >&2; exit 1; }
    version="v$v"
fi
case $version in *[!A-Za-z0-9._-]*|"") echo "build-release: invalid version '$version'" >&2; exit 2 ;; esac
command -v zip >/dev/null 2>&1 || { echo "build-release: zip not found" >&2; exit 1; }

stage=$(mktemp -d) || exit 1
trap 'rm -rf "$stage"' EXIT
cp -R tinta.koplugin "$stage/tinta.koplugin" || exit 1
find "$stage/tinta.koplugin" -type d -name tests -prune -exec rm -rf {} +
find "$stage/tinta.koplugin/apps" -mindepth 1 -maxdepth 1 -name '_*' -exec rm -rf {} +
# in the maintainers' tree, the private apps listed in scripts/public-exclude.txt stay out of the zip too
if [ -f scripts/public-exclude.txt ]; then
    for d in $(sed -n 's|^tinta\.koplugin/apps/\([a-z0-9_]*\)/$|\1|p' scripts/public-exclude.txt); do rm -rf "$stage/tinta.koplugin/apps/$d"; done
fi
find "$stage" \( -name '.DS_Store' -o -name '._*' -o -name '*.swp' \) -exec rm -rf {} + 2>/dev/null

mkdir -p dist || exit 1
out="$root/dist/tinta-$version.zip"
rm -f "$out"
(cd "$stage" && zip -qr -X "$out" tinta.koplugin) || exit 1
echo "build-release: $out ($(unzip -Z1 "$out" | wc -l | tr -d ' ') entries)"
