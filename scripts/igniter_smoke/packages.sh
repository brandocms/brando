#!/usr/bin/env bash
set -euo pipefail

# Builds the Hex and npm packages a release would publish, from a scratch copy
# of FRAMEWORK set to a release candidate version, into ROOT/packages:
#
#   brando-VERSION.tar                  the Hex tarball (`mix hex.build`)
#   hex/                                its contents, as `mix deps.get` unpacks them
#   brandocms-brandojs-VERSION.tgz      the npm tarball (`npm pack`)
#   VERSION                             the candidate version
#
# Logs and content listings go to ROOT/logs. The scratch copy is deleted
# afterwards, so no Brando checkout is left next to the consumer.
#
#   BRANDO_SMOKE_VERSION  the candidate version (default: mix.exs's X.Y.Z + -rc.smoke)
framework="${1:?usage: packages.sh FRAMEWORK ROOT}"
root="${2:?usage: packages.sh FRAMEWORK ROOT}"
release="$root/release-copy"
packages="$root/packages"
logs="$root/logs"
mkdir -p "$release" "$packages" "$logs"

# Tracked and untracked-but-not-ignored files, as a clean clone with the local
# edits would have them: no deps, _build, node_modules or .yalc.
git -C "$framework" ls-files -z --cached --others --exclude-standard |
  (cd "$framework" && perl -0ne 'chomp; print "$_\0" if -e $_' | tar --null -T - -cf -) |
  tar -xf - -C "$release"

current="$(sed -n 's/^  @version "\([^"]*\)"$/\1/p' "$release/mix.exs")"
version="${BRANDO_SMOKE_VERSION:-${current%%-*}-rc.smoke}"
# A development version generates a Yalc copy instead of the npm pin.
case "$version" in
  *-dev | *-dev.*) echo "packages.sh: $version is a development version; pick a release candidate" >&2; exit 2 ;;
esac
# Only the scratch copy is bumped, and a run on a release tag must not check
# the candidate against that tag.
env -u GITHUB_REF_TYPE -u GITHUB_REF_NAME RELEASE_VERSION_ROOT="$release" \
  "$release/scripts/release-version" bump "$version" > "$logs/release-version.log" 2>&1

(cd "$release" && mix hex.build --output "$packages/brando-$version.tar") > "$logs/hex-build.log" 2>&1
mkdir "$packages/hex"
tar -xOf "$packages/brando-$version.tar" contents.tar.gz | tar -xzf - -C "$packages/hex"
tar -xOf "$packages/brando-$version.tar" metadata.config > "$packages/hex/hex_metadata.config"
tar -xOf "$packages/brando-$version.tar" contents.tar.gz | tar -tvzf - > "$logs/hex-contents.txt"

(cd "$release/assets" && npm pack --ignore-scripts --pack-destination "$packages" --json) > "$logs/npm-pack.json" 2> "$logs/npm-pack.log"
npm_tarball="$packages/brandocms-brandojs-$version.tgz"
test -f "$npm_tarball"
tar -tvzf "$npm_tarball" > "$logs/npm-contents.txt"
rm -rf "$release"

# Local build and linking state must never reach a package.
if grep -E '(^|[ /])(node_modules|_build|deps|\.yalc|yalc\.lock)(/|$)' "$logs/hex-contents.txt" "$logs/npm-contents.txt"; then
  echo "packages.sh: a package contains local build or linking state (above)" >&2
  exit 1
fi

echo "$version" > "$packages/VERSION"
hex_files="$(grep -c '^-' "$logs/hex-contents.txt")"
npm_files="$(grep -c '^-' "$logs/npm-contents.txt")"
hex_bytes="$(wc -c < "$packages/brando-$version.tar" | tr -d ' ')"
npm_bytes="$(wc -c < "$npm_tarball" | tr -d ' ')"
echo "Hex brando $version: $hex_files files, $hex_bytes bytes; npm @brandocms/brandojs $version: $npm_files files, $npm_bytes bytes" |
  tee "$logs/packages.log"
