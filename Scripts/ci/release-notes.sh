#!/usr/bin/env bash
# Turns the GitHub release body (markdown from release-please) into App Store "What's New" text
# for every locale in fastlane/metadata. App Store Connect allows at most 4000 characters.
set -euo pipefail
notes=$(printf '%s\n' "${BODY:-}" \
  | sed -E 's/^#+ *//; s/\*\*//g; s/\[([^]]+)\]\([^)]*\)/\1/g; s/^\* /• /' \
  | grep -v '^[[:space:]]*$' | head -c 4000 || true)
if [ -z "$notes" ]; then
  notes="Bug fixes and improvements."
fi
for dir in fastlane/metadata/*/; do
  printf '%s\n' "$notes" > "${dir}release_notes.txt"
done
echo "Release notes:"; printf '%s\n' "$notes"
