# Block editor benchmarks

Measurement tooling for the block editor architecture decision. Not part of the
regression suite — nothing here runs during `test_e2e.sh`.

Background and results: `.claude/plans/block-editor-architecture/`.

## 1. Seed the fixtures

```sh
cd e2e && source .envrc && MIX_ENV=e2e mix run priv/repo/e2e_seeds_large.exs
```

Builds `/bench-flat-5`, `/bench-flat-40`, `/bench-flat-115` (five mixed module
types) and `/bench-nested` (40 containers × multi × 2 entries = 160 blocks over
3 levels). Idempotent. Writes entry ids to
`e2e/e2e/playwright/bench/fixture-ids.json` (gitignored).

## 2. Payload and latency

```sh
cd e2e/e2e/playwright
pnpm playwright test --config bench/playwright.bench.config.js
```

Records, per entry size: mount payload + wall clock, single-edit in/out bytes
(first block and last block), insert latency, save latency. Prints `BENCH_ROW`
JSON per entry.

## 3. Server-side memory

LiveComponents are not separate processes — every Block/RenderVar component's
assigns live on the parent LiveView process heap, so editor memory is only
visible from inside the BEAM.

Start the server as a named node:

```sh
cd e2e && source .envrc
MIX_ENV=e2e PORT=4444 elixir --sname brandobench --cookie benchcookie -S mix phx.server
```

Hold an entry open (keeps the LiveView connected while you measure):

```sh
cd e2e/e2e/playwright
BENCH_ENTRY=115 HOLD_MS=40000 pnpm playwright test \
  --config bench/playwright.bench.config.js --grep "hold entry"
```

`BENCH_ENTRY` is `5`, `40`, `115` or `nested`. Then, while it holds:

```sh
cd e2e/bench
elixir --sname measure --cookie benchcookie measure_lv_memory.exs
```

Reports the `PageFormLive` process and its socket handler, before and after a
forced GC. **The post-GC number is the one that matters** — right after mount the
heap is full of render garbage that would be collected anyway.

## Gotchas

- Playwright's `actionTimeout` defaults to unlimited and the repo config doesn't
  set one, so a mistyped locator in a long-timeout spec blocks for the whole test
  timeout instead of failing. `bench/playwright.bench.config.js` sets it to 20s;
  do the same in any spec that raises its own timeout.
- `evalLV` in `e2e/e2e/playwright/utils.js` is dead — no `sandbox:eval` handler
  exists anywhere in the codebase. That's why memory is measured over
  distribution instead.
