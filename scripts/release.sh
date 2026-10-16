#!/bin/bash
# Publishes a Quote Pilot release on GitHub: scripts/release.sh 1.1.0
#
# Bump CFBundleShortVersionString (and CFBundleVersion) in Resources/Info.plist first and commit it to
# main. This script edits no file in the repo. It checks, tests, builds, zips, tags and publishes, and
# stops at the first thing that goes wrong. Quote Pilot's updater picks up the newest release's
# QuotePilot-mac.zip, so what goes out here is what people get.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: scripts/release.sh <version>   (for example 1.1.0)" >&2
    exit 2
fi
version="$1"
tag="v$version"

cd "$(dirname "$0")/.."

step=""
say() {
    step="$1"
    echo
    echo "==> $1"
}
trap 'echo >&2; echo "Stopped at: ${step:-the start}. Nothing after that step was done." >&2' ERR

fail() {
    echo "$1" >&2
    exit 1
}

say "Checking the version ($version)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "The version must look like 1.2.3, not '$version'."
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[ "$plist_version" = "$version" ] \
    || fail "Resources/Info.plist says $plist_version, not $version. Bump it and commit it first."

say "Checking the tree is clean and on main"
[ -z "$(git status --porcelain)" ] || fail "There are uncommitted changes. Commit or move them first."
branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || fail "You are on '$branch'. Releases are made from main."

say "Checking $tag is new and gh is ready"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "The tag $tag already exists here."
git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 && fail "The tag $tag already exists on GitHub."
command -v gh >/dev/null || fail "The GitHub CLI (gh) isn't installed."
gh auth status >/dev/null 2>&1 || fail "gh isn't signed in. Run: gh auth login"

# Command Line Tools 27.0's macOS 27 SDK can't build SwiftUI's @State without Xcode; use the macOS 26.5
# SDK the tools also include (build.sh does the same).
if [ -z "${SDKROOT:-}" ] && sdk="$(xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null)"; then
    export SDKROOT="$sdk"
fi

say "Running the tests"
swift test

say "Building Quote Pilot.app"
./build.sh
built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "build/Quote Pilot.app/Contents/Info.plist")"
[ "$built_version" = "$version" ] || fail "The app that was built is $built_version, not $version."

say "Zipping it to build/QuotePilot-mac.zip"
ditto -c -k --keepParent "build/Quote Pilot.app" build/QuotePilot-mac.zip

say "Tagging $tag and pushing the tag"
git tag "$tag"
git push origin "$tag"

say "Creating the GitHub release"
gh release create "$tag" build/QuotePilot-mac.zip --title "Quote Pilot $version" --generate-notes

echo
echo "Released Quote Pilot $version. Copies of Quote Pilot will offer it within a day, or at Help > Check for Updates."
