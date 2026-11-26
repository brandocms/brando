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
# With multi the admin answers on the endpoint's host only (localhost, what
# the generated dev config sets) and the site on the domain seed.exs gives it.
smoke_site_url="http://127.0.0.1:$smoke_port"
if [[ "$smoke_mode" == multi ]]; then smoke_admin_url="http://localhost:$smoke_port"; else smoke_admin_url="$smoke_site_url"; fi
smoke_server_pid=''
# The consumer's endpoint watchers start its two Vite dev servers on these
# ports, which Brando.HTML reads too. Off the defaults, so other sites' Vite
# servers on 3000 and 3333 cannot stand in for them.
export BRANDO_VITE_ADMIN_PORT="${BRANDO_SMOKE_VITE_ADMIN_PORT:-$((smoke_port + 1))}"
export BRANDO_VITE_FRONTEND_PORT="${BRANDO_SMOKE_VITE_FRONTEND_PORT:-$((smoke_port + 2))}"
smoke_vite_ports=("$BRANDO_VITE_ADMIN_PORT" "$BRANDO_VITE_FRONTEND_PORT")
mkdir -p "$smoke_root/logs"
echo "Igniter $smoke_mode smoke consumer ($smoke_source): $smoke_root"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "root=$smoke_root" >> "$GITHUB_OUTPUT"; fi
trap 'echo "Smoke failed near line $LINENO; inspect $smoke_root/logs" >&2' ERR

listening() { curl --silent --output /dev/null "http://localhost:$1/"; }

# Stopping Phoenix stops its Brando.Vite watchers, which stop Vite. A Vite
# server still listening afterwards fails the run.
stop_server() {
  if [[ -n "$smoke_server_pid" ]]; then
    kill "$smoke_server_pid" 2>/dev/null || true
    wait "$smoke_server_pid" 2>/dev/null || true
    smoke_server_pid=''
    local port attempt
    for port in "${smoke_vite_ports[@]}"; do
      for attempt in $(seq 1 20); do
        if ! listening "$port"; then continue 2; fi
        sleep 0.5
      done
      echo "A Vite dev server still listens on port $port after the consumer stopped" >&2
      return 1
    done
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
  # Brando compiled there without its optional dependencies, Igniter, req_llm
  # and lazy_html (phx.new lists it for tests only): its part of the log (from
  # "==> brando" to the next app) has no warning.
  awk '/^==> /{brando = ($2 == "brando")} brando' "$smoke_root/logs/compile-without-igniter.log" > "$smoke_root/logs/brando-without-optional-deps.log"
  if ! grep -q 'Generated brando app' "$smoke_root/logs/brando-without-optional-deps.log" ||
    grep -q 'warning:' "$smoke_root/logs/brando-without-optional-deps.log"; then
    echo "Brando did not compile warning-free without Igniter, req_llm and lazy_html; see $smoke_root/logs/brando-without-optional-deps.log" >&2
    exit 1
  fi
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
# Brando parses HTML with the optional lazy_html: the installer drops the
# `only: :test` of phx.new's line, so a release has it.
if ! grep -qE '^[[:space:]]*\{:lazy_html, "[^"]+"\},?$' mix.exs; then echo "brando.install left lazy_html out of the runtime dependencies" >&2; exit 1; fi
# AI needs the optional req_llm, which the installer adds only with --ai: the
# consumer, its admin and its site below run with AI unavailable.
if grep -q ':req_llm' mix.exs; then echo "brando.install added req_llm without --ai" >&2; exit 1; fi
mix run --no-start -e 'false = Code.ensure_loaded?(ReqLLM); false = Brando.AI.available?(); false = Brando.AI.enabled?()' > "$smoke_root/logs/check-without-req-llm.log" 2>&1
if grep -l '__BRANDO_' .envrc.prod .envrc.staging config/dev.secret.exs; then echo "brando.install.secrets left markers in the files above" >&2; exit 1; fi
# Brando.Crypto's secret: one value for the site, in the three files.
encryption_secrets="$(
  { sed -n 's/^export BRANDO_ENCRYPTION_SECRET="\(.*\)"$/\1/p' .envrc.prod .envrc.staging
    sed -n 's/.*Brando\.Crypto, secret: "\(.*\)"$/\1/p' config/dev.secret.exs; } | sort -u
)"
if [[ "$(printf '%s\n' "$encryption_secrets" | grep -c .)" -ne 1 ]]; then
  echo "brando.install did not give .envrc.prod, .envrc.staging and config/dev.secret.exs one encryption secret" >&2
  exit 1
fi
# What Florist's release build needs, and the live preview of CMS pages.
cmp Dockerfile "$brando_dir/priv/templates/brando.install/Dockerfile"
# With :multi the installer also keeps each site project's dependencies and build out of the context.
if [ "$smoke_mode" = multi ]; then
  awk '{ print } $0 == "assets/frontend/node_modules" { print "assets/sites/*/node_modules"; print "assets/sites/*/dist" }' \
    "$brando_dir/priv/templates/brando.install/dockerignore" | cmp .dockerignore -
else
  cmp .dockerignore "$brando_dir/priv/templates/brando.install/dockerignore"
fi
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
elixir "$framework_dir/scripts/igniter_smoke/blocks_blueprint.exs"
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
# Every migration again, on an empty database, now that the app has a Blueprint
# with blocks: a new server, CI or a new test database migrates this way.
mix run --no-start "$framework_dir/scripts/igniter_smoke/fresh_migrations.exs" > "$smoke_root/logs/fresh-migrations.log" 2>&1
if grep -q 'is deprecated' "$smoke_root/logs/fresh-migrations.log"; then
  echo "A migration Brando installed calls a deprecated function; see $smoke_root/logs/fresh-migrations.log" >&2
  exit 1
fi
if [[ "$smoke_bootstrap" == precompiled ]]; then
  mix run "$framework_dir/scripts/igniter_smoke/check_customized.exs" > "$smoke_root/logs/check-customized.log" 2>&1
fi

# Starts the consumer and waits for the admin's /admin/login, and with "vite" for both
# Vite dev servers too.
start_server() {
  local log="$1" wait_for_vite="${2:-}" attempt
  PORT="$smoke_port" mix phx.server > "$smoke_root/logs/$log" 2>&1 &
  smoke_server_pid=$!
  for attempt in $(seq 1 90); do
    if curl --silent --fail "$smoke_admin_url/admin/login" > /dev/null &&
      { [[ "$wait_for_vite" != vite ]] || {
        curl --silent --fail "http://localhost:$BRANDO_VITE_ADMIN_PORT/@vite/client" > /dev/null &&
          curl --silent --fail "http://localhost:$BRANDO_VITE_FRONTEND_PORT/@vite/client" > /dev/null
      }; }; then
      return 0
    fi
    if ! kill -0 "$smoke_server_pid" 2>/dev/null; then break; fi
    sleep 1
  done
  echo "Consumer or its Vite servers did not start; inspect $smoke_root/logs/$log" >&2
  return 1
}

run_browser() {
  BRANDO_SMOKE_BASE_URL="$smoke_site_url" BRANDO_SMOKE_ADMIN_URL="$smoke_admin_url" \
    BRANDO_SMOKE_TENANCY_MODE="$smoke_mode" BRANDO_SMOKE_ARTIFACTS="$smoke_root/browser-$1" \
    pnpm --dir "$framework_dir/scripts/igniter_smoke" exec playwright test --config playwright.config.js > "$smoke_root/logs/browser-$1.log" 2>&1
}

# As users get it: hmr: true in dev.exs, with the endpoint's watchers starting
# both Vite dev servers.
for port in "${smoke_vite_ports[@]}"; do
  if listening "$port"; then echo "Port $port already answers; the consumer's Vite needs it" >&2; exit 1; fi
done
mix run --no-start "$framework_dir/scripts/igniter_smoke/database.exs" snapshot > "$smoke_root/logs/database-snapshot.log" 2>&1
start_server server.log vite
admin_login="$(curl --silent --fail "$smoke_admin_url/admin/login")"
if [[ "$admin_login" != *"http://localhost:$BRANDO_VITE_ADMIN_PORT/@vite/client"* ]]; then
  echo "With hmr: true the admin did not load Vite's client; inspect $smoke_root/logs/server.log" >&2
  exit 1
fi
run_browser vite
stop_server

# The built assets, as production serves them: the browser tests again, on
# the database as seeded, with hmr: false, so a template that does not build,
# or builds the wrong entries, fails here and not only in a deploy.
mix run --no-start "$framework_dir/scripts/igniter_smoke/database.exs" restore > "$smoke_root/logs/database-restore.log" 2>&1
printf '\nconfig :igniter_smoke, hmr: false\n' >> config/dev.exs
start_server server-built.log
admin_login="$(curl --silent --fail "$smoke_admin_url/admin/login")"
if [[ "$admin_login" == *"@vite/client"* || "$admin_login" != *"/assets/admin/admin-"* ]]; then
  echo "With hmr: false the admin did not load its built assets; inspect $smoke_root/logs/server-built.log" >&2
  exit 1
fi
run_browser built
stop_server
if [[ "$smoke_source" == packaged ]]; then
  if [[ "$(package_digest)" != "$package_before" ]]; then echo "The consumer wrote into the Hex package at $brando_dir" >&2; exit 1; fi
  # Nothing in the consumer, its dependencies or node_modules may name the checkout.
  # grep exits 1 for no match; 2, an unreadable file, must not pass as one.
  references=0
  grep -rlF -e "$framework_dir" -e "$(cd "$framework_dir" && pwd -P)" . > "$smoke_root/logs/checkout-references.log" ||
    references=$?
  if [[ "$references" -ne 1 ]]; then
    echo "The consumer references the Brando checkout, or the scan failed (grep exit $references); see $smoke_root/logs/checkout-references.log" >&2
    exit 1
  fi
fi
echo "Igniter $smoke_mode smoke passed: $smoke_root"
