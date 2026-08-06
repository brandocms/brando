# Phase 3 review — form audit (efficiency, idioms, dead code)

> **RESOLVED 2026-08-06.** Every warning and suggestion is fixed, plus four of the
> five pre-existing items. Disposition table at the foot of this file. Final gates:
> 1222 tests / 0 failures (+9), credo `2 / 118 / 152 / 12` — exactly baseline,
> `mix compile --force --warnings-as-errors` clean, and **e2e 105/105 passing**
> (full `--reset` run against rebuilt assets, including `projects.spec.js`, the
> spec whose video path blocked the `tab.ex` item).
>
> Three fixes were **mutation-verified** — the change reverted, the new test
> confirmed to fail, the change restored. That check is the whole point of W2/W3,
> so it was not taken on faith.
>
> One new defect was found *by* the new tests: `Block.get_fragment/1` used the
> BANG fetch, so a block referencing a deleted fragment raised
> `Ecto.NoResultsError` mid-render — killing the editor — and made the
> `fragment_not_found` branch unreachable. Fixed to match `get_container/1`.

**Scope:** `git diff HEAD~5` on `next` — commits `3739112a6` (galleries, Phase 2 tail) and
`22007d023` (Phase 3 E+F). 25 files, +1138 / −224.
**Agents:** elixir, liveview, testing, requirements, verification, iron-laws (6)
**Date:** 2026-08-06

## Verdict: PASS WITH WARNINGS

No blocker survived verification. Every gate passes, and the requirements check came back
17 MET / 1 PARTIAL / 0 UNMET, with the two `[ ]` items genuinely and deliberately unimplemented.

Two agents filed a BLOCKER; **neither was introduced by this diff** — I checked both against
`HEAD~5` and the code is byte-identical. They are recorded below as pre-existing. The one
finding that genuinely matters is W1: a load-bearing premise in the plan is false, and the
perf item it justified does not deliver its main win.

## Requirements Coverage

| | |
|---|---|
| MET | 17 |
| PARTIAL | 1 |
| UNMET | 0 (2 items unchecked *by design*, reasons verified) |
| UNCLEAR | 1 |

Independently re-verified, not taken from the plan's self-report:

| claim | result |
|---|---|
| `mix xref graph --sink .../input/vars.ex --label compile` lists nothing | **CONFIRMED** — re-run, empty |
| `used_input?/1` reads `form.params` and nothing else | **CONFIRMED** — `phoenix_component.ex:1753`, `used_param?(form.params, field)` |
| no top-level `.action` branch remains | **CONFIRMED** — only `var_layout.ex:76`, nested, `in [:replace, :delete]` |
| `mark_as_deleted` typo clause was dead | **CONFIRMED** — `changeset_runner.ex:45` + `mark_for_deletion/1:105-115` rewrite first |
| all seven `hero-*` classes exist in `heroicons.css` | **CONFIRMED**; surviving `svg` rule (`Form.css:602`) is scoped to `.form-tab-customs` |
| both `[ ]` items still open, reasons hold | **CONFIRMED** — `tab.ex:44-62` still `:if` with the revert recorded |
| "`container_config` is rendered by every root block" | **FALSE** — see W1 |
| "eight form-side subscribes" | **NINE** — `form.ex:3550, 3993, 4785` + six in `hooks.ex` |

## Gates

| gate | result |
|---|---|
| `mix compile --force --warnings-as-errors` | PASS — 600 files |
| `mix format --check-formatted` | PASS |
| `mix test` | PASS — 135 doctests, 1213 tests, 0 failures (+25 vs baseline 1188) |
| `mix credo --strict` | PASS — `2 / 118 / 152 / 12`, **exactly** baseline; the 2 warnings are in `asset_intent.ex`, untouched by this diff |
| `cd e2e && MIX_ENV=e2e mix compile --warnings-as-errors` | PASS |
| e2e Playwright | **PASS — 105/105 (8.9m)**, run 2026-08-06 after the fixes, with `--reset` (DB drop, migration rollback-and-forward, reseed) and rebuilt consumer assets |

---

## WARNINGS

### W1. The container/palette scoping rests on a false premise, and the perf win is not delivered `[HIGH CONFIDENCE — elixir + liveview + requirements]`

`block.ex:934-936` and `block.ex:1283-1286` both justify retaining the lists for every **root**
block with the claim that `container_config` is rendered by every root block (`render.ex:527`).
Traced independently by three agents and confirmed by hand:

- `<.container_config>` (`render.ex:520`) sits inside `def container(assigns)` (`render.ex:451`)
- `<.container>` is invoked from exactly one site: `render.ex:200`
- that site is inside `def render(%{type: :container} = assigns)` (`render.ex:197`)

So `container_config` renders **only for container blocks**. The `or belongs_to == :root`
disjunct in `block.ex:940` and in `renders_palette_options?/1` (`:1285`) is redundant.

**Cost:** on a page of N root module blocks, every one still calls `list_containers!/1` *and*
`list_palettes!/1` — two ETS reads each copying the full term onto the LiveView heap, both lists
then retained in assigns and walked by change tracking on every diff. That is exactly the cost
the item set out to remove. On a typical module-block page the change removes nothing.

The plan (`plan.md:906-908`) records the premise as a *verified* fact that shaped the design, and
both code comments state it as fact — so this misleads the next reader as well as costing the win.

**Fix:** `defp renders_palette_options?(%{type: type}), do: type == :container`, drop
`or belongs_to == :root` from the `:containers` `assign_new` at `block.ex:940`, and correct both
comments. Safe: the only readers of either assign are unreachable for non-container blocks.

### W2. `empty_params_errors_test.exs` passes against the pre-fix code `[testing]`

The file's own header says it "is what makes dropping the forced action safe". It does not.

- Four tests (`:32`, `:39`, `:50`, `:61`) never call `Form` at all — they assert
  `Phoenix.Component.used_input?/1` semantics, which the change does not touch.
- The one that does (`:76`) asserts `params == %{}` and `refute used_input?`. Both hold
  identically with the forced `Map.put(:action, :validate)` still in place.

Revert the production change and all 5 still pass. Given this project has twice shipped a test
that passed against broken code, this matters more here than it would elsewhere.

**Fix:** add the sensitive assertion — `assert socket.assigns.form.source.action == nil` at `:76`.
One line.

Note: the *change itself* is independently verified correct (see the requirements table) — this
is a test-integrity finding, not a defect in `form.ex`.

### W3. Two of the four `addon_statuses_test.exs` assertions are vacuous `[testing]`

- `:75` (`all_transformers_received? == true`) — `Page` has no transformers, so the pre-fix code
  sets it `true` too.
- `:78` snapshots `before` from the socket itself, so it passes even if `assign_addon_statuses/1`
  is deleted entirely.

Only `:74` is fix-sensitive. The transformer-state bug this file was written for — the real find
of E1 — is therefore pinned by exactly one assertion. Worth a schema that actually has a
transformer.

### W4. The rewritten resolver test no longer defends the property it existed for `[testing]`

`form_component_resolver_test.exs:26` previously asserted the Blueprint stores the `:vars`
*token* — which the change deliberately breaks. The rewrite asserts the resolved module, which
duplicates `component_resolution_test.exs:18`. The property that test was actually defending —
*no compile-time edge from Blueprint onto admin components* — now rests on a one-off `mix xref`
run recorded in a comment.

The property **does still hold** (I re-ran the xref; empty output). It is simply unguarded now,
so a future change can break it silently.

**Fix:** assert it in the test — shell out to `mix xref graph --sink ... --label compile` and
assert empty, or assert `Mix.Tasks.Xref` output, so the guarantee is enforced rather than noted.

### W5. The `:processed`-only unsubscribe rests on an invariant that is only partly verified `[liveview + elixir]`

`hooks.ex:429-431` unsubscribes from `brando:image:<id>` on `[:image, :updated]` only when the
image is `:processed`. That is correct **iff** every subscribe sits immediately before exactly one
processing round.

- Confirmed for `form.ex:3550`, `:3993`, `:4785`.
- **Unverified** for the six `deliver_asset/3` sites (`hooks.ex:536, 556, 628, 653, 688, 717`) —
  note there are nine subscribes in total, not the eight the plan claims.

If any of those six subscribes once and expects several rounds, the image **silently pins on
"Processing"** with no error surfaced. Related: `hooks.ex:399-405` unsubscribes on
`[:image, :error]` assuming it is the final Oban attempt; the producer was not located, so if an
intermediate attempt broadcasts `:error` and a later retry succeeds, that success is lost
(`{:cont, socket}`, no UI).

This is the **highest production risk in the diff** and it has no test. The plan acknowledges the
gap ("Phase 4 harness territory") — that is a reasonable deferral, but the invariant should be
confirmed by reading those six sites before merge, since it is cheap and the failure is silent.

### W6. `options_test.exs` is `async: true` while mutating global config `[testing]`

`:5` declares `async: true`; `:34` does `Application.put_env(:brando, :languages, ...)`.

No current victim — the only other test files touching `:languages` are
`option_compatibility_test.exs` (async, but uses the atom as a DSL literal, never reads the
config) and `verifier_test.exs` (`async: false`). So the suite is not racing today. It is a
landmine for the next async test that reads `Brando.config(:languages)`.

**Fix:** `async: false`. One word.

### W7. `form.ex:4946-4952`'s stated justification is wrong `[liveview]`

The comment justifies dropping the forced action by saying both error gates route through
`used_input?/1`. They do not: `has_error/2`'s second clause (`:5556-5557`) reads `field.errors`
raw, with no `used_input?` check.

The change is still correct — that clause is not reached for an empty-params form — but a reader
who checks the stated reason will find it false and may revert on that basis. Fix the comment.

---

## SUGGESTIONS

- **`Input.Options.tokens/0` is dead** — `options.ex:16-19` exports it, but all three consumers
  (`input.ex:288`, `select.ex:337`, `multi_select.ex:579`) still guard on the literal
  `[:languages, :admin_languages]`. Adding a fourth token means editing three files, and the new
  token would silently fall through the callers' passthrough arm rather than expanding. The stated
  goal ("one contract instead of three copies") is half met. Guards can't call remote functions —
  use `@option_tokens Options.tokens()` in each caller, or give `Options` a total `expand/1` with a
  passthrough clause.
- **`refresh_images: true` now costs a full `list_images/1`** (`hooks.ex:322` →
  `image_picker.ex:502`) on every `[:image, :updated]`, whether or not the picker is open — once
  per image during a bulk upload, so N images → N full-library queries. Not a regression (the
  cached `:images` assign meant the same work), but it is where the `image_picker` tradeoff
  compounds. A `picker_open?` guard would close it.
- **Scope the unsubscribe comment** — `hooks.ex:419-424` reads as unconditional. It holds for
  rounds *this form* starts, not for rounds started elsewhere (another admin re-cropping, a
  re-process from the image list). Say "locally initiated rounds".

---

## PRE-EXISTING (present in `HEAD~5`, not introduced here)

Verified byte-identical against `HEAD~5` — recorded so they are not re-derived, and because two of
them were filed as blockers.

- **P1 `palette_options` `[]` is truthy** — `render.ex:1173` is `<%= if @palette_options do %>`,
  and every non-rendering branch returns `[]`, so the `else` (hidden input, `:1182`) is
  unreachable. A container with `allow_custom_palette == false` renders a `<select>` with zero
  options instead of the hidden carrier, and an already-set `palette_id` is dropped from params on
  the next `validate_block`. **The `else -> []` is at `block.ex:1290` in `HEAD~5` too** — filed as
  a blocker, but the diff did not introduce it. Real latent bug; worth its own fix (return `nil`).
- **P2 `container_not_found` / `fragment_not_found` leave assigns unset** — `block.ex:1302`/`:1333`
  set the flag but never assign `:container`/`:palette_options`/`:fragment`, and unlike
  `module_not_found` (`render.ex:23`) there is **no matching `render/1` clause**, so rendering
  falls through to `render(%{type: :container})` which reads all three → `KeyError`, killing the
  editor LiveView and every unsaved block edit. Identical in `HEAD~5`.
- **P3 palette options go stale on container switch** — `maybe_update_container/2` (`:2141`)
  re-assigns only `:container`, while `:palette_options` is `assign_new` closing over the *first*
  container's `allow_custom_palette`/`palette_namespace`. Byte-identical in `HEAD~5`.
- **P4** `render.ex:295` — inline `style=` on the unknown-block-type debug render, against the
  repo's no-inline-styles rule.
- **P5** `block.ex:906-924` — `try/rescue` around `Changeset.get_assoc/2` as control flow.

---

## Checked and clear

Recorded so the next reviewer does not re-derive them.

- `Dsl.transform_form/1` compile-time `resolve/1` — no runtime path expects an unresolved token;
  `%Forms.Form{}`/`%Forms.Subform{}` are never constructed outside the Spark DSL; Subform
  sub-fields render through a different module that never resolved components, so skipping them
  preserves behaviour.
- `block_field.ex` `connected?/1` gating (`:657-663`, `:674-681`) — subscribe and
  `request_blocks_sync/1` gated symmetrically; `blocks_topic` still assigned on the dead render.
  No unsubscribe needed — the topic dies with the process.
- The transformer-status split (`assign_transformer_statuses/1`) and every `assign_new` addon
  conversion — no second `transformer_changesets`-shaped bug found.
- Conditional `@fragments` — no KeyError path.
- `blocks.ex` `reject_deleted/2` — recursion preserved on both branches.
- `legacy.ex` deletion — no remaining reference or `imports:` entry.
- `image_picker.ex` cache removal — rendered list is a stream; every `assign_folder_state/2` call
  site re-queries anyway.
- Iron Laws — no `style=` introduced, dead `svg path:nth-of-type(2)` rule correctly removed,
  `Options.expand/1` called in the function body before `~H` (not inline in HEEx), no
  `String.to_atom`, no sticky-JS violations.
- `gallery_test.exs:386-389` handles the `capture_log` trap correctly
  (`Logger.configure(level: :warning)` + `on_exit` restore) — the only `capture_log` in the diff.

## Agent coverage note

`phx:iron-law-judge` ran without shell access and could not read the diff directly; it reviewed
~15 of 25 files from their current state. The uncovered files (`dsl.ex`, `blocks.ex`,
`legacy.ex`, `block.ex`) were covered by the elixir and liveview agents, which did have shell
access. `phx:liveview-architect` exhausted its turn budget and was resumed to write its output.

---

## Disposition (2026-08-06)

| # | finding | disposition |
|---|---|---|
| W1 | container/palette scoping false premise | **FIXED** — `renders_palette_options?/1` is `type == :container`; `or belongs_to == :root` dropped from `block.ex:940` too; both comments corrected to name the real call chain. Mutation-verified. |
| W2 | `empty_params_errors_test.exs` passes pre-fix | **FIXED** — two new tests assert `form.source.action == nil` for `assign_refreshed_form/1` and `assign_form/1`. Mutation-verified: re-adding the forced action fails them. |
| W3 | vacuous `addon_statuses_test.exs` assertions | **FIXED** — the transformer test now models MID-collection (`all_transformers_received?: false`, one reported + one nil), which pre-fix code overwrites to `true`. The static-status test asserts against `has_trait/1` instead of a snapshot of the socket. Mutation-verified. |
| W4 | rewritten resolver test guards nothing | **FIXED** — a new test shells out to `mix xref graph --sink … --label compile` and asserts empty, with a `File.exists?` guard so a rename cannot make it pass vacuously. |
| W5 | unsubscribe invariant partly unverified | **VERIFIED, no code change needed.** All nine subscribes read and confirmed to precede a queued round. The `[:image, :error]` half is guaranteed by the producer: `ImageProcessor.handle_processing_error/4` broadcasts only when `job.attempt >= job.max_attempts`. Comment corrected (was "×5"/eight, actually ×6/nine) and now records both guarantees. |
| W6 | `options_test.exs` async + global config | **FIXED** — `async: false`, with the reason. |
| W7 | wrong justification comment in `form.ex` | **FIXED** — comment now says only `has_error/2`'s `true` clause gates on `used_input?`, and names the fallback clauses that do not. |
| S1 | `Options.tokens/0` dead, 3 hardcoded copies | **FIXED** — `expand/1` is now TOTAL (passthrough clause), so the three callers no longer name the tokens at all; `tokens/0` deleted. Its test replaced with one pinning each passthrough shape the callers branch on. Mutation-verified. |
| S2 | `refresh_images` queries when picker closed | **PARTIALLY FIXED** — a never-opened picker now skips the query entirely (safe: both open clauses call `assign_folder_state/2` themselves). Opened-then-closed is NOT covered: the drawer's closed state lives entirely client-side (`b:show_drawer` has no server counterpart), so a full guard needs new client→server plumbing — the same shape as the `tab.ex` attempt that was already reverted this phase. Recorded in the code. |
| S3 | unsubscribe comment reads as unconditional | **FIXED** — now states the subscription is scoped to locally initiated rounds, and what that gives up. |
| P1 | `palette_options` `[]` truthy → empty select | **FIXED** — non-rendering branches return `nil`; `attr` default changed `[]` → `nil`. |
| P2 | not-found branches leave assigns unset | **FIXED** — both branches now assign their keys, `fragment_not_found` is seeded in `mount/1`, and `render.ex` gained the two missing clauses mirroring `module_not_found`. |
| P2b | **NEW** — `get_fragment/1` used the bang fetch | **FIXED** — found by the new test. Raised `Ecto.NoResultsError` on a deleted fragment instead of returning nil, killing the editor and making the not-found branch unreachable. Now mirrors `get_container/1`. |
| P3 | palette options stale on container switch | **FIXED** — `maybe_update_container/2` recomputes `:palette_options` alongside `:container`. |
| P4 | inline `style=` in `render.ex` | **FIXED** — `.block-unknown-type` class added to `BlockEditor.css`. |
| P5 | `try/rescue` as control flow (`block.ex:906`) | **NOT DONE** — a behavioural refactor of untouched code, outside a review-fix pass. Still recorded above. |

New test file: `test/brando_admin/components/form/block/container_scoping_test.exs` (6 tests) —
pins the corrected scoping boundary, the `nil`-not-`[]` contract, and both not-found paths.
Nothing else would have noticed any of them drifting back.

**Before the e2e suite is run**, rebuild the consumer assets — `BlockEditor.css` changed:
`cd e2e/assets/backend && pnpm build`.
