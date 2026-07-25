#!/usr/bin/env bash
# Build all slide decks to HTML (site/) and PDF (dist/pdf/).
# Requirements: Node.js (npx). No global installs needed.
# Run from the repo root: ./scripts/build.sh

set -euo pipefail

# Ensure we run from the repo root regardless of invocation directory.
cd "$(dirname "$0")/.."

if [ ! -f theme/course.css ]; then
  echo "ERROR: theme/course.css not found — are you in the repo root?" >&2
  exit 1
fi

MARP="npx --yes @marp-team/marp-cli@latest"

mkdir -p site dist/pdf

echo "==> Building HTML into site/"
$MARP --theme-set theme/course.css \
      --html \
      --input-dir slides \
      --output site

echo "==> Building PDF into dist/pdf/"
$MARP --theme-set theme/course.css \
      --pdf \
      --allow-local-files \
      --input-dir slides \
      --output dist/pdf

# --input-dir also converts week-template.md; that's fine (it must render
# clean too), but keep the published artifacts to real weeks + template.

echo "==> Done."
echo "    HTML: $(ls site/week-*.html | wc -l) file(s) in site/"
echo "    PDF:  $(ls dist/pdf/week-*.pdf | wc -l) file(s) in dist/pdf/"
