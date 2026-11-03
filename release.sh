#!/bin/bash
# Publishes a GitHub release and updates the Homebrew cask.
# Usage: ./release.sh 1.0.1
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
REPO="zakarlyya/mta"
TAP_REPO="zakarlyya/homebrew-tap"
ZIP="build/MTABar.zip"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit your changes first." >&2
    exit 1
fi

VERSION="$VERSION" ./build.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/MTABar.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "MTA Bar $VERSION" --generate-notes

TAP_DIR="$(mktemp -d)"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --quiet
sed -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    "$TAP_DIR/Casks/mtabar.rb" > "$TAP_DIR/Casks/mtabar.rb.new"
mv "$TAP_DIR/Casks/mtabar.rb.new" "$TAP_DIR/Casks/mtabar.rb"
git -C "$TAP_DIR" commit -qam "mtabar $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"

echo "Released $VERSION (sha256 $SHA)"
