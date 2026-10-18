#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Tinta contributors
# Assembles the deployable demo site (https://tinta.hfps.dev) into a folder: docs/tinta-prototipo.html -> index.html,
# docs/screenshots/ -> screenshots/, docs/img/ -> img/ (when it exists). Plain static files, nothing to compile.
# Usage: scripts/build-site.sh [output-dir]   (default: dist-site/ at the repo root). Run from anywhere.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$root/dist-site"}
rm -rf "$out"
mkdir -p "$out"
cp "$root/docs/tinta-prototipo.html" "$out/index.html"
cp -R "$root/docs/screenshots" "$out/screenshots"
rm -f "$out/screenshots/README.md"
if [ -d "$root/docs/img" ]; then cp -R "$root/docs/img" "$out/img"; fi
echo "site ready in $out"
