#!/bin/bash
#
# Moves the project's MARKETING_VERSION past a published release so Xcode
# builds show the next development version, and commits the change.
#
#   ./Scripts/bump-dev-version.sh 0.4.2    sets 0.4.3 unless the project is already newer
#
# release.sh runs this after a successful public release. Packaging scripts
# pass the release version explicitly, so this value only affects Xcode builds.

set -euo pipefail

cd "$(dirname "$0")/.."

[ $# -eq 1 ] || { echo "usage: $0 RELEASED_VERSION" >&2; exit 1; }
RELEASED="${1#v}"
[[ "$RELEASED" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || {
    echo "error: '$1' is not a version like 0.3.0" >&2; exit 1
}
NEXT="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"

PROJECT=Dejima.xcodeproj/project.pbxproj
git diff --quiet HEAD -- "$PROJECT" || {
    echo "error: $PROJECT has uncommitted changes; commit them first" >&2; exit 1
}

versions=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([0-9.]+);$/\1/p' "$PROJECT" | sort -uV)
[ -n "$versions" ] || { echo "error: no MARKETING_VERSION found in $PROJECT" >&2; exit 1; }
current=$(printf '%s\n' "$versions" | tail -1)

# Keep a version that was already raised by hand, such as 0.5.0 after releasing 0.4.2.
if [ "$(printf '%s\n%s\n' "$current" "$RELEASED" | sort -V | tail -1)" != "$RELEASED" ]; then
    echo "==> Project version $current is already past $RELEASED"
    exit 0
fi

sed -i '' -E "s/(MARKETING_VERSION = )[0-9.]+;/\1$NEXT;/" "$PROJECT"
git commit -q -m "Begin $NEXT development" -- "$PROJECT"
echo "==> Project version set to $NEXT and committed"
