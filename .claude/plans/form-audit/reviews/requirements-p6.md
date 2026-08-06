# Requirements Verification — Phase 6

## Requirements Coverage (from Plan file `.claude/plans/form-audit/phase-6-plan.md`)

| Finding | Status | Evidence |
|---|---|---|
| W1 — `kill_live/2` takes role from caller | MET | `test/support/live_case.ex:128` `def kill_live(view, role) when role in [:root, :child]` — no default arg; `:130` `if role == :root, do: await_proxy_exit(proxy_pid)` (child skips entirely); `live_case.ex:145-147` `await_proxy_exit/1` now `500 -> flunk(...)`, `Process.alive?/1` escape hatch gone |
| W1-call-sites — all five pass `:root` | MET | `form_recovery_test.exs:36,48,151,174,198` all `kill_live(view, :root)`; grep finds no other `kill_live(` caller in `lib/` or `test/` |
| W1-verify — two harness regression tests, watched RED | MET | `form_recovery_test.exs:64-70` root-flunk (`assert_raise ExUnit.AssertionError, ~r/did not exit within 500ms/`) and `:73-79` child-skip (`:timer.tc` < 400ms), both driven by `stub_view_with_live_proxy/0` at `:289-295`. Independently re-run green. RED-ness of the root case is structural (old code returned `:ok` on a live proxy); the `:child` mutation was not re-run here |
| W2 — comment corrected, function unchanged | MET | `test/support/live_case.ex:134-144` now states non-matching `{:EXIT, …}` stay in the mailbox **deliberately**; `receive`/`after` body unchanged apart from the timeout branch W1 owns |
| W3 — `key_available?/2` + `key_exists?/2` removed + caller inverted | MET | `lib/brando/cdn/cdn.ex:381-397` `key_available?/2` with the documented `== {:error, :not_found}` semantics and `@doc`; `grep key_exists?` across `lib test e2e guides priv CHANGELOG.md` → 0 hits; caller inverted at `lib/brando/utils.ex:1182` |
| W3-verify — three new cases, falsifiable | MET | `test/brando/utils_test.exs:513-570` (`:not_found` as-is / hit renamed / 403 renamed with suffix regex). **Mutation re-run by this reviewer**: reverting to `match?({:ok, _}, …)` produced 2 failures in `utils_test.exs`; source restored |
| W4 — `ReqOptions.merge/2` extracted, three providers use it, private helpers removed | MET | New `lib/brando/videos/uploaders/req_options.ex:1-38`; call sites `mux.ex:573`, `bunny.ex:431`, `cloudflare.ex:281-285`; `defp req_options` gone from both `mux.ex` and `bunny.ex` (diff `-` lines), Cloudflare's inline `get_config(:req_options)` read gone; `grep req_options lib/` returns only the new module |
| W4-verify — a test that fails when the merge order flips | MET | `test/brando/videos/provider_client_test.exs:162-196` colliding `headers:` entry vs the built Basic auth. **Mutation re-run by this reviewer**: flipping to `Keyword.merge(built_opts, configured \|\| [])` → 1 failure; source restored |
| S1 — "nested-safe" wording replaced | MET | `test/support/live_case.ex:116-117` now "composes across *repeated* calls"; "nested-safe" no longer present |
| S2 — `mix.exs` comment narrowed | MET | `mix.exs:82-88` drops "standing invitation for a real key…", keeps the shipped-never-evaluated + fixtures argument, and explicitly disclaims the placeholder-credential risk by naming `priv/`'s deliberate placeholders |
| S3 — `awaitBlockDebounce` comment corrected | MET | `e2e/e2e/playwright/utils.js:29-34`: "The sleep is not removed — it is narrowed to the one interval that has to be slept through… and followed by `syncLV`". `awaitBlockShip`'s comment untouched, as instructed |
| S4 — `lockdown_test.exs` `async: false` | MET | `test/brando/plugs/lockdown_test.exs:8` `use ExUnit.Case, async: false`, with a comment naming the global keys mutated |

**Summary**: 12 MET, 0 PARTIAL, 0 UNMET, 0 UNCLEAR (8/8 triaged findings W1–S4 delivered)

## Verification run

`mix test test/brando/utils_test.exs test/brando/videos/provider_client_test.exs test/brando_admin/live/form_recovery_test.exs test/brando/plugs/lockdown_test.exs` → **12 doctests, 79 tests, 0 failures**.

Two mutations were re-run independently (W3 predicate, W4 merge order); both went RED and both source files were restored (`git diff --stat` clean afterwards).

## Scope creep

None material. Two changes outside a named task, both consequential:

- `lib/brando/cdn/client.ex:29` — moduledoc pointer changed from `Brando.Videos.Uploaders.Mux.req_options/0` to `Brando.Videos.Uploaders.ReqOptions`. Required: W4 deleted the referenced function, so leaving it would have created the exact dangling-claim defect this audit closes.
- `.claude/plans/form-audit/phase-6-plan.md` and `scratchpad.md` — process documents the plan's Notes section explicitly requires.

Not verified from code (out of a requirements agent's reach): the plan's baseline table claims full `mix test` 1271+135/0, credo 284, and E2E 107/0. Only the four touched suites were run here.
