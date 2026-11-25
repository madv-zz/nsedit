#!/bin/sh
# Prints the section "## v<version> ..." of CHANGELOG.md (up to the next "## " heading): the release notes.
# Usage: ci/release-notes.sh <version>      e.g. ci/release-notes.sh 2.0.0
set -eu
version=${1:?usage: $0 <version>}
awk -v head="## v$version" '
    index($0, head) == 1 && (length($0) == length(head) || substr($0, length(head) + 1, 1) == " ") { on = 1; next }
    on && /^## / { exit }
    on { print }
' "$(dirname "$0")/../CHANGELOG.md" | sed -e '/./,$!d'
