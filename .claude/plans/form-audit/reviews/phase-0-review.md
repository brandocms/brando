# Phase 0 review — form logic audit (commit `2c26cb31b`)

**Date:** 2026-08-05
**Scope:** `git diff HEAD~1` — 12 `lib/` files, 10 test files
**Agents:** elixir-reviewer, liveview-architect, testing-reviewer, security-analyzer,
iron-law-judge, requirements-verifier

> **RESOLVED 2026-08-05.** BLOCKER-1, W1 and W2 fixed; a further pre-existing crash found by
> the follow-up pass (`page_vars.ex` `sequenced_subform`) fixed too. Gates after fixes:
> `mix test` **1099/0**, format clean, credo at pre-existing baseline, E2E **105/0**.
> See "Resolution" at the end. W3 and W4 deliberately left open, with reasons.

## Verdict: REQUIRES CHANGES

One confirmed BLOCKER. It is in code this phase *added*, it defeats part of the B2 fix, and the
test written to prove B2 does not exercise the shape the real code produces.

Requirements coverage is otherwise clean, so this is not a scope problem — it is a correctness
problem in one function.

---

## Requirements Coverage

Source: `.claude/plans/form-audit/plan.md`, Phase 0 (A1, A2, B1–B7). Phases 1–4 out of scope.

| Finding | Status |
|---|---|
| A1 embed→assoc on `refs` | MET — all root+child pairs converted; independent grep found no survivors |
| A2 video MatchError | MET |
| B1 persisted-ref media | MET — both halves present (params restore + FK hidden inputs) |
| B2 child diff merge | **PARTIAL** — scalar fields only; refs/vars/table_rows still replaced (see BLOCKER-1) |
| B3 cross-parent move | MET |
| B4 cast lists | MET — `@block_attrs`' three omissions independently confirmed deliberate |
| B5 conditional refs | MET with documented known gap; judged honest, not overstated |
| B6 subform `get_field` | MET |
| B7 picker select | MET — the "already correct" claim independently confirmed |

No scope creep: every changed file traces to a Phase 0 finding. Both deferred E2E checkboxes
carry explicit deferral notes rather than being dropped.

> B2 was marked MET by the requirements agent, which checked that the *described* change is
> present. The elixir agent then found the change doesn't do what it claims. Downgraded to
> PARTIAL here — a reminder that "the diff matches the plan" and "the code works" are
> different questions.

---

## BLOCKER-1 — `deep_merge_params/2` never merges refs, vars or table_rows

`lib/brando_admin/components/form/block_field/ops.ex:765-769`

`deep_merge_params/2` recurses only when **both sides are maps**. Everything else hits
`defp deep_merge_params(_old, new), do: new` — wholesale replace.

But `changes_to_params/1` emits nested relations as **lists**, not index-keyed maps
(`change_value(list)` at `ops.ex:805-809`). So for the exact fields most likely to hold
programmatic state — refs and their media FKs — the "deep" merge is a plain replace, and B2's
bug survives for them.

**Verified by probe**, two `validate` rounds on a persisted child block:

```
ROUND 1 diff: %{"refs" => [%{"id" => 12271, "image_id" => 61278}, %{"id" => 12272}]}
ROUND 2 diff: %{"refs" => [%{"id" => 12271}, %{"id" => 12272, "image_id" => 61279}]}
MERGED:       %{"refs" => [%{"id" => 12271}, %{"id" => 12272, "image_id" => 61279}]}

image_ids surviving: [nil, 61279]   (61278 lost)
```

**Failure scenario:** on a child block with two refs, pick an image on ref A, then pick an image
on ref B. Save. Ref A's image is gone. This is B1's symptom, on child blocks, reintroduced by
B2's own fix.

**Why the tests missed it:** `ops_test.exs:88-95` ("CHILD merge is deep") hand-builds
`%{"refs" => %{"0" => …, "1" => …}}` — a map shape the real code never produces. It passes
against broken behaviour. `child_diff_test.exs` drives the real path but only edits scalar
fields (`description`, `anchor`), which merge correctly.

**Fix sketch (not applied — review is read-only):** merge relation lists by matching on `"id"`
(and `"uid"` for unsaved rows), or normalise diffs to index-keyed maps before storing. Whichever
is chosen, the regression test must derive its params from a real `Ecto.Changeset` via
`Ops.block_diff_params/1` rather than hand-writing them.

---

## WARNINGs

**W1 — cross-parent move can strand a block in the UI**
`block.ex:189-228` + `block_field.ex:257-290`

`extract_child` unconditionally removes the child from `block_list`, `changesets` and
`children_forms`, *then* sends the message. The `materialize_child` failure branch added this
phase logs and returns, but `rebuild_outline_items` only reflects the canonical op store — the
source component's local render state is already gone. The block vanishes from the canvas while
still existing server-side.
Reachability is low (failure needs an unknown or root uid, which a real drag can't produce), so
this is a defensive branch that fails badly rather than a live bug. Confirmed by reading both
sides.

**W2 — newly castable FKs have no `foreign_key_constraint`**
`lib/brando/content/block.ex:69-70` (`@var_attrs`), `:298` (`ref_changeset/3`)

`video_id` and `gallery_id` now reach INSERT, but neither changeset declares
`foreign_key_constraint/2` and the columns carry real FKs. A hand-edited hidden input raises
`Ecto.ConstraintError` and takes the LiveView down — the same crash-loses-unsaved-work class as
A2, which this phase fixed. Pre-existing for `image_id`/`file_id`; newly reachable for the two
added here.

**W3 — B4 widened the `carried_var` DOM surface by six fields**
`render.ex:2060` renders a hidden input for *every* `ContentBlock.var_attrs()` entry (unsaved
vars only). Adding six fields to `@var_attrs` therefore also added six client-editable inputs.
`creator_id`/`block_id`/`page_id` were already exposed — that is C5's shape on vars and is
pre-existing — but `config_target` is newly client-selectable, letting a user point a var at
another blueprint's upload config. `ConfigTarget` resolution itself is safe (guarded
`to_existing_atom`, blueprint check, `"default"` fallback, no traversal); the risk is only
meaningful if a consuming app permits SVG uploads anywhere.

**W4 — two test-quality gaps**
- `child_diff_test.exs:88-94` depends on the `{:phoenix, :send_update, {ref, assigns}}` message
  shape, an internal LiveView contract, with no comment saying so. A LiveView upgrade would
  turn this into a confusing failure.
- `conditional_refs_test.exs` "does not carry an unsaved ref" pins a *known-unfixed* gap. The
  plan documents it; the test file doesn't say so, so it reads like desired behaviour.

**No tenant boundary exists in Brando** (no `organization_id`/`tenant_id`/`site_id` anywhere in
`lib/brando/images`), and every admin can already reach every asset through the pickers. All
security findings are therefore "authenticated admin", none cross-tenant.

---

## SUGGESTIONS

- `ops.ex:798-803` — doc comment describes the wrong clause (inverted).
- `ops.ex` `stored_block_params/3` — the `:entry_block` branch is unreachable (merge is only
  requested for `:block`).
- `page_vars.ex` — still duplicates logic now living in `SubformHelpers`.
- `ref_events_test.exs` / `ref_media_test.exs` — near-identical `socket_for` helpers; extract.
- `picker_select_test.exs` — one no-op assertion could be strengthened.
- Comment style (Law #19): `conditional_refs_test.exs:1-8` and `block.ex:290-294` mix durable
  invariants with commit-message-style bug narration.
- `render.ex` `carried_refs/1` — pre-existing duplicate-DOM-id risk if one ref name appears
  twice in `liquid_splits`. Not introduced here.

---

## Coverage caveats

Reported so the clean areas aren't over-read:

- **iron-law-judge** enumerated only 3 of the 12 changed `lib/` files. Its "no violations" is
  partial, not comprehensive.
- **liveview-architect** exhausted its turns and was resumed; it listed `subform.ex`,
  `page_vars.ex` and some `form.ex` call sites (including the image-editor save path and
  `input/file.ex` callers of `commit_selected_asset`) as **not investigated**.
- Verification gates were run before the commit, not re-run here: `mix test` 1090/0,
  `format --check-formatted` clean, credo at pre-existing baseline, E2E 105/0. The E2E suite
  passing is *not* evidence against BLOCKER-1 — no spec edits two refs on one child block.

---

## Resolution (2026-08-05)

### BLOCKER-1 — fixed, and the first attempt at the fix was itself wrong

`deep_merge_params/2` now merges relation lists **elementwise by identity** (`"id"` for
persisted rows, `"uid"` for unsaved ones).

The first version appended old-only rows so nothing could be lost. That was wrong in the mirror
direction: when a relation key is present its list is COMPLETE (`change_value/1` maps every
element and turns `:replace`/`:delete` changesets into `:drop`), so a row missing from the newer
diff was *deleted* — carrying it over would resurrect deleted refs. Caught by a test written for
adjacent behaviour. Final semantics: **the new list defines membership; the old list only
contributes field history for rows present in both.**

Tests replaced, not just added. The old "CHILD merge is deep" test asserted on a hand-built
`%{"refs" => %{"0" => …}}` map that the real code never produces — it passed against broken
behaviour and had to go. New coverage:
- `ops_test.exs` — merge by id, merge by uid, no-resurrection of dropped rows, identity-less rows
- `child_diff_test.exs` — end-to-end: two `validate` rounds picking media on two different refs
  of one child, params derived from real changesets via `Ops.block_diff_params/1`

### W1 — fixed by pre-flighting the move

`outline_reposition` now builds the child changeset **before** telling the source parent to
release it, so a failure is a clean no-op instead of a block stranded off-canvas. The
`insert_extracted_child` failure branch is now unreachable-by-construction and, if reached
anyway, reloads blocks from the (authoritative) op store rather than returning silently.
Extracted `build_child_changeset/2` so both sites share one path.

### W2 — fixed

`foreign_key_constraint/2` for all four media FKs on both `var_changeset` and `ref_changeset`,
via `validate_media_fks/1` (guarded by `__schema__(:fields)` so it serves both schemas).
Verified: without it the four new tests raise `Ecto.ConstraintError`; with it they return an
invalid changeset. Covers `image_id`/`file_id` too, which had the same pre-existing hole.

### NEW — `page_vars.ex` `sequenced_subform` KeyError crash (pre-existing, fixed)

Found by the follow-up LiveView pass. It read `socket.assigns.form.source`, but
`fieldset/field.ex:36-48` renders `PageVars` with a `field=` prop and **no `form=`** — so every
drag-reorder in advanced mode raised `KeyError` and killed the LiveView. Not introduced by
Phase 0 (the line is context in the diff, not a change), but it sat in a function this phase
refactored and is the same crash-loses-your-work class as A2. Routed through
`SubformHelpers.sequenced_subform/2`, which reads the correct binding, plus a test pinning that
subform handlers never read `:form`.

### Left open, deliberately

- **W3** (`carried_var` surface widened by six fields, `config_target` client-selectable) —
  the `creator_id`/`block_id`/`page_id` exposure underneath it is finding **C5**, which is
  Phase 1's job. Fixing half of it here would fragment that work. Phase 1 should whitelist the
  carried set, not just the recover path.
- **W4** (test-comment gaps) — cosmetic; folded into the notes above rather than churning files.
- `subform.ex` `sequenced_subform` still dispatches `put_embed`/`put_assoc` on a **client-sent**
  `event_params["embeds"]` flag rather than schema introspection. Pre-existing (0 hits in the
  Phase 0 diff), and a wrong flag raises the same way A1 did. Worth a Phase 3 item; not changed
  here because it is untouched by this phase and deserves its own test.

### Corrections to the agents' findings

Two agent claims did not survive verification, recorded so they aren't re-raised:

- `subform.ex` `sequenced_subform` "uses the `get_field` anti-pattern" — **false positive.**
  `get_change_or_field/2` prefers `get_change`, which returns changesets; the `get_field`
  fallback only fires when there is no pending change to lose. The *client-flag* half of that
  same finding is real and is listed above.
- iron-law-judge's first pass reported "no violations" while having examined only 3 of 12
  changed `lib/` files. The re-run over the other 9 found the `page_vars.ex` crash.
