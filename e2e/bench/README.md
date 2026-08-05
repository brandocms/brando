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

## 4. Where the time goes (server vs browser)

Wall clock conflates three things with different fixes, so measure them apart:

- **Server round trip** — first frame sent to last frame received.
- **Browser main thread** — `PerformanceObserver` on `longtask` (blocks over 50 ms).
- The remainder is Playwright actionability and idle waits.

`bench/insert-breakdown.spec.js` does this for the three clicks that make up an
insert. It is what showed insert latency at 115 blocks is browser layout, not
server render work: the round trip is flat in block count (~95 ms at every
size) while the main thread is not (0 → 52 → 776 ms).

`bench/insert-client-cost.spec.js` separates layout from morphdom: it repeats
the operation with the block list `display: none`, leaving the DOM exactly as
large but out of layout. 258 ms → 0 ms at 20 999 unchanged nodes.

`bench/tree-triggers.spec.js` reports the same split for copy, the outline
drawer and the entry-field fan-out, and asserts budgets for the first and last.

## 5. Server-side profiling

`e2e/bench/profile_op.exs` attaches `:eprof` to the LiveView process for the
duration of one operation. The operation has to be driven from a real client
while the profiler is already attached, so the two coordinate through flag
files. Start the server as a named node (see above), then in one shell:

```sh
cd e2e/e2e/playwright
BENCH_PROFILE=1 BENCH_OP=insert BENCH_ENTRY=115 pnpm playwright test \
  --config bench/playwright.bench.config.js bench/profile-op.spec.js
```

and in another, at the same time:

```sh
cd e2e/bench
BENCH_OP=insert BENCH_ENTRY=115 elixir --sname profile --cookie benchcookie profile_op.exs
```

`BENCH_OP` is `insert`, `outline` or `copy`. The report is written to
`bench/profile-<op>-<entry>.txt` and echoed. Without `BENCH_PROFILE=1` the spec
skips itself, so a plain sweep of `bench/` does not block on a flag file nobody
is going to raise.

## Gotchas

- Playwright's `actionTimeout` defaults to unlimited and the repo config doesn't
  set one, so a mistyped locator in a long-timeout spec blocks for the whole test
  timeout instead of failing. `bench/playwright.bench.config.js` sets it to 20s;
  do the same in any spec that raises its own timeout.
- `evalLV` in `e2e/e2e/playwright/utils.js` is dead — no `sandbox:eval` handler
  exists anywhere in the codebase. That's why memory is measured over
  distribution instead.
- `:eprof` lives in OTP's `tools` app, which a Mix project does not put on the
  code path — `:eprof.start/0` comes back `:undef` on the server node.
  `profile_op.exs` adds `tools-*/ebin` from the node's own `:code.root_dir/0`.
  It also redirects the report through `:eprof.log/1`, because `analyze/2`
  otherwise prints through the *server's* group leader.
- **A fixture that does not contain the thing being measured reports success.**
  None of the flat/nested modules mention `entry`, so `Block.may_read_entry?/2`
  excluded every one of them and the entry-field fan-out measured 7 KB — while
  it was in fact shipping `nil` to every block and blanking `{{ entry.title }}`
  everywhere. `/bench-entry-consumers` exists for that measurement, and the
  spec asserts the rendered output, not just the byte count. Same failure shape
  as the bench save that reported a latency for a save that never succeeded.
