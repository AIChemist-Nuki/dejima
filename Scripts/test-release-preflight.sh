#!/bin/bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "$0")/.." && pwd)
RELEASE_FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/dejima-release-preflight.XXXXXX")
trap 'rm -rf "$RELEASE_FIXTURE"' EXIT
export RELEASE_FIXTURE

mkdir -p "$RELEASE_FIXTURE/Scripts" "$RELEASE_FIXTURE/Dejima.xcodeproj" "$RELEASE_FIXTURE/bin"
cp "$REPOSITORY_ROOT/Scripts/release.sh" "$RELEASE_FIXTURE/Scripts/release.sh"
touch "$RELEASE_FIXTURE/Dejima.xcodeproj/project.pbxproj"

# All release services are replaced before invoking the real script in isolation.
cat > "$RELEASE_FIXTURE/bin/git" <<'EOF'
#!/bin/bash
case "$1 $2" in
    'status --porcelain'|'status --short')
        if [ "${FIXTURE_DIRTY:-0}" = 1 ]; then echo ' M example.swift'; fi
        ;;
    'rev-parse -q') exit 1 ;;
    tag*) touch "$RELEASE_FIXTURE/tag-called"; exit 90 ;;
    *) echo "Unexpected git invocation: $*" >&2; exit 91 ;;
esac
EOF

cat > "$RELEASE_FIXTURE/bin/xcodebuild" <<'EOF'
#!/bin/bash
if [ "$1" = -version ]; then
    echo 'Fixture Xcode'
else
    touch "$RELEASE_FIXTURE/build-called"
    exit 92
fi
EOF

cat > "$RELEASE_FIXTURE/bin/security" <<'EOF'
#!/bin/bash
cat "$RELEASE_FIXTURE/identities"
EOF

cat > "$RELEASE_FIXTURE/bin/xcrun" <<'EOF'
#!/bin/bash
if [ "$1 $2" = 'notarytool history' ]; then
    echo 'error: fixture notarization profile is unavailable' >&2
else
    echo "Unexpected xcrun invocation: $*" >&2
fi
exit 93
EOF

chmod +x "$RELEASE_FIXTURE/bin/"*
export PATH="$RELEASE_FIXTURE/bin:$PATH"
unset CODE_SIGN_IDENTITY NOTARY_PROFILE FIXTURE_DIRTY
: > "$RELEASE_FIXTURE/identities"

check_failure() {
    local name="$1" expected="$2" version="${3:-9.9.9}"
    if bash "$RELEASE_FIXTURE/Scripts/release.sh" "$version" > "$RELEASE_FIXTURE/output" 2>&1; then
        echo "FAIL: $name unexpectedly succeeded" >&2
        exit 1
    fi
    if ! grep -Fq "$expected" "$RELEASE_FIXTURE/output"; then
        echo "FAIL: $name did not report the expected error" >&2
        cat "$RELEASE_FIXTURE/output" >&2
        exit 1
    fi
    if [ -e "$RELEASE_FIXTURE/tag-called" ] || [ -e "$RELEASE_FIXTURE/build-called" ]; then
        echo "FAIL: $name attempted to tag or build" >&2
        exit 1
    fi
    echo "PASS: $name rejected before tagging or building"
}

check_failure invalid-version 'is not a version like' invalid
export FIXTURE_DIRTY=1
check_failure uncommitted-changes 'uncommitted changes'
unset FIXTURE_DIRTY

check_failure missing-profile 'NOTARY_PROFILE is required'
export NOTARY_PROFILE=fixture-profile
check_failure missing-developer-id 'Found 0 matching identities'

printf '%s\n' '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Example (ABCDEFGHIJ)"' > "$RELEASE_FIXTURE/identities"
export CODE_SIGN_IDENTITY='Apple Development: Example (ABCDEFGHIJ)'
check_failure development-identity 'Found 0 matching identities'
unset CODE_SIGN_IDENTITY

check_failure invalid-notary-profile 'fixture notarization profile is unavailable'
printf '%s\n' '  2) ABCDEF0123456789ABCDEF0123456789ABCDEF01 "Developer ID Application: Other (KLMNOPQRST)"' >> "$RELEASE_FIXTURE/identities"
check_failure ambiguous-developer-id 'Found 2 matching identities'
