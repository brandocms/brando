#!/usr/bin/env bash
set -euo pipefail

# Requires an explicit disposable PostgreSQL service, phx_new 1.8.13, pnpm,
# Yalc and Playwright Chromium. Only the generated consumer builds JS/CSS.
: "${BRANDO_SMOKE_PGPORT:?Set BRANDO_SMOKE_PGPORT to a disposable PostgreSQL service}"
smoke_mode="${1:-none}"
case "$smoke_mode" in none|single|multi) ;; *) echo 'Expected none, single or multi' >&2; exit 2 ;; esac
smoke_bootstrap="${BRANDO_SMOKE_BOOTSTRAP:-fresh}"
case "$smoke_bootstrap" in fresh|precompiled) ;; *) echo 'Expected fresh or precompiled bootstrap' >&2; exit 2 ;; esac
framework_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/brando-igniter-smoke.XXXXXX")"
smoke_app="$smoke_root/consumer"
smoke_database="brando_igniter_smoke_$(basename "$smoke_root" | tr '[:upper:].-' '[:lower:]__')"
smoke_port="${BRANDO_SMOKE_PORT:-4482}"
smoke_server_pid=''
mkdir -p "$smoke_root/logs"
echo "Igniter $smoke_mode smoke consumer: $smoke_root"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "root=$smoke_root" >> "$GITHUB_OUTPUT"; fi
trap 'echo "Smoke failed near line $LINENO; inspect $smoke_root/logs" >&2' ERR

stop_server() {
  if [[ -n "$smoke_server_pid" ]]; then
    kill "$smoke_server_pid" 2>/dev/null || true
    wait "$smoke_server_pid" 2>/dev/null || true
  fi
}
trap stop_server EXIT

if [[ -n "${BRANDO_SMOKE_PHX_EBIN:-}" ]]; then
  elixir -pa "$BRANDO_SMOKE_PHX_EBIN" -S mix phx.new "$smoke_app" --app igniter_smoke --module IgniterSmoke --no-install --no-assets --no-dashboard --no-mailer > "$smoke_root/logs/phoenix.log" 2>&1
else
  mix phx.new "$smoke_app" --app igniter_smoke --module IgniterSmoke --no-install --no-assets --no-dashboard --no-mailer > "$smoke_root/logs/phoenix.log" 2>&1
fi
cd "$smoke_app"
elixir "$framework_dir/scripts/igniter_smoke/bootstrap.exs" "$framework_dir" "$smoke_database" "$smoke_mode" "$smoke_port"
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

install_options=(--yes --tenancy-mode "$smoke_mode" --public-site --replace-phoenix-home)
if [[ "$smoke_mode" == single ]]; then install_options+=(--site-key smoke); fi
mix igniter.install "brando@path:$framework_dir" "${install_options[@]}" > "$smoke_root/logs/install.log" 2>&1
mix compile --warnings-as-errors > "$smoke_root/logs/compile.log" 2>&1
elixir "$framework_dir/scripts/igniter_smoke/fingerprint.exs" > "$smoke_root/before-rerun"
mix brando.install --yes > "$smoke_root/logs/rerun.log" 2>&1
elixir "$framework_dir/scripts/igniter_smoke/fingerprint.exs" > "$smoke_root/after-rerun"
cmp "$smoke_root/before-rerun" "$smoke_root/after-rerun"

mix brando.assets.setup > "$smoke_root/logs/assets.log" 2>&1
mix run --no-start "$framework_dir/scripts/igniter_smoke/check_assets.exs" "$framework_dir" > "$smoke_root/logs/asset-bytes.log" 2>&1
mix ecto.create > "$smoke_root/logs/database-create.log" 2>&1
mix ecto.migrate > "$smoke_root/logs/framework-migrations.log" 2>&1
mix run "$framework_dir/scripts/igniter_smoke/seed.exs" > "$smoke_root/logs/seed.log" 2>&1
mix run "$framework_dir/scripts/igniter_smoke/seed_pages.exs" > "$smoke_root/logs/seed-pages.log" 2>&1

mix brando.gen.blueprint Catalog Product --yes > "$smoke_root/logs/blueprint.log" 2>&1
mix compile --warnings-as-errors > "$smoke_root/logs/blueprint-compile.log" 2>&1
mix brando.gen IgniterSmoke.Catalog.Product --public-route /products --yes > "$smoke_root/logs/resource.log" 2>&1
mix compile --warnings-as-errors > "$smoke_root/logs/resource-compile.log" 2>&1
mix brando.gen.blueprint_migration IgniterSmoke.Catalog.Product --yes > "$smoke_root/logs/resource-storage.log" 2>&1
if [[ "$smoke_mode" == none ]]; then
  mix brando.migrate > "$smoke_root/logs/resource-migrate.log" 2>&1
else
  mix brando.migrate --tenants > "$smoke_root/logs/resource-migrate.log" 2>&1
fi
if [[ "$smoke_bootstrap" == precompiled ]]; then
  mix run "$framework_dir/scripts/igniter_smoke/check_customized.exs" > "$smoke_root/logs/check-customized.log" 2>&1
fi

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
echo "Igniter $smoke_mode smoke passed: $smoke_root"
