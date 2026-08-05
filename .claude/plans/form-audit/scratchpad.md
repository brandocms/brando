# Form audit — decisions and dead ends

## Retractions during the audit (important — don't re-derive these)

The first recovery pass produced three alarming findings that turned out to be **wrong**.
Recorded here so nobody rediscovers them:

1. ❌ "Non-block fields have zero recovery — the main form lacks `phx-auto-recover`."
   **Wrong.** Absence of `phx-auto-recover` means LiveView's *default* recovery, not none.
   `getFormsForRecovery()` (`deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts:2525-2603`)
   captures any form with a stable `id` + `phx-change` that isn't `phx-auto-recover="ignore"`.
   The main form (`form.ex:2048-2055`) qualifies. No `ignore` exists anywhere in the codebase.

2. ❌ "Existing block edits always silently revert on process death."
   **Wrong in general.** Block forms (`block/render.ex:372`) are unconditionally rendered with
   stable ids and `phx-change="validate_block"`, so they get default recovery too.

3. ❌ "`hooks.ex` rebuilding the changeset from DB on mount defeats recovery."
   **Backwards.** That is exactly how LV recovery is designed to work: fresh changeset from DB,
   recovered params replayed on top via `validate`.

The codebase's own comment at `form.ex:4136-4144` documents the author observing default
recovery firing — it was the best available evidence and the first pass missed it.

**Lesson for this codebase:** recovery here is deliberate and mostly correct. The failure mode
is not "no recovery plumbing", it is **state with no DOM representation**.

## The unifying insight

Everything that actually loses data in this audit shares one root cause:

> A value lives only in changeset `changes` (or component assigns), with no corresponding
> DOM input, and the next `validate` rebases on `changeset.data`.

That single sentence explains B1 (persisted ref media), B2 (child block diffs), B6 (subform
`get_field`), B7 (picker select), and C2 (drawer field edits). It also explains why recovery
can't save them: **LiveView recovery replays the DOM, and these values aren't in it.**

Worth considering as a follow-up: a lint/test that asserts every field the editor can mutate
has either DOM backing or an explicit programmatic-merge path. That would have caught B1 at
the commit that introduced it.

## B1 — how the regression got in

Commit `6ee6e93a2` ("perf: carry only ref identity once a ref is persisted") suppressed the FK
hidden inputs for persisted refs. The reasoning in the comment at `render.ex:1234-1238` is
**correct in isolation** — `cast_assoc` matches on the primary key and leaves unmentioned
fields alone, so DB-persisted values survive fine.

What it missed: values that are in `changes` but *not yet in the DB* have nothing to be left
alone. The compensating merge was apparently intended — `events.ex:781` computes `applied_block`
and `:786-788` describes exactly this purpose — but the merge was never wired up. `applied_block`
is only used at `:793` for a NotLoaded fallback.

So this is a half-implemented mechanism, not an oversight. The fix should complete it rather
than revert the perf work.

### Options considered for B1

| Option | Fixes steady state | Fixes recovery | Payload cost |
|---|---|---|---|
| (a) merge `applied_block` ref changes | ✅ | ❌ | none |
| (b) always emit the 4 FK hidden inputs | ✅ | ✅ | small (4 fields/ref) |
| revert `6ee6e93a2` wholesale | ✅ | ✅ | large — rejected |

**Chosen: (a) + (b), scoped to the four FK fields only.** (a) is the correctness fix and costs
nothing; (b) is narrowly what makes the value recoverable after process death, which is the
user's actual ask. Reverting the perf commit is rejected — mount cost is the known bottleneck
here (see the Svelte-rewrite decision memo), so re-inflating block payloads is the wrong trade.

## Deliberately not planned

- **No block editor rewrite.** Per-edit cost was re-confirmed flat (one changeset, one
  `send_update`); mount is the real cost. The Svelte rewrite was already measured and rejected.
- **No new recovery framework.** Three mechanisms exist (blocks / drawer / live preview) and the
  ordering race between them is already deliberately handled (`form.ex:4136-4144`,
  `maybe_finish_live_preview_recovery/1`). Adding a fourth abstraction would be churn.
- **Gallery dedupe deferred until after D4/D5.** Fix the bugs in both copies first, then collapse —
  deduping first would just make the bug fix harder to review.
- **`form.ex` extraction (Phase 3 G) last.** Doing it before Phase 0 would make the data-loss
  diffs unreviewable.

## Phase 0 implementation notes (2026-08-05) — what the plan got wrong

Phase 0 shipped complete (A1, A2, B1-B7). Four places where implementation contradicted the
plan, recorded so they aren't re-derived:

1. **B1's option (a) as written would not have worked.** Merging the FK onto
   `block_for_changeset` (the base struct) makes `apply_changes` look right — the UI shows the
   picked image — but produces no entry in `changeset.changes`, and `Ops.block_diff_params` →
   `changes_to_params` reads `changes`. The save silently drops it. Caught only because the
   regression test included a real `Repo.update` round-trip. **Shipped: restore the FKs through
   *params* before the cast**, so the cast emits a real change. Applies to the child clause too,
   which had the same save-path hole despite looking fine in steady state.

2. **`ops_test.exs:54` was not asserting buggy behaviour.** It uses a ROOT uid, and replace IS
   correct for roots. Merging root diffs would introduce the mirror bug: a field edited then
   reverted to its DB value emits no change, so the merge resurrects the stale value. The
   `{:update}` op now branches — replace for roots, deep-merge for children.

3. **`subform.ex`'s `add_subentry` did NOT already follow the Append Changeset pattern.** It
   dispatches assoc-vs-embed correctly on the *write* but still read with `get_field`. B6 was
   nine sites, not three (`subform.ex` ×3, `page_vars.ex` ×2, `subform_helpers.ex` ×2,
   `vars.ex`, and the shared helper). `subform.ex`'s `sequenced_subform` was genuinely safe —
   `get_change_or_field/2` prefers `get_change`, which returns changesets.

4. **The `get_field` mechanism is subtler than "discards pending input".** Measured:
   `get_field/3` *does* carry the pending value (applied structs). What's lost is the **change** —
   writing structs back yields child changesets with empty `changes`, so Ecto emits no UPDATE.

       get_field  -> put_change  =>  [{"one", %{}}]                  persists "orig1"
       get_assoc  -> put_assoc   =>  [{"one", %{value: "PENDING"}}]  persists "PENDING"

**The scratchpad's unifying insight held up, and got sharper.** Every Phase 0 data-loss bug was
the same thing: *a value living in `data` (or in assigns) rather than in `changes`*. That is the
one-line test for this codebase — not "is it in the DOM", but "will it produce a change".

Two same-class bugs were found by auditing rather than from the reports, both by asking "where
else does this exact shape appear?":
- `ref_changeset/3` cast `image_id`/`video_id`/`file_id` but not `gallery_id` (B4's sibling)
- the six extra `get_field` subform sites above (B6's siblings)

Also worth knowing: **`liquid_strip_logic` refs are only unsafe in mixed modules.** If *every*
ref is inside stripped logic, params omit `"refs"` entirely, `cast/3` skips absent keys, and
nothing is deleted. The bug needs at least one ref outside the logic and one inside.

## Open questions to settle during implementation

- B5 (refs inside `{% if %}`/`{% for %}`) — needs a repro before any fix. If confirmed it may be
  the single worst bug in the audit, since it deletes data on the *first* keystroke.
- C4 — the cross-entry sessionStorage leak was not reproduced. Add `entry_id` to the key
  regardless; it's free and strictly correct.
- D2 — mid-upload reconnect ack/retry semantics were never verified. Measure before designing.
- `polymorphic_embed`'s `cast/1` behaviour with raw changesets (`vars.ex:118`, `link.ex:69`,
  `subform_helpers.ex:18,39`). Three consistent sites suggests intentional; unverified.

## Phase 1 implementation notes (2026-08-05)

Phase 1 shipped complete (C1–C6). What the plan did not predict:

1. **A second crash, found by writing C6's test.** `var_struct_to_map/1` (`events.ex`) hand-pruned
   `Var`'s associations and the list predated the `:video` and `:gallery` relations, so both
   reached `put_assoc(:vars, …)` as `%NotLoaded{}` → `UndefinedFunctionError` on `__changeset__/0`
   → dead editor LiveView. Reachable from the "reset var" / "reset vars" buttons on **any** module
   with vars. Same omission shape as B4, and the same fix shape: derive the list from
   `__schema__(:associations)` so the next relation cannot reintroduce it.
   *Lesson: a hand-maintained list of schema fields is a bug waiting for the next migration.
   B4 and this are the same defect twice — grep for the rest.*

2. **C4 could not be reproduced, and the static read says why.** The snapshot is only written by
   `disconnected()` and only read by `reconnected()`; a hook that *mounts* after a reconnect runs
   `mounted()`, which is a deliberate no-op. So the cross-entry leak needs the same hook element
   to survive an entry change — a `push_patch` within one LiveView, not the `push_navigate` used
   between entries. Fix shipped anyway (entry-scoped key), as the plan directed. **Recorded as
   unconfirmed, not as absent** — this is a reading of the lifecycle, not a runtime probe.

3. **C3's fix needed a server change the plan did not mention.** "Move `removeItem` after a
   server-confirmed recovery" only works if the server actually replies — all three
   `recover_blocks` paths had to move from `{:noreply, …}` to `{:reply, …}`. (Verified a
   LiveComponent may reply: `channel.ex:804`.)

4. **C5 was two whitelists, not one.** The grafted child subtree from C1 initially bypassed the
   sanitizer entirely — worth remembering that adding a new params path (C1) silently widened the
   attack surface a sibling finding (C5) was closing, *in the same phase*. Also picked up W3 from
   the Phase 0 review here as planned: `creator_id` is now derived in `var_changeset/3,4` from
   the user argument that was being threaded in and ignored, which closes creator spoofing on
   every path rather than one DOM surface at a time.

5. **Two plan line references had drifted** despite the mechanical rebase onto `683ef6944`:
   C2's "silent no-op at `form.ex:4102-4104`" is now the paramless `save_video` clause (the real
   one is the `_ ->` fallthrough in `recover_drawer_state`), and C5's `block_field.ex:1175` is
   `:1251`. The rebase note said the shift was mechanical and un-re-audited; that was accurate,
   and checking each reference before acting on it was worth the minutes.

6. **AGENTS.md violation fixed in passing:** `carried_var/1` called `ContentBlock.var_attrs()`
   directly inside HEEx. LiveView cannot change-track a function call, so the whole comprehension
   was re-evaluated and re-sent on every diff. Now a compile-time module attribute assigned into
   the template. Pre-existing, not introduced by this phase — but it was the line being edited.

**The unifying insight still holds, in its Phase 0 sharpened form** ("will it produce a change?").
C2 is the newest instance: replaying drawer edits via `change/2` would have put them in `data`
and never emitted SQL — the test asserts they land in `changes`, not merely that they render.

### [13:01] WARN: liveview-architect stopped mid-investigation without writing reviews/liveview.md (turn exhaustion, ~20 tool uses). Resuming the agent to have it write findings; if that fails, the LiveView angle of this review is UNCOVERED and must not be reported as clean.

## Phase 2 implementation notes (2026-08-05)

Phase 2 shipped D1, D3–D7 and D-dup. D2 is blocked on a measurement the user runs
(`d2-repro.md`). What the plan did not predict:

1. **The dominant defect class in this phase was not the one the audit named.** Phase 0/1's
   unifying insight was "a value in `data` rather than `changes`". Phase 2's is **"library
   clients raise, they don't only return"** — three instances, each capable of killing a
   long-lived process holding unsaved work:
   - `Mux.api_request/3` raises `RuntimeError` on missing credentials → dead entry form
   - `Brando.CDN.get_s3_config/2` raises on a missing CDN config, reached via
     `finalize_direct/3` → dead **sticky** manager, taking every other in-flight upload
   - `ConfigTarget.serialize/1` raises on a non-blueprint schema or empty field segment

   All three were found by *writing the test*, not by reading. Same class as A2. **There is
   almost certainly more of this — a deliberate sweep is warranted.**

2. **`nil` is an atom.** `ConfigTarget.serialize({"video", Schema, nil})` happily produced
   `"video:Schema:"` because `segment!/2`'s `is_atom` clause accepted it. Any guard of the
   form "is this a valid segment" needs an explicit nil check, not a type check.

3. **A schema's form NAME and its blueprint `singular` are not the same thing.**
   `Phoenix.Naming.resource_name(Brando.MigrationTest.ProjectUpdate1)` is `"project_update1"`;
   its `__naming__().singular` is `"project"`. They coincide for real schemas, which is why the
   old `"#{singular}_form"` derivation looked correct. **`@form_id`, threaded down by
   `Form.input/1`, is the only authoritative source** — it is the id the live view actually
   mounted the component under. Discovered by a test failing on the *right* thing for the
   wrong reason.

4. **`assign_new` was load-bearing, not lazy (D5).** The obvious fix — swap it for `assign` so
   the gallery tracks the changeset — would have blanked every thumbnail, because the objects
   only carry a preloaded `:image`/`:video` while they come straight from the DB and
   `slim_gallery_object/1` strips them on the way back through `put_assoc`. The cache existed
   for a reason; the fix had to keep the reason (`merge_loaded_media/2`) and drop only the
   staleness. *Lesson: before removing a cache, work out what it was caching.*

5. **A workaround comment can be load-bearing for the wrong reason (D7).** The comment saying
   `editing_image?` "must be cleared or the main save is rejected" was true, but the real bug
   was that `reset_image_field`/`reset_file_field` closed their drawer *without* clearing it —
   `reset_video_field` always did. The asymmetry is what made the workaround look deliberate.
   *When a comment justifies something that looks wrong, check whether it is compensating for a
   third thing.*

6. **Three of the plan's own findings were wrong as written**, all in the same direction — the
   audit inferred a symmetry that was not there. D6 assumed `video_block` knew the image id
   (its `cover_image` embed has no id field at all); D-dup assumed `gallery_objects.ex` shared
   D4's bug (it only ever mounts where the hardcoded id is correct); D7's "every drawer close"
   was already guarded. In each case the *finding* was still real, just not where or why the
   plan said. **Check the premise before the fix — it cost minutes each time and would have
   cost hours as a wrong fix.**

7. **Deduping found a bug on its own (D-dup).** The two gallery thumbnails were byte-identical
   markup with *different* lookups: one guarded empty strings, the other did not, so
   `to_string(nil) == to_string("")` could render a different object's thumbnail. This is the
   concrete cost the D-dup finding was asserting in the abstract.

8. **An audit finding can smuggle in a guarantee the system never made.** D2 asked for an ACK,
   a bounded retry and an editor-visible error on delivery failure — which reads as reasonable
   until you notice `docs/UPLOADER.md:176-178` already declares delivery *best-effort and
   orphan-safe*: "Navigate away mid-upload → the upload still finishes, the asset still exists,
   we just skip the (now-gone) UI update." There is nothing to retry to when no one is
   listening, and no editor to show an error in. I carried "delivery can be missed" as an open
   gap for several messages; the user pushed back with "makes sense that it doesn't land in the
   form if the form isn't there" and was right. **The real defect was narrower: a form that WAS
   mounted and WAS the right form still missed its delivery, because the topic changed
   underneath it.** *Check a finding against the documented contract before treating its framing
   as the spec.*

### Deliberately not done, and why
- **The `video_block` cover-image defect** (D6 note): `@picture_fields_to_take` ∩ `Image` ∩
  `PictureBlock.Data` is `[:formats, :fetchpriority]`, so picking a cover image stores nothing
  usable. That is a schema decision (give `Data` an FK, or move the cover to a ref), not a
  Phase 2 line edit.
- **`file_picker`/`video_picker` upload-root helpers.** Share a shape, not an implementation;
  unifying means changing video's config *resolution* path, which deserves its own check.
- **A successful direct-upload finalize test.** Needs the S3 mock boundary that is Phase 4's
  job. The tests pin that the completion now *reaches* finalize, not that finalize succeeds.
