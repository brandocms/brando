#!/usr/bin/env bash
set -euo pipefail

# Requires an explicit disposable PostgreSQL service, phx_new 1.8.13, pnpm,
# Yalc (checkout source only) and Playwright Chromium. Only the generated
# consumer builds JS/CSS.
#
#   BRANDO_SMOKE_SOURCE  checkout (default): Brando as a path dependency on this
#                        checkout, BrandoJS through Yalc. packaged: the Hex and npm
#                        packages a release candidate would publish (see
#                        scripts/igniter_smoke/packages.sh), with no checkout or Yalc.
: "${BRANDO_SMOKE_PGPORT:?Set BRANDO_SMOKE_PGPORT to a disposable PostgreSQL service}"
smoke_mode="${1:-none}"
case "$smoke_mode" in none|single|multi) ;; *) echo 'Expected none, single or multi' >&2; exit 2 ;; esac
smoke_bootstrap="${BRANDO_SMOKE_BOOTSTRAP:-fresh}"
case "$smoke_bootstrap" in fresh|precompiled) ;; *) echo 'Expected fresh or precompiled bootstrap' >&2; exit 2 ;; esac
smoke_source="${BRANDO_SMOKE_SOURCE:-checkout}"
case "$smoke_source" in checkout|packaged) ;; *) echo 'Expected checkout or packaged source' >&2; exit 2 ;; esac
framework_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke_tmp="${TMPDIR:-/tmp}"
smoke_root="$(mktemp -d "${smoke_tmp%/}/brando-igniter-smoke.XXXXXX")"
smoke_app="$smoke_root/consumer"
smoke_database="brando_igniter_smoke_$(basename "$smoke_root" | tr '[:upper:].-' '[:lower:]__')"
smoke_port="${BRANDO_SMOKE_PORT:-4482}"
smoke_server_pid=''
mkdir -p "$smoke_root/logs"
echo "Igniter $smoke_mode smoke consumer ($smoke_source): $smoke_root"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "root=$smoke_root" >> "$GITHUB_OUTPUT"; fi
trap 'echo "Smoke failed near line $LINENO; inspect $smoke_root/logs" >&2' ERR

stop_server() {
  if [[ -n "$smoke_server_pid" ]]; then
    kill "$smoke_server_pid" 2>/dev/null || true
    wait "$smoke_server_pid" 2>/dev/null || true
  fi
}
trap stop_server EXIT

# The directory the consumer takes Brando from, and whose templates and skills
# the checks compare against.
brando_dir="$framework_dir"
if [[ "$smoke_source" == packaged ]]; then
  "$framework_dir/scripts/igniter_smoke/packages.sh" "$framework_dir" "$smoke_root"
  brando_dir="$smoke_root/packages/hex"
  smoke_version="$(cat "$smoke_root/packages/VERSION")"
  smoke_npm_tarball="$smoke_root/packages/brandocms-brandojs-$smoke_version.tgz"
  # Any Yalc run fails loudly: a released install must not need it.
  mkdir -p "$smoke_root/no-yalc"
  printf '#!/bin/sh\necho "packaged smoke: yalc must not run (yalc $*)" >&2\nexit 97\n' > "$smoke_root/no-yalc/yalc"
  chmod +x "$smoke_root/no-yalc/yalc"
  export PATH="$smoke_root/no-yalc:$PATH"
  package_digest() {
    (cd "$brando_dir" && { find . | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256; } | shasum -a 256)
  }
  package_before="$(package_digest)"
fi

if [[ -n "${BRANDO_SMOKE_PHX_EBIN:-}" ]]; then
  elixir -pa "$BRANDO_SMOKE_PHX_EBIN" -S mix phx.new "$smoke_app" --app igniter_smoke --module IgniterSmoke --no-install --no-assets --no-dashboard --no-mailer > "$smoke_root/logs/phoenix.log" 2>&1
else
  mix phx.new "$smoke_app" --app igniter_smoke --module IgniterSmoke --no-install --no-assets --no-dashboard --no-mailer > "$smoke_root/logs/phoenix.log" 2>&1
fi
cd "$smoke_app"
elixir "$framework_dir/scripts/igniter_smoke/bootstrap.exs" "$brando_dir" "$smoke_database" "$smoke_mode" "$smoke_port"
if [[ "$smoke_bootstrap" == precompiled ]]; then
  elixir "$framework_dir/scripts/igniter_smoke/customize.exs"
  elixir "$framework_dir/scripts/igniter_smoke/optional_dependency.exs" remove
  mix deps.get > "$smoke_root/logs/deps-without-igniter.log" 2>&1
  mix compile > "$smoke_root/logs/compile-without-igniter.log" 2>&1
  mix run --no-start -e 'false = Code.ensure_loaded?(Igniter); false = Mix.Brando.Igniter.Project.__mix_recompile__?()' > "$smoke_root/logs/check-without-igniter.log" 2>&1
  elixir "$framework_dir/scripts/igniter_smoke/optional_dependency.exs" add
fi
mix deps.get > "$smoke_root/logs/deps.log" 2>&1
if [[ "$smoke_bootstrap" == precompiled ]]; then
  mix deps.compile > "$smoke_root/logs/compile-with-igniter.log" 2>&1
fi
elixir "$framework_dir/scripts/igniter_smoke/fingerprint.exs" > "$smoke_root/before-preview"
mix brando.install --dry-run --yes > "$smoke_root/logs/preview.log" 2>&1
elixir "$framework_dir/scripts/igniter_smoke/fingerprint.exs" > "$smoke_root/after-preview"
cmp "$smoke_root/before-preview" "$smoke_root/after-preview"

# A new install adds the CMS public site, which takes / from phx.new's
# unchanged homepage.
install_options=(--yes --tenancy-mode "$smoke_mode")
if [[ "$smoke_mode" == single ]]; then install_options+=(--site-key smoke); fi
mix igniter.install "brando@path:$brando_dir" "${install_options[@]}" > "$smoke_root/logs/install.log" 2>&1
mix compile --warnings-as-errors > "$smoke_root/logs/compile.log" 2>&1
if grep -l '__BRANDO_' .envrc.prod .envrc.staging; then echo "brando.install.secrets left markers in the files above" >&2; exit 1; fi
# What Florist's release build needs, and the live preview of CMS pages.
cmp Dockerfile "$brando_dir/priv/templates/brando.install/Dockerfile"
cmp .dockerignore "$brando_dir/priv/templates/brando.install/dockerignore"
grep -q 'steps: \[:assemble, :tar\]' mix.exs
grep -q 'def migrate do' lib/igniter_smoke/release_tasks.ex
grep -q 'media_path: "./media"' config/prod.exs
grep -q 'preview_target Pages.Page do' lib/igniter_smoke_web/live_preview.ex
grep -Eq 'get[ (]"/", IgniterSmokeWeb\.CMS\.PageController, :index' lib/igniter_smoke_web/router.ex
if grep -Eq 'get[ (]"/", PageController, :home' lib/igniter_smoke_web/router.ex; then echo "phx.new's homepage route was not replaced" >&2; exit 1; fi
elixir "$framework_dir/scripts/igniter_smoke/fingerprint.exs" > "$smoke_root/before-rerun"
mix brando.install --yes > "$smoke_root/logs/rerun.log" 2>&1
elixir "$framework_dir/scripts/igniter_smoke/fingerprint.exs" > "$smoke_root/after-rerun"
cmp "$smoke_root/before-rerun" "$smoke_root/after-rerun"
elixir "$framework_dir/scripts/igniter_smoke/check_agent_files.exs" "$brando_dir" > "$smoke_root/logs/agent-files.log" 2>&1

elixir "$framework_dir/scripts/igniter_smoke/frontend_fixture.exs"
if [[ "$smoke_source" == packaged ]]; then
  mix run --no-start "$framework_dir/scripts/igniter_smoke/packaged.exs" pin "$smoke_version" "$smoke_npm_tarball" > "$smoke_root/logs/packaged-pin.log" 2>&1
fi
mix brando.assets.setup > "$smoke_root/logs/assets.log" 2>&1
mix run --no-start "$framework_dir/scripts/igniter_smoke/check_assets.exs" "$brando_dir" > "$smoke_root/logs/asset-bytes.log" 2>&1
if [[ "$smoke_source" == packaged ]]; then
  mix run --no-start "$framework_dir/scripts/igniter_smoke/packaged.exs" verify "$smoke_version" "$smoke_npm_tarball" > "$smoke_root/logs/packaged-verify.log" 2>&1
fi
mix ecto.create > "$smoke_root/logs/database-create.log" 2>&1
mix ecto.migrate > "$smoke_root/logs/framework-migrations.log" 2>&1
mix run "$framework_dir/scripts/igniter_smoke/seed.exs" > "$smoke_root/logs/seed.log" 2>&1
mix run "$framework_dir/scripts/igniter_smoke/seed_pages.exs" > "$smoke_root/logs/seed-pages.log" 2>&1

mix brando.gen.blueprint Catalog Product --yes > "$smoke_root/logs/blueprint.log" 2>&1
mix compile --warnings-as-errors > "$smoke_root/logs/blueprint-compile.log" 2>&1
mix brando.gen IgniterSmoke.Catalog.Product --public-route /products --yes > "$smoke_root/logs/resource.log" 2>&1
mix compile --warnings-as-errors > "$smoke_root/logs/resource-compile.log" 2>&1
mix brando.gen.blueprint_migration IgniterSmoke.Catalog.Product --yes > "$smoke_root/logs/resource-storage.log" 2>&1
# --all finds the consumer's Blueprints and, with Product planned, nothing left to plan.
mix brando.gen.blueprint_migration --all --check > "$smoke_root/logs/resource-storage-all.log" 2>&1
if [[ "$smoke_mode" == none ]]; then
  mix brando.migrate > "$smoke_root/logs/resource-migrate.log" 2>&1
else
  mix brando.migrate --tenants > "$smoke_root/logs/resource-migrate.log" 2>&1
fi
if [[ "$smoke_bootstrap" == precompiled ]]; then
  mix run "$framework_dir/scripts/igniter_smoke/check_customized.exs" > "$smoke_root/logs/check-customized.log" 2>&1
fi

# The installer enables HMR in dev.exs; the smoke serves the built manifests
# checked above instead of a Vite dev server.
printf '\nconfig :igniter_smoke, hmr: false\n' >> config/dev.exs
PORT="$smoke_port" mix phx.server > "$smoke_root/logs/server.log" 2>&1 &
smoke_server_pid=$!
smoke_ready=false
for attempt in $(seq 1 60); do
  if curl --silent --fail "http://127.0.0.1:$smoke_port/admin/login" > /dev/null; then smoke_ready=true; break; fi
  if ! kill -0 "$smoke_server_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [[ "$smoke_ready" != true ]]; then echo "Consumer did not start; inspect $smoke_root/logs/server.log" >&2; exit 1; fi
BRANDO_SMOKE_BASE_URL="http://127.0.0.1:$smoke_port" BRANDO_SMOKE_ARTIFACTS="$smoke_root/browser" \
  pnpm --dir "$framework_dir/scripts/igniter_smoke" exec playwright test --config playwright.config.js > "$smoke_root/logs/browser.log" 2>&1
if [[ "$smoke_source" == packaged ]]; then
  if [[ "$(package_digest)" != "$package_before" ]]; then echo "The consumer wrote into the Hex package at $brando_dir" >&2; exit 1; fi
  # Nothing in the consumer, its dependencies or node_modules may name the checkout.
  # grep exits 1 for no match; 2, an unreadable file, must not pass as one.
  stop_server
  references=0
  grep -rlF -e "$framework_dir" -e "$(cd "$framework_dir" && pwd -P)" . > "$smoke_root/logs/checkout-references.log" ||
    references=$?
  if [[ "$references" -ne 1 ]]; then
    echo "The consumer references the Brando checkout, or the scan failed (grep exit $references); see $smoke_root/logs/checkout-references.log" >&2
    exit 1
  fi
fi
echo "Igniter $smoke_mode smoke passed: $smoke_root"
