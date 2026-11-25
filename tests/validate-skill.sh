#!/bin/bash
# SKILL.md structure: frontmatter fields and a phased workflow. Run by sdlc as
# the `skill-structure` check (was .github/workflows/skill.yml).
set -euo pipefail
cd "$(dirname "$0")/.."
test -s SKILL.md || { echo "FAIL: SKILL.md missing or empty"; exit 1; }
head -1 SKILL.md | grep -q '^---$' || { echo "FAIL: Missing YAML frontmatter"; exit 1; }
for field in name description argument-hint allowed-tools; do
  grep -q "^$field:" SKILL.md || { echo "FAIL: Missing $field field"; exit 1; }
done
phase_count=$(grep -c '^## Phase [0-9]' SKILL.md || true)
echo "Found $phase_count phases"
test "$phase_count" -ge 2 || { echo "FAIL: Fewer than 2 phases found"; exit 1; }
echo "SKILL.md structure valid"
