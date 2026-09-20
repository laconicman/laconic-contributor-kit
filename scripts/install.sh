#!/usr/bin/env bash
# Install `contrib` and the resource bundle it needs.
#
# The binary ALONE is not enough and fails in a way that hides itself: SwiftPM's
# generated `Bundle.module` accessor falls back to the absolute path of the build
# directory, so a copied-alone binary keeps working right up until someone runs
# `swift package clean` — and then dies with an internal fatalError rather than a
# diagnosable message. Copy both, or don't copy.
#
#   ./scripts/install.sh [prefix]        # default: /usr/local/bin
set -euo pipefail

PREFIX="${1:-/usr/local/bin}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# `.build/release` is a symlink to the triple-specific directory; resolve it so
# `find` traverses the real one.
BUILD="$(cd "$ROOT/.build/release" && pwd -P)"

[ -x "$BUILD/contrib" ] || { echo "build it first:  swift build -c release" >&2; exit 1; }

BUNDLE="$(find "$BUILD" -maxdepth 1 -name '*_ContributorKit.bundle' -print -quit)"
[ -n "$BUNDLE" ] || { echo "no resource bundle in $BUILD — rebuild" >&2; exit 1; }

mkdir -p "$PREFIX"
install -m 0755 "$BUILD/contrib" "$PREFIX/contrib"
# Remove every ContributorKit bundle, not just this build's: the package has been
# renamed once, and a stale bundle beside the binary is exactly the kind of thing
# that works until it doesn't.
rm -rf "$PREFIX"/*_ContributorKit.bundle
cp -R "$BUNDLE" "$PREFIX/"

echo "installed:"
echo "  $PREFIX/contrib"
echo "  $PREFIX/$(basename "$BUNDLE")"
echo
"$PREFIX/contrib" --version
