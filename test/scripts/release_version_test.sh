#!/usr/bin/env bash
# Checks scripts/release-version against version files in a scratch
# directory: which combinations `check` accepts, and what `bump` writes.
# Needs bash and jq.
#
#   bash test/scripts/release_version_test.sh
set -uo pipefail

# shellcheck source=test/scripts/isolate.sh
. "$(dirname "$0")/isolate.sh"

root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/scripts/release-version"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/release-version-test.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

failures=0
case_root=""

# fresh [VERSION] — a scratch repository where everything agrees on VERSION
# (default 0.55.0-dev), the backend template on a local Yalc package and the
# template mix.exs on a path dependency.
fresh() {
  local version="${1:-0.55.0-dev}" tag=beta
  case "$version" in *-*) ;; *) tag=latest ;; esac
  case_root="$scratch/case"
  rm -rf "$case_root"
  mkdir -p "$case_root/assets" "$case_root/e2e" "$case_root/priv/templates/brando.install/assets/backend"
  cat >"$case_root/mix.exs" <<EOF
defmodule Brando.Mixfile do
  use Mix.Project

  @version "$version"

  defp deps do
    [
      {:phoenix, "1.8.15"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_live_view, "1.2.12"},
      {:phoenix_html, "~> 4.0"}
    ]
  end
end
EOF
  cat >"$case_root/e2e/mix.exs" <<'EOF'
defmodule E2eProject.MixProject do
  defp deps do
    [
      {:phoenix, "1.8.15"},
      {:phoenix_live_view, "1.2.12"}
    ]
  end
end
EOF
  cat >"$case_root/assets/package.json" <<EOF
{
  "name": "@brandocms/brandojs",
  "version": "$version",
  "publishConfig": {
    "access": "public",
    "tag": "$tag"
  },
  "dependencies": {
    "phoenix": "1.8.15",
    "phoenix_live_view": "1.2.12"
  }
}
EOF
  cat >"$case_root/priv/templates/brando.install/assets/backend/package.json" <<'EOF'
{
  "name": "backend",
  "version": "0.0.0",
  "dependencies": {
    "@brandocms/brandojs": "file:.yalc/@brandocms/brandojs",
    "@brandocms/jupiter": "5.0.0-beta.19"
  }
}
EOF
  cat >"$case_root/priv/templates/brando.install/mix.exs" <<'EOF'
  defp deps do
    [
      # brando
      # {:brando, github: "brandocms/brando"}
      {:brando, path: "../../brando"}
    ]
  end
EOF
}

run() {
  env -u GITHUB_REF_TYPE -u GITHUB_REF_NAME RELEASE_ROOT="$case_root" "$script" "$@" 2>&1
}

# set_json FILE FILTER ARGS... — edits a JSON file in the case.
set_json() {
  local file="$case_root/$1"
  shift
  jq "$@" "$file" >"$file.new" && mv "$file.new" "$file"
}

# set_line FILE OLD NEW — replaces a line containing OLD in a case file.
set_line() {
  local file="$case_root/$1"
  awk -v old="$2" -v new="$3" 'index($0, old) { print new; next } { print }' "$file" >"$file.new" && mv "$file.new" "$file"
}

pass() { echo "ok   $1"; }
fail() {
  failures=$((failures + 1))
  echo "FAIL $1"
  shift
  local line
  for line in "$@"; do echo "     $line"; done
}

# expect <case> <exit status> <text the output must contain> <args...>
expect() {
  local name="$1" want_status="$2" want="$3" output status
  shift 3
  output="$(run "$@")"
  status=$?
  if [ "$status" -eq "$want_status" ] && grep -qF -- "$want" <<<"$output"; then
    pass "$name"
  else
    fail "$name" "expected exit $want_status and: $want" "got exit $status:" "$output"
  fi
}

# expect_file <case> <file> — the case file matches stdin.
expect_file() {
  local name="$1" diff
  if diff="$(diff -u - "$case_root/$2")"; then
    pass "$name"
  else
    fail "$name" "$diff"
  fi
}

backend="priv/templates/brando.install/assets/backend/package.json"
template="priv/templates/brando.install/mix.exs"

fresh
expect "agreeing versions pass" 0 "release-version: 0.55.0-dev in mix.exs and assets/package.json (npm dist-tag beta)" check

fresh
set_json assets/package.json '.version = "0.54.0"'
expect "an npm version behind mix.exs fails" 1 \
  "assets/package.json has version 0.54.0, mix.exs has 0.55.0-dev (scripts/release-version bump 0.55.0-dev)" check

fresh
set_json assets/package.json '.publishConfig.tag = "latest"'
expect "a prerelease under latest fails" 1 "publishConfig.tag latest; 0.55.0-dev publishes under beta" check

fresh 0.55.0
set_json assets/package.json '.publishConfig.tag = "beta"'
expect "a stable version under beta fails" 1 "publishConfig.tag beta; 0.55.0 publishes under latest" check

fresh 0.55.0
expect "a stable version under latest passes" 0 "(npm dist-tag latest)" check

fresh
set_json assets/package.json 'del(.publishConfig)'
expect "a missing publishConfig.tag fails" 1 "publishConfig.tag (none)" check

fresh
sed 's/^  @version .*/  @version "0.55"/' "$case_root/mix.exs" >"$case_root/mix.new" && mv "$case_root/mix.new" "$case_root/mix.exs"
expect "a malformed mix.exs version fails" 1 "@version 0.55 is not a version" check

fresh
grep -v '@version' "$case_root/mix.exs" >"$case_root/mix.new" && mv "$case_root/mix.new" "$case_root/mix.exs"
expect "a mix.exs without @version fails" 1 "mix.exs needs exactly one line" check

fresh
set_json "$backend" '.dependencies["@brandocms/brandojs"] = "link:../../../assets"'
expect "a link: BrandoJS pin passes" 0 "generator pins agree" check

fresh
set_json "$backend" '.dependencies["@brandocms/brandojs"] = "0.55.0-dev"'
expect "an exact BrandoJS pin on the version passes" 0 "generator pins agree" check

fresh
set_json "$backend" '.dependencies["@brandocms/brandojs"] = "0.54.0"'
expect "an exact BrandoJS pin on another version fails" 1 \
  "pins @brandocms/brandojs to 0.54.0: use exactly 0.55.0-dev, or a local file:/link: package" check

fresh
set_json "$backend" '.dependencies["@brandocms/brandojs"] = "^0.55.0-dev"'
expect "a BrandoJS range fails" 1 "pins @brandocms/brandojs to ^0.55.0-dev" check

fresh
set_json "$backend" 'del(.dependencies["@brandocms/brandojs"]) | .devDependencies = {"@brandocms/brandojs": "0.55.0-dev"}'
expect "an exact BrandoJS pin in devDependencies passes" 0 "generator pins agree" check

fresh
set_json "$backend" 'del(.dependencies["@brandocms/brandojs"])'
expect "a backend template without BrandoJS fails" 1 "has no @brandocms/brandojs dependency" check

fresh
set_line "$template" '{:brando, path:' '      {:brando, "== 0.55.0-dev"}'
expect "an == Brando requirement on the version passes" 0 "generator pins agree" check

fresh
set_line "$template" '{:brando, path:' '      {:brando, "0.55.0-dev"}'
expect "a bare Brando version passes" 0 "generator pins agree" check

fresh
set_line "$template" '{:brando, path:' '      {:brando, "~> 0.55.0-dev"}'
expect "a Brando range fails" 1 "requires {:brando, \"~> 0.55.0-dev\"}: use exactly \"0.55.0-dev\"" check

fresh
set_line "$template" '{:brando, path:' '      {:brando, github: "brandocms/brando", branch: "main"}'
expect "a github: Brando dependency passes" 0 "generator pins agree" check

fresh
set_line "$template" '{:brando, path:' '      # gone'
expect "a template without a Brando dependency fails" 1 "has no {:brando, …} dependency" check

fresh
set_json assets/package.json '.dependencies.phoenix_live_view = "1.2.11"'
expect "LiveView JS behind Elixir fails" 1 "assets/package.json has phoenix_live_view 1.2.11, mix.exs has 1.2.12" check

fresh
set_line e2e/mix.exs '{:phoenix, ' '      {:phoenix, "1.8.14"},'
expect "the E2E app on another Phoenix fails" 1 "e2e/mix.exs has phoenix 1.8.14, mix.exs has 1.8.15" check

fresh
set_line mix.exs '{:phoenix_live_view, ' '      {:phoenix_live_view, "~> 1.2"},'
expect "a LiveView range in mix.exs fails" 1 "mix.exs needs an exact {:phoenix_live_view, \"X.Y.Z\"}" check

fresh
expect "a matching --tag passes" 0 "and tag v0.55.0-dev;" check --tag v0.55.0-dev
expect "another --tag fails" 1 "tag v0.55.0-beta.0 does not match mix.exs's version 0.55.0-dev (expected v0.55.0-dev)" \
  check --tag v0.55.0-beta.0
expect "a tag without the v fails" 1 "tag 0.55.0-dev does not match" check --tag 0.55.0-dev

name="a pushed tag in GitHub Actions is checked"
output="$(GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v0.54.0 RELEASE_ROOT="$case_root" "$script" check 2>&1)"
if [ $? -eq 1 ] && grep -qF "tag v0.54.0 does not match" <<<"$output"; then pass "$name"; else fail "$name" "$output"; fi

name="a branch ref in GitHub Actions is not a tag"
output="$(GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main RELEASE_ROOT="$case_root" "$script" check 2>&1)"
if [ $? -eq 0 ]; then pass "$name"; else fail "$name" "$output"; fi

expect "check rejects unknown arguments" 2 "usage: scripts/release-version" check --tags v1
expect "a missing command prints usage" 2 "usage: scripts/release-version"

# bump: a prerelease with the generator on exact pins.
fresh
set_json "$backend" '.dependencies["@brandocms/brandojs"] = "0.55.0-dev"'
set_line "$template" '{:brando, path:' '      {:brando, "== 0.55.0-dev"}'
expect "bump to a prerelease passes the check" 0 "release-version: 0.55.0-beta.0 in mix.exs" bump 0.55.0-beta.0
expect "bump moved the version line in mix.exs" 0 "0.55.0-beta.0" check --tag v0.55.0-beta.0
expect_file "bump rewrites only the npm version" assets/package.json <<'EOF'
{
  "name": "@brandocms/brandojs",
  "version": "0.55.0-beta.0",
  "publishConfig": {
    "access": "public",
    "tag": "beta"
  },
  "dependencies": {
    "phoenix": "1.8.15",
    "phoenix_live_view": "1.2.12"
  }
}
EOF
expect_file "bump moves an exact BrandoJS pin" "$backend" <<'EOF'
{
  "name": "backend",
  "version": "0.0.0",
  "dependencies": {
    "@brandocms/brandojs": "0.55.0-beta.0",
    "@brandocms/jupiter": "5.0.0-beta.19"
  }
}
EOF
if grep -qxF '      {:brando, "== 0.55.0-beta.0"}' "$case_root/$template"; then
  pass "bump moves an exact Brando requirement"
else
  fail "bump moves an exact Brando requirement" "$(cat "$case_root/$template")"
fi

# bump: to stable, with the generator on local sources.
fresh 0.55.0-beta.0
cp "$case_root/$backend" "$scratch/backend.before"
cp "$case_root/$template" "$scratch/template.before"
expect "bump to a stable version switches the dist-tag to latest" 0 "(npm dist-tag latest)" bump 0.55.0
if cmp -s "$scratch/backend.before" "$case_root/$backend" && cmp -s "$scratch/template.before" "$case_root/$template"; then
  pass "bump leaves local generator sources alone"
else
  fail "bump leaves local generator sources alone"
fi
if grep -qxF '  @version "0.55.0"' "$case_root/mix.exs"; then
  pass "bump writes the mix.exs version"
else
  fail "bump writes the mix.exs version" "$(grep version "$case_root/mix.exs")"
fi

fresh
expect "bump rejects a leading v" 2 "v0.55.0 is not a version like 0.55.0" bump v0.55.0
expect "bump rejects a partial version" 2 "0.55 is not a version" bump 0.55
if grep -qxF '  @version "0.55.0-dev"' "$case_root/mix.exs"; then
  pass "a rejected bump changes nothing"
else
  fail "a rejected bump changes nothing" "$(grep version "$case_root/mix.exs")"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) failed"
  exit 1
fi
echo "all cases passed"
