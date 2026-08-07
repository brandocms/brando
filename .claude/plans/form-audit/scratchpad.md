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

## [22:5x] HANDOFF — Phase 2 e2e: one open failure, one revert

### State

Committed on `next`, unit suite **1194 / 0**, format clean, credo at baseline:
`cfb3639fc` (D3–D7, D-dup) · `d852ec7ef` (D1) · `a3f8a7d35` (docs) ·
`3694b9769` (review B1/B2/W1/W7) · `f303564f5` (review W2–W6/W8) ·
`3f11b8e3a` (review disposition) · `6da10b844` (D2 revert)

**e2e: 104 passed / 1 failed.**

### ✅ CLOSED — `tests/projects/projects.spec.js:4` (see "Phase 2 e2e resolution" at the end)

The handoff below is kept as written, because its *process note* was right and its
*three candidate call sites were all wrong*. Everything under "Narrowed candidates"
chases a lost object; nothing was ever lost. Read the resolution section instead.

### OPEN (as handed off) — `tests/projects/projects.spec.js:4 "creates project"`

Line 123: uploads **two** images to `project_gallery`
(`./fixtures/image2.jpg`, `./fixtures/image.jpg`), then expects two
`[id$="-sortable-gallery-objects"] .gallery-object img`. Only **one** renders.

**Reproduces in isolation** (`./test_e2e.sh --reset tests/projects/projects.spec.js`),
so it is not full-suite load flake.

Confusing evidence — do not skip this: it **passed in the first full run**,
which had every commit through `3f11b8e3a` including D2. It then failed in the
next two full runs and in isolation. So "D2 caused it" is ruled out, and the
run-1 pass is unexplained. Establish causation against `65e90b831` (the
pre-Phase-2 commit) BEFORE assuming it is ours — that is the step I skipped
twice today and was wrong both times.

Narrowed candidates, in order, all from this phase and all on the two-object path:
1. `Brando.Galleries.append_unique_media/2` (review B2). Dedupes by media id;
   two distinct images should both append. Verify `same_media?/2` cannot match
   two different ids — and that the delivered `new_image` map really carries
   `image_id` (gallery delivery builds it in `form.ex`'s `:gallery` clause).
2. `Brando.Galleries.merge_loaded_media/2` (D5 + review B1). Maps over the
   changeset's objects and never drops, so it should not lose one — confirm.
3. `Form.put_gallery_at/4` / `append_gallery_object/5` (D4 refactor). Two
   sequential deliveries must accumulate; check the second reads the first's
   write back out of the changeset.

Fastest discriminator: the gallery component has three writers for
`gallery_objects` and the review already flagged their ordering (B2). Log the
list length at each writer for a two-file upload.

### REVERTED — D2's client-owned delivery topic (`6da10b844`)

Broke `block-multiuser-sync.spec.js:245`. Bisected one variable per run:
full handshake → 1 failed; no `claimDeliverTopic()` → 9/9; sticky
`setAttribute` but no `pushEventTo` → 9/9. **The sticky DOM write is innocent;
the round trip is the cause.** Moving the claim to a non-rendered assign did
NOT fix it, so the re-render is not the whole story — handling *any* event on
the Form LiveComponent during its two-phase block mount (`blocks_ready?` is
deferred by `send_update_after`) disturbs block sync, mechanism unknown.

The underlying bug is real and measured (`form:a852c2d1-…` then
`form:dae79cd2-…` across two mounts; `put_intake_item/6` captures the topic at
intake and never updates it). Re-land it away from the Form mount path — most
likely the sticky `UploadManager` owning the entry→topic mapping, since it
already survives navigation and has no block tree to disturb.

Kept from D2: `data-entry-id` on the form element,
`AssetIntent.validate_deliver_topic/1` public, truncated topic logging.

### Process note

Two wrong calls today, same shape both times: I explained a failure from the
most available story instead of measuring. First "that spec is flaky" (the plan
says so — it reproduced 2/2). Then "it's the re-render" (survived one bisect,
failed the full suite, and shipped a second regression). **The bisect narrowed
the component, not the mechanism; I treated it as if it had done both.**

## Phase 2 e2e resolution (2026-08-05) — `projects.spec.js`

**Fixed.** One-line change in `Brando.Galleries`: `fresher?/2`'s timestamp comparison
went from `== :gt` to `!= :lt`, i.e. a tie now keeps the previously-loaded copy.

### What it actually was

`updated_at` is `Ecto.Schema.timestamps()`' default `:naive_datetime` — **second
precision**. Upload → Oban process → in-place refresh completes inside one second,
so the refreshed `:processed` image and the changeset's `:unprocessed` snapshot of
the same image compare **equal**. `merge_loaded_media/2` required a strict `:gt` to
prefer the cached copy, so the refresh was discarded on the next `assign_value` —
which the *second* upload's delivery triggers. `Thumb` then renders the spinner
placeholder instead of an `<img>`, so one of two objects had no `img`.

Nothing was ever lost: both objects were in the changeset, both carried loaded
media. Only the **refresh** was lost.

### Process, since the handoff's own note was about process

1. **Causation first, and it paid.** Spec passes at `65e90b831`, fails on `next`.
   Two runs, ~4 min. The handoff was right that this step had been skipped twice.
2. **My first hypothesis was wrong and the probe killed it in one run.** I read the
   `assign_new` → `merge_loaded_media` diff, saw `append_unique_media/2` skip an
   already-present object, and concluded it was dropping the delivery's loaded
   media. The probe showed both objects arriving *with* media. Cost: one e2e run,
   because I probed instead of fixing.
3. **The handoff's three candidate call sites were all wrong** — all three assume a
   lost object (`append_unique_media`, `merge_loaded_media` dropping, `put_gallery_at`
   not accumulating). The failing assertion (`.nth(1)` of `.gallery-object img`)
   reads as "an object is missing" but is equally satisfied by "an object rendered
   without an `<img>`". The post-failure DOM snapshot showed *two* figures with two
   `img`s, which is what broke the framing: the second thumbnail was late, not absent.
   *An assertion on a rendered child is not an assertion on the parent's existence.*
4. **The run-1 pass the handoff called unexplained is explained**: it is a
   second-boundary race. If the two uploads straddle a second tick, the timestamps
   differ, `:gt` holds, and the refresh survives. Nothing to do with D2.

### Lesson, in the shape the rest of this scratchpad uses

Phase 0/1's insight was *"a value in `data` rather than `changes`"*. Phase 2's was
*"library clients raise, they don't only return"*. This one is:

> **A timestamp comparison is only as good as the timestamp's precision.** Ecto's
> default `timestamps()` is second-granular, so any "is this copy newer?" test
> between two writes in the same request is a coin flip. Tie-break deliberately,
> toward whichever side is the one that actually receives updates.

Worth a grep: any other `NaiveDateTime.compare(...) == :gt` deciding between two
in-memory copies of the same row has the same latent bug.

### The duplicate-primary-key warning — fixed, and I was wrong to shelve it

I first reported `found duplicate primary keys for association/embed :gallery_objects`
as "benign, needs its own scope", on the evidence that the spec passed including its
reopen-after-save `toHaveCount(3)`. The user pushed back — correctly — that a passing
test is not a diagnosis. Tracing it through Ecto showed it was worse than noise:

- `gallery_at/3` reads the **applied** gallery, so unsaved objects sit in `data` with
  `id: nil`.
- `process_current/3` (`deps/ecto/lib/ecto/changeset/relation.ex:540`) keys `current`
  by primary key. Every nil-id object keys on `[nil]`, so all but the last are
  silently shadowed — that is what the warning reports.
- `map_changes/9` → `pop_current/2` then matches each nil-id **param** against
  whichever struct survived, and calls `Changeset.change(that_struct, params)`.
  **Image A's params were being applied on top of image B's struct.**

The rows came out right only because `slim_gallery_object/1` pins every writable
field, so the mismatched base contributed nothing to the result. That is an accident
of the param shape. Anything that ever slims a subset — or any `put_assoc` here that
does not go through `slim_gallery_object/1` — turns it into real cross-contamination.

Fix: `forget_unsaved_objects/1` in `put_gallery_at/4`. An unsaved object has no
identity to match on, so it is dropped from the base and remains the plain insert it
already is. Objects with a real id still match and still update.

Two things worth carrying forward:

1. **The other gallery writer was already safe, for the reason that explains the
   bug.** `Input.GalleryObjects` puts onto the *entry changeset*, whose `data` holds
   only persisted objects — unsaved ones live in `changes`. Only `put_gallery_at/4`
   read an applied struct back in as its base. *`get_field` moves changes into data;
   anything that then treats that data as identity is suspect.*
2. **`capture_log` asserts nothing here by default.** `config/test.exs` pins
   `config :logger, level: :error`, which drops Ecto's warning at the primary filter
   before any capture handler sees it. My first version of the log test passed against
   the *broken* code. The structural assertion is the real one; the log assertion only
   works with the level lowered for its duration.

### Process note to go with the one already in the handoff above

The handoff's own lesson was "I explained a failure from the most available story
instead of measuring". I then did the adjacent version of it: I explained an anomaly
away with the most available *reassurance* ("the test passes, so it is benign") and
filed it as out of scope. Both are the same failure — accepting a story instead of
reading the code. It cost one exchange because the user caught it.

## Phase 3 E + F implementation notes (2026-08-06)

Shipped all of E (E6 partially) and 7 of 8 in F. What the plan did not predict:

1. **`assign_new` is not always the safe direction (E1).** Two of the seven addon statuses
   could not become `assign_new`: `mount/1` seeds `has_meta?: false` so the async-load
   render has it, and `assign_new` would have pinned it to `false` for the life of the
   component; `has_alternates?` reads `entry.id`, which is nil until a create form saves.
   *Check what `mount/1` already seeded before converting anything to `assign_new`.*

2. **The real find in E1 was not the perf.** `all_transformers_received?` and
   `transformer_changesets` are STATE — `reset_transformer_changesets/1` owns them — and
   re-initialising them on every parent re-render discarded whatever a transformer had
   already reported if a diff landed mid-collection. Same shape as Phase 0's data loss,
   found by asking "is this value derived, or is it state?" while converting it.

3. **A finding can name the wrong two files (E6).** `image_picker` and `video_picker` look
   identical and are not: every one of ImagePicker's `assign_folder_state/2` call sites
   re-queries first, so its retained `:images` was pure waste; VideoPicker's
   `assign_folder_state/2` is reached from a dozen sites that do NOT reload, so its
   `:videos` is a real cache and dropping it would add queries. Same code shape, opposite
   correct action.

4. **A test can pin the thing you are about to change (E3).**
   `form_component_resolver_test.exs` asserted the Blueprint stores the `:vars` *token*.
   The property worth keeping was "no compile dependency on admin modules", which I
   verified survives (`mix xref graph --sink ... --label compile` lists nothing) before
   rewriting the assertion. *When a test fails on a deliberate change, find the property
   it was defending before you edit it.*

5. **`capture_log` asserts nothing in this suite by default** — `config/test.exs` pins
   `config :logger, level: :error`, so warnings never reach the capture handler. Already
   recorded under the gallery work; it bit twice.

### The one that did not land: `form/tab.ex`

The plan wanted the video drawer's Upload/External-URL sub-tabs switched from `:if` to a
CSS toggle, calling it "narrow blast radius: 2 fields". It is not narrow. **The two panels
bind the same field** — a hidden `video[type]` of `:upload` in one, a Vimeo/YouTube select
bound to `video[type]` in the other — so mounting both puts two inputs of that name in the
form. The spec that catches it is `projects.spec.js:290` (upload a local video, expect an
"Edit video" button).

Two attempts, both reverted:
- plain class toggle → spec fails (both attempts)
- class toggle + `<fieldset disabled>` around the inactive panel, which excludes its inputs
  from submission while keeping their DOM values → **still fails**

So the duplicate-name theory explains at most part of it, and I stopped rather than run a
third guess. Causation was established both directions before reverting. The underlying
defect (switching sub-tabs mid-edit drops an unflushed `source_url`) is real and now
documented in a comment above `tab_content/1`, together with the failing spec line.

*Process note, and it is the same one as the gallery work: I formed a mechanism from
reading, built a fix on it, and only the e2e run told me the mechanism was incomplete. The
difference this time is that I stopped after the second attempt and reverted, instead of
shipping a third theory.*

[10:14] Phase 3 review started — 6 agents (elixir, liveview, testing, requirements, verification, iron-laws) on `git diff HEAD~5`
[10:17] WARN: phx:liveview-architect did not write .claude/plans/form-audit/reviews/liveview-p3.md — turn exhaustion, return message empty. Resuming agent to dump findings.
[10:21] Phase 3 review complete — PASS WITH WARNINGS. 0 blockers (2 filed, both disproved as pre-existing vs HEAD~5), 7 warnings, 3 suggestions, 5 pre-existing. Written to reviews/phase-3-review.md

## Phase 3 review fixes (2026-08-06)

All 7 warnings, 3 suggestions and 4 of 5 pre-existing items fixed. Three things
worth carrying forward:

1. **Two agents' BLOCKERs were not regressions.** Both filed against `block.ex`
   `palette_options`. Checking the same lines in `HEAD~5` showed them byte-identical
   — real latent bugs, but not this diff's. *A finding's severity depends on when the
   code arrived, and the agent that reads only the current tree cannot tell you.*
   Fixed them anyway, labelled pre-existing.

2. **Mutation-verify a test written to catch a revert.** W2/W3 were both "this test
   passes against the broken code". Writing a better assertion and watching it go
   green proves nothing — it has to be watched going RED. Reverted each fix, confirmed
   the failure, restored. `assert action == nil` caught it; so did modelling the
   transformer collection as *partial* (`all_transformers_received?: false`), because
   `Page` has no transformers and any assertion of `true` is satisfied by the bug.

3. **The new test found a defect the review missed.** Writing coverage for the
   `fragment_not_found` branch showed it is unreachable: `get_fragment/1` used
   `get_fragment!`, so a deleted fragment raised `Ecto.NoResultsError` mid-render
   instead of returning nil — editor down, unsaved edits gone. `get_container/1` next
   to it already used the non-raising fetch. *Two functions written to the same
   contract, one bang apart; the test for the branch is what exposed it.*

Not done: `block.ex:906` `try/rescue` as control flow (pre-existing, behavioural
refactor). S2's picker guard is partial — opened-then-closed needs a server-side
close signal that does not exist, and inventing one is the `tab.ex` trap again.

**e2e (2026-08-06, after the review fixes):** 105/105 passing, 8.9m, full `--reset`
(DB drop → migration rollback-to-baseline → forward → reseed) against rebuilt
consumer assets. Includes `projects.spec.js`, the spec that blocked the `tab.ex`
item — so the two new `render/1` clauses, the `nil`-not-`[]` palette contract and
the non-raising `get_fragment/1` all clear the real browser path.

## Phase 4 implementation notes (2026-08-06)

Phase 4 shipped complete — all 7 items. What the plan did not predict:

1. **Three of seven items were wrong as written, and all three in the same direction:
   they asked for a guarantee the system does not make.** This is now the audit's most
   repeated failure mode — D2 asked for a delivery ACK the contract forbids, D6 assumed
   `video_block` knew an image id, and now:
   - "verify uploaded rows are cleaned up on a failed or reset save" — they are not,
     deliberately (`UPLOADER.md:529`, and `research/03-uploads.md:88` had already written
     it down as an *accepted-by-design orphan*). The research report contradicted the plan
     item derived from it.
   - "positive sessionStorage-recovery assertion via hard `page.reload()`" — structurally
     impossible: capture is in `disconnected()`, replay in `reconnected()`, and `mounted()`
     is an explicit no-op. A reload runs neither.
   - "a behaviour + Mox boundary for the S3/Mux/Bunny clients" — one seam for two different
     problems. See 3 below.
   *Read the research the item came from before implementing the item.*

2. **The harness found a live data-loss bug on its first real assertion, and it is the
   audit's own subject.** `Form.handle_event("validate", …)` assigned the recomputed form
   inside the `[^singular | rest]` branch of its `_target` case. Form recovery has no
   originating element, so `pushFormRecovery` names **the first non-hidden input in the
   form** (`view.ts:2450`) — which on the entry form is the `image_editor_upload` file input
   two elements in (`form.ex:2105`), not an entry field. `_target: ["image_editor_upload"]`
   fell to the `[_]` clause, so every recovered value was cast and then dropped.
   This *sharpens* the scratchpad's retraction #1 rather than reversing it: default recovery
   does fire for plain fields, exactly as recorded — the handler discarded the result.
   **Nothing short of mounting the form could see this.** Every prior form test drove
   `handle_event/3` directly and therefore chose its own `_target`.
   *Lesson: a handler that branches on `_target` sees something on recovery that it never
   sees while the user types.*

3. **Two seams, not one, and the shape of the seam matters more than having one.**
   S3 got a behaviour (`Brando.CDN.Client`) because ExAws has no test transport and the calls
   are semantic. Mux/Bunny/Cloudflare got `Req.Test` because they speak HTTP and **a behaviour
   mock can only assert *that* a client was called, when the bugs these clients have are in
   the request they build** — the auth header, the library path. Cloudflare already had a
   `:req_options` seam; the other two just needed the same line.
   And presigning was pulled back *out* of the behaviour after four existing tests failed:
   `ExAws.S3.presigned_url/5` is an HMAC over local credentials, not a network call, and those
   tests assert the real signature's query parameters. *A seam belongs where the process
   boundary is, not where the module boundary is.*

4. **The test fixtures under-specify constraints that shipped migrations specify — twice in
   one session.** Seven asset FKs were bare `references(:images)`/`references(:files)` where
   every app gets `on_delete: :nilify_all` from `brando_80`/`brando_92`; `content_blocks.uid`
   had no unique index where apps get one from `brando_123`. Consequences were real: purging a
   soft-deleted image that a page referenced raised `foreign_key_violation` and wedged
   `clean_up_soft_deletions/0` for every schema after `Image`, and two roots could share a uid.
   Both aligned in dated migrations (the monolithic file is the original schema; it is
   symlinked into e2e, so both DBs get them).
   *Lesson, and it generalises past this repo: a fixture that under-specifies a constraint makes
   every test written on top of it assert behaviour production does not have. Check the shipped
   migration before trusting the test schema.*

5. **`uid` was declared `required: true` and never enforced.** Neither `block_changeset/3` nor
   `recursive_block_changeset/3` validated it, so a root saved with `uid: nil`. The op store
   keys on uid, the block component's DOM id is `block-<uid>`, and recovery keys on
   `entry_block_form-<uid>` — C6 fixed one way of *producing* a nil uid; this closes the source.
   Same shape as B4 and the `var_struct_to_map/1` crash: **a declared contract that the cast
   path does not implement.** Worth a sweep for other `required: true` attributes whose schema
   uses a hand-rolled changeset.

6. **Block recovery does not fire on a real connection loss — measured, not inferred.**
   `disconnected()` fires and the snapshot is written correctly. But when the network returns
   LiveView cannot rejoin the lost view and does a **full page reload**, so the hook runs
   `mounted()` (the no-op) and the snapshot is never read. Recovery covers
   `liveSocket.disconnect()` → `connect()`, which only a test or the dev console does.
   **The obvious patch is wrong**: recovering in `mounted()` would replay one abandoned create
   form's blocks into the next, because every unsaved entry shares the `new` bucket (C4) — the
   "stale sessionStorage" spec forbids exactly that. A real fix needs an identity that survives
   a reload without colliding across create forms. Left asserted-as-is so a future fix flips
   the test. *This is the third time a "reasonable line edit" turned out to be a design change
   (`tab.ex`, D2's topic, now this) — and the second time the e2e run was the thing that said so.*

7. **`Application.put_env(key, nil)` is not the same as absent.** A config-restore helper stored
   `nil`, which beats the `[]` default in `Application.get_env(:brando, __MODULE__, [])`, so
   `Keyword.get(nil, …)` raised — breaking a D3 assertion in a *different file*, reproducibly
   but only when both ran. Restore with `fetch_env/2` + `delete_env/2`.

### Deliberately not done, and why
- **Recovery on `mounted()`** (6 above) — needs a per-form identity, not a line edit.
- **The other 128 `waitForTimeout` calls.** The item named block-recovery and multiuser-sync;
  all 19 in those two are gone. What remains fixed there is only the app's own two client-side
  timers (`phx-debounce` 300ms, `SHIP_SETTLE_MS` 400ms), now named next to the hook they mirror
  and each followed by an event-driven `syncLV`.
- **A successful *video* provider finalize.** The provider tests stub the request the client
  builds; the webhook-driven completion path is still uncovered.

[13:14] WARN: phx:elixir-reviewer hit its turn limit and wrote a PARTIAL elixir-p4.md
(ended "(continued)"). Resumed via SendMessage to complete items 1-4 (cdn/client.ex
dispatch completeness, validate_required(:uid) flows, migration reversibility,
upload_manager form id). Partial content was retained, not discarded.

## Phase 5 implementation notes (2026-08-06)

Phase 5 shipped complete — all 22 tasks, closing all 15 triage items from the
Phase 4 review. Final gates: `mix test` **1265 / 0** (1257 + 8 new), credo
**284** (unchanged), format clean, compile clean, e2e **107 / 0** on `--reset`
against rebuilt consumer assets.

### 1. The sequencing decision paid, and it is measurable

5A first was the plan's load-bearing call, and the throwaway wrote it down in
one run: mount → `kill_live` → remount → kill the second view. **It PASSED
against the leak and FAILED with the fix.** That is the whole argument for the
ordering — every mutation-verification in 5B and 5C is read off this
instrument, and before the fix the instrument under-reported crashes for the
rest of the test process.

`flush_exits/0` was the second half. It drained *every* `{:EXIT, _, _}` for
50 ms; it now drains only `view.proxy`'s pid. The proxy pid is not the view pid
(`%View{proxy: {ref, topic, proxy_pid}}`), and killing a **root** view stops its
proxy (`client_proxy.ex:542-545`) while a **child** shares the root's proxy,
which stays alive — so "no exit arrived and the proxy is alive" is correct, not
a timeout.

### 2. The pre-existing test stayed green, exactly as predicted

W1's mutation-verify is the one worth remembering. Reverting the 404
translation left `direct_finalize_test.exs`'s `:not_found` test **passing** —
because it stubs `Client.Mock`, and the mock was the only thing in the system
ever producing the contract. The branch was dead in production and green in CI.
The new coverage drives the real `Client.ExAws` through the real ExAws response
pipeline with only the socket replaced (`http_client:` + `http_opts:` in the
config keyword list), which is what can actually go red.

*Generalisation: when a behaviour has one real implementation and one mock, a
test that only ever meets the mock proves the mock, not the contract.*

### 3. Three findings were wrong-as-written again — and this time in a new way

The audit's most repeated failure mode has been "the item asks for a guarantee
the system does not make". Phase 5 added a variant: **the item names a fix whose
premise is false, and the check is the deliverable.**

- **S1 (`uid` `null: false`).** The plan said "check the shipped consumer
  migrations first", and the check said *don't do it*: `brando_103` ships
  `add :uid, :text` and the only thing production adds is `brando_123`'s unique
  index. Tightening the fixture would have made every test on it assert
  behaviour real apps do not have — Phase 4's fixture-drift lesson pointed the
  other way. Recorded in the migration so it is not re-litigated.
  (`content_refs.uid` IS `null: false`, via `brando_137`, and the fixture
  already matches. The asymmetry is production's.)
- **S5 (suite stdout noise).** The plan said "find the `IO.inspect`/`dbg`".
  There is none. It is a `Logger.error` in `error_translator.ex` that
  `inspect`s an entire `Forms.Form` — tabs → fieldsets → inputs, >100 lines per
  occurrence. Also **not e2e-only**: it fires four times in the unit suite.
  Replaced with the form name + `Forms.list_fields/1`, which is what you
  actually compare the missing key against. Unit-suite output **579 → 89 lines**.
- **The e2e baseline of 108.** There are 107 tests, and Phase 5 added none.
  The number was in the plan without a run behind it; the last recorded run in
  this scratchpad was 105/105. *A baseline nobody measured is not a baseline.*

### 4. A mutation found a weak assertion inside the fix I was writing

Dropping `required: true` from `Page.uri` reddened both rewritten "invalid
entry" tests — but the error list came back `[:language, :status]`, meaning the
insert had been failing for reasons the test never named and `{:error, _}` would
have matched regardless. Tightened to `assert Keyword.keys(errors) == [:uri]`
with `language`/`status` supplied.

*The mutation is not only a check on the fix; it prints the actual failure and
that tells you whether your assertion was aimed at the right thing.*

### 5. W4 was four sites in the plan and eight in the tree

The named twins (`direct_finalize`, `utils_test`, `uploads_test`, `html_test`)
plus `lockdown_test.exs` (five tests, **no restore at all**, "restoring"
`:lockdown` to `false` and `:lockdown_until` to literal `nil` — neither is the
absent key they started from, and neither runs if an assertion fails first) and
three copies of a local `restore_env/2,3` helper. All now go through
`Brando.Test.Support.put_test_env/2`; the three duplicates are gone.

`html_test.exs` was the worst of them: a bare `put_env(:brando, Brando.Villain,
parser: …)` with no restore, which drops `extra_blocks` (`config/test.exs:48-49`
sets both keys) for every test that runs after it.

### 6. S4 — verified rather than assumed

Dropping `config` and `test` from `mix.exs`'s `files:` looked risky because
`elixirc_paths(:test)` returns `["lib", "test/support"]`. It is not: Mix compiles
dependencies in `:prod`, so that clause never fires for a consumer. Confirmed
empirically — `e2e/_build/test/lib/brando/ebin/` contains no
`Elixir.Brando.ConnCase.beam`. Both directories were shipped, never evaluated,
and full of placeholder credentials.

### Deliberately not done, and why
- **The install/upgrade migration gap.** `brando.install` stops at `brando_115`
  (123 files) while `brando.upgrade` has 157 — so a freshly installed app never
  gets `brando_123`'s unique index, among ~38 others. Found while checking S1.
  Real, pre-existing, and a much bigger job than a Phase 5 line edit.
- **`selected_option/2` with several options selected in a `multiple` select.**
  Still returns the first only; correct handling needs `name[]` array encoding.
  The plan scoped W6 to the single-select fallback and that is what shipped.
- **`lockdown_test.exs` is `async: true` while mutating global app env.**
  `put_test_env/2` makes the restore correct, but the concurrency is still
  wrong in principle. No other file reads `:lockdown`, so it does not bite.

## Phase 5 review (2026-08-06)

Diff base `HEAD~6` (5ed8aa885 = Phase 4 docs commit). 29 files, 894 insertions.
Panel: elixir, testing, security, iron-laws, verification, requirements —
6 agents, one pass each. Requirements source: `phase-5-plan.md`.

**Result: PASS WITH WARNINGS.** 0 blockers. Requirements 18 MET / 0 UNMET / 1
PARTIAL / 2 UNCLEAR — the PARTIAL and UNCLEAR are all "RED/GREEN evidence is not
visible in a diff snapshot", which §2–4 above record. Gates re-run by the panel:
1265 tests + 135 doctests / 0, credo 284, compile + format clean.

Findings in `reviews/phase-5-review.md`. The one that matters:
`await_proxy_exit/1` returns `:ok` on timeout whenever the proxy is alive, so a
hung **root** proxy is indistinguishable from the benign **child** case — and no
test exercises the child branch it exists for. Same shape as the `trap_exit` leak
5A was written to remove.

Two corrections to claims recorded above:
- Unit-suite stdout measured **76** lines, not 89. Better than claimed; the 89
  was not measured either.
- The security agent's open item ("did a real key ever ship in `config/test.exs`?")
  is **closed**: across all 84 commits touching the file, the only real-looking
  value is a Guardian JWT `secret_key` for issuer `BrandoTesting`, added
  2016-11-05 (`3054445f7`), removed 2018-04-19 (`ebbebc006`). Nothing to rotate.

### Phase 5 triage — 8 approved, 0 skipped, 0 deferred
`reviews/phase-5-triage.md`. Two decisions worth carrying:
- **W1:** `kill_live/2` takes `:root | :child` from the caller; flunk on timeout
  in both. Inference between "child proxy shared" and "root proxy hung" is
  removed rather than tested around.
- **W3 (`key_exists?`):** fail **closed** — only `{:error, :not_found}` means
  absent. Accepted consequence: a transiently-erroring bucket now blocks an
  upload that used to proceed. A blocked upload is recoverable; an overwritten
  live asset is not. This is production behaviour, pre-existing, and only
  expressible because 5B's W1 introduced the `:not_found` contract.

## Phase 6 plan (2026-08-06)

`phase-6-plan.md` — 12 tasks, 4 phases, all 8 triaged findings mapped. No
research agents: the review was the research.

**Reading the code to plan the fixes re-shaped three of the eight findings.**
Recorded in the plan rather than folded in silently:

1. **W3's accepted consequence was false.** `key_exists?/2` has one caller
   (`utils.ex:1182`) whose `true` branch calls `unique_filename/1` — it
   *renames*, it does not block. Failing closed costs an occasional
   unnecessary rename, not a blocked upload. The trade recorded in the triage
   was worse than the real one.
2. **W2 is a comment fix.** Leaving unrelated `{:EXIT, …}` queued is correct —
   swallowing them is exactly what the old `flush_exits/0` did wrong. Only the
   sentence claiming the function "drains" them is inaccurate.
3. **S3 is narrower than the finding.** `utils.js` never calls the sending-side
   helpers event-driven; it disclaims them and reserves the term for the
   retrying `expect`. The loose claim is `awaitBlockDebounce`'s "Replaces a flat
   waitForTimeout(600)", which reads as removing a sleep it actually renames.

*Generalisation, and the third time this audit has hit it: an agent finding is a
hypothesis with a file:line attached. Two of these three would have shipped as
written — one of them buying a production behaviour trade that was never on the
table.*

Design calls worth keeping:
- **W1 `:child` skips the proxy wait entirely** rather than waiting 500 ms then
  deciding. Root stops its proxy; a child shares the root's, so there is nothing
  in flight to await. Kills the race and a pointless half-second. No default arg
  — a default reintroduces the implicitness the fix removes.
- **W4 is scoped to the merge line, not `api_request/3`.** The three bodies
  genuinely differ (Basic / AccessKey / Bearer, different URL construction,
  arity 3 vs 4). Only `Keyword.merge(get_config(:req_options) || [], built)` is
  byte-identical, and that is what drifted.

### Found while planning, out of scope
The three uploaders disagree on missing-credential behaviour: Mux and Bunny
**raise**, Cloudflare returns `{:error, :not_configured}`. A caller cannot
handle both with one branch. Pre-existing; no finding asked for it.

## Phase 6 implementation notes (2026-08-06)

Phase 6 shipped complete — all 12 tasks, closing all 8 triaged findings. Gates:
`mix test` **1271 + 135 doctests / 0** (+6 new), credo **284** (unchanged),
format and compile clean, unit-suite stdout **76 lines** (exactly the baseline),
e2e **107 / 0** on a full `--reset` (8.9m). Every baseline held; nothing moved
that needed explaining.

The plan's three re-shaped findings all held up against the code. What the plan
did *not* predict:

### 1. W4-verify's warning was the finding

The plan said a green run on `provider_client_test.exs` "is not sufficient; the
RED is". It was right, and stronger than it knew: **all four pre-existing tests
passed with the merge order flipped.** The reason is worth keeping — the tests
install their transport stub *through* `:req_options` (`plug: {Req.Test, name}`),
and `plug:` collides with nothing the providers build (`method`, `url`,
`headers`, `json`). With no key overlap, `Keyword.merge/2` is order-insensitive,
so the suite could not see the direction of the very line it was meant to cover.

The extraction had therefore moved an untested defect, exactly as the plan
feared. The new test makes the collision deliberate: a `:req_options` entry
carrying its own `authorization` header. Flipped, the stub sees
`hijacked:hijacked`; correct, it sees `id:secret` — which is the concrete form
of the rule's own comment, *"a config seam that can unset credentials is a
config seam that will."*

*Generalisation: a seam used only for injection is not exercised by injection.
If the test harness reaches the code through the same option it is testing, the
option's semantics are invisible to it.*

### 2. W1-verify needed two mutations, and the second one is the branch nobody had

The Phase 5 review's actual complaint was two-part: `await_proxy_exit/1` cannot
tell a hung root from a healthy child, **and no test exercises the child branch
it exists for**. Only mutating the `flunk` covers the first half. Mutating
`if role == :root` to `if role in [:root, :child]` covers the second, and it
went RED at 500ms — which is the pointless half-second the plan predicted the
`:child` path would otherwise spend.

Both tests are kept, on the 5A precedent. They need a stub view, not a real one:
`kill_live/2` reads only `.pid` and `.proxy`, so a plain map with a spawned
never-dying proxy is the whole fixture.

One wart worth knowing: `kill_live/2` flunks *before* restoring `trap_exit`.
That is harmless in real use — a flunk ends the test process and the flag with
it — but a test that deliberately catches the flunk has to put the flag back
itself. `restore_trap_exit/0` does that, with the reason next to it.

### 3. The plan's three corrections were all confirmed against the tree

Recorded because the plan asked for the check to be the deliverable:

- **W3.** `key_exists?/2` had exactly one caller, no `@doc`, and no reference in
  `guides/`, `CHANGELOG.md` or `priv/` — grep confirms. The `true` branch
  renames; nothing is blocked. Removing it outright was as low-risk as claimed.
- **W1 call sites.** All five kill views obtained from `live_form/3`, which is
  `Phoenix.LiveViewTest.live/2` — root mounts, so `:root` at all five.
- **S2.** `priv/`'s credential-shaped placeholders re-verified before writing
  the replacement comment: `deployment.cfg:8` (`DB_PASS = prod_database_password`),
  `.envrc.prod:3` (`BRANDO_SECRET_KEY_BASE`), `fabfile.py`'s `SSH_PASS`. The
  general secrets argument really does contradict what `priv/` must ship.

### 4. `nil` is still not the same as absent — third time in this audit

`ReqOptions.merge/2` keeps `Keyword.get(:req_options) || []` rather than
`Keyword.get(:req_options, [])`. The default only covers an *absent* key;
Phase 4 note 7 and `provider_client_test.exs`'s own `with_config/2` comment both
record a stored `nil` beating a default and raising downstream. The `|| []` is
load-bearing, not noise.

### Deliberately not done, and why
- **Collapsing `api_request/3` itself.** Scoped out by the plan and the scoping
  holds: Basic vs `AccessKey` vs Bearer, two URL shapes, arity 3 vs 4, and two
  different answers to missing credentials.
- **The missing-credential disagreement** (Mux/Bunny raise, Cloudflare returns
  `{:error, :not_configured}`). Still open, still pre-existing, still not asked
  for by any finding.
- **Cloudflare has no `provider_client_test.exs` coverage at all.** Noticed while
  adding the precedence test, which is Mux-only. The extracted helper is shared,
  so the rule is covered once — but Cloudflare's request construction is not
  covered anywhere.

---

# Phase 7 planning — 2026-08-06

Plan: `.claude/plans/form-audit/phase-7-plan.md`. From
`reviews/phase-6-triage.md` (14 approved, 0 skipped, 0 deferred). No research
agents — the review findings are the research.

## What re-reading the code changed about four findings

### 1. B1's real child already exists
`lib/brando_admin/components/layouts/live.html.heex:2-4` renders three sticky
children (`brando-chrome`, `brando-upload-manager-lv`, nav) on every admin page.
So `live_form/2` + `find_live_child(view, "brando-chrome")` is a real nested
child with no new fixture. B1-prove is ~10 lines, not a fixture project.

### 2. The reading was re-done, agrees, and changes nothing about the task
Against `phoenix_live_view 1.2.8` (`mix.lock:87`), in `client_proxy.ex`:
`put_view/3` monitors (`:849`) and registers in `state.pids` (`:856`) for every
view with no root/child distinction; children reach it at `:1001`;
`{:DOWN,…}` → `fetch_view_by_pid` → `{:stop,…}` (`:543-545`, `:909-912`).
So the reading predicts the proxy dies on a child kill.

Deliberately did **not** let this substitute for B1-prove. Twice in this audit a
`file:line` reading was shipped as a result and was wrong. Reading it a third
time is not the check.

### 3. Nothing passes `:child` except the test of the `:child` branch
Real sites — `form_recovery_test.exs:36, 48, 151, 174, 198` — are all `:root`.
Only `:75` passes `:child`, against a stub. Collapsing to `kill_live/1` deletes
one test and rewrites five one-word call sites.

### 4. W-5's open question resolves in the direction that clears it
`build_direct_filename/2` (`uploads.ex:419-434`) uniquifies **unconditionally**;
`build_upload_key/2` uniquifies only when `key_available?/2` says taken. The
direct path uses the stricter guard, so `finalize_direct/3`'s bare
`head_object/2` calls (`:266`, `:292`) verify a completed upload — they are not a
missing collision check. W-5 is not a live upload defect and does not need its
own phase. 7C confirms this rather than re-deriving it, and escalates if it
does not hold.

## New, not from the review — flagged, not actioned
`build_upload_key/2` calls `key_available?/2` unconditionally, so
`overwrite: true` + `force_filename` (honoured at `utils.ex:1196-1199`) still
gets a `unique_filename/1` suffix on collision, defeating the `overwrite` it
just honoured. Downstream-consumer surface only. Recorded for a decision in 7C;
this phase's remit is claims, not behaviour.

## S-7 upgraded from "check" to "expect a fix"
`assets/node_modules/` is **120 MB**, gitignored (`.gitignore:10`), and Hex globs
the filesystem — it does not read `.gitignore`. `mix.exs:89-98` ships `"assets"`
whole. Brando's frontend reaches consumers via Yalc, not the tarball, so the
open question is what the tarball needs `assets/` for at all.

## Phase 7 implementation — B1-prove result (2026-08-06)

**Measured: the proxy dies.** The `:child` branch's premise is false.

`live_form(conn, "/admin/pages/update/#{id}")` → `find_live_child(view, "brando-chrome")`
→ `Process.exit(child.pid, :kill)`. Within the same 500 ms window
`await_proxy_exit/1` allows, the root's proxy pid delivers `:DOWN`.

Causation was established, not assumed — the plan's standard, and it was worth
the extra run:
- `assert Process.alive?(proxy_pid)` before the kill: passes.
- A control test that mounts, finds the child, and **kills nothing** asserts
  `:proxy_survived` after 500 ms: passes. Also asserts `child.pid != view.pid`,
  so the child is a genuinely distinct process and not the root under another
  name. Deleted after it did its job.

So the reading recorded above ("§2 the reading was re-done, agrees") was right,
and *running it was still the check* — a stub could never have shown this,
because the stub is the claim wearing a `spawn/1`.

**Consequence for B1-fix:** take the "proxy dies" branch. `kill_live/2`'s
`:root`/`:child` distinction is not real; collapse to `kill_live/1`.

## Phase 7 implementation — W-5-investigate result (2026-08-06)

**The conclusion holds; the plan's wording for it does not.** The plan said
`build_direct_filename/2` "uniquifies **unconditionally**". It does not — it has
three branches, and the plan's sentence describes only the third. Checked
branch by branch against `build_upload_key/2` (`utils.ex:1174`), which is what
the comparison was actually for:

| config | `build_upload_key/2` | `build_direct_filename/2` |
|---|---|---|
| default | slugify, uniquify **only if the key is taken** | slugify, uniquify **always** |
| `random_filename: true` | `random_filename/1` | `random_filename/1` — identical |
| `overwrite: true` | slugify, **and still uniquify if taken** | slugify, no uniquify |
| `overwrite: true` + `force_filename` | forced name, **and still uniquify if taken** | slugify; `force_filename` not honoured |

So in every branch where collision-safety is *wanted*, the direct path is at
least as strict as `build_upload_key/2`, and in the default branch strictly
stricter. In the `overwrite` branch it does not uniquify — which is the
requested behaviour, and the row where `build_upload_key/2` is the one getting
it wrong (see the `overwrite`/`force_filename` observation below).

`random_filename/1` was checked rather than assumed: `random_string/1`
(`utils.ex:182-192`) hashes `{seed, :os.timestamp()}`, so it is time-varying
and not a deterministic function of the filename. A deterministic one would
have been a real collision bug in both paths.

**`finalize_direct/3`'s `head_object/2` calls (`uploads.ex:266`, `:292`) are
verification, not a missing guard.** They run *after* the client has PUT to the
presigned key, and feed `validate_direct_object/3`'s size and content-type
checks. Collision detection at that point is not merely absent, it is
impossible — the object is already written. The only place a guard could sit is
key construction, in `initiate_direct_asset/3` (`:395-398`), and that is what
`build_direct_filename/2` is.

**W-5 is not a live upload defect.** No escalation; 7C absorbs it as planned.

## Phase 7 — the `overwrite:` observation, sharpened (2026-08-06) — AWAITING DECISION

The plan flagged this as "`overwrite: true` + `force_filename` still collects a
`unique_filename/1` suffix". Checking it made it **broader**, and gave it a
structural counterpart in this same repo.

**`build_upload_key/2` (`utils.ex:1174-1182`) never honours `overwrite:` at
all** — with or without `force_filename`:

```elixir
key = concat_with_upload_path(filename, file_cfg)
if Brando.CDN.key_available?(key, file_cfg), do: key, else: unique_filename(key)
```

There is no `overwrite` branch on that `if`. `overwrite: true` only changes
*which name is chosen* (it is what lets `get_valid_filename/2`'s
`force_filename` clause match at `:1196`); the suffix is then applied to
whatever name came out, whenever the key is taken.

**The local filesystem path gets this right, and its shape is the fix.**
`upload.ex:321-327`:

```elixir
dest =
  if Map.get(cfg, :overwrite) do
    joined_dest
  else
    (File.exists?(joined_dest) && Path.join(ul_path, unique_filename(fname))) || joined_dest
  end
```

Same decision, one `if` more. So the two transports disagree on a documented
option: `file_config.ex:22` declares `:overwrite` as "Allow overwriting existing
files with the same name", and the CDN key path silently does not.
`build_direct_filename/2` (`uploads.ex:427`) also honours it correctly — so
`build_upload_key/2` is the odd one of three.

**Fixed** (user's call, after being surfaced rather than actioned silently).
`build_upload_key/2` now short-circuits on `overwrite` and skips the bucket
check entirely in that branch — one fewer `HEAD` per upload, and the option
finally does what `Brando.Type.FileConfig` says it does.

The mutation is the part worth keeping: removing the branch made both new tests
fail with `Mox.UnexpectedCallError — no expectation defined for head_object/3`.
That is a stronger RED than an equality assertion, because *the call itself* is
the defect — the test asserts the bucket is never consulted by declining to
stub it. Same trick is reusable anywhere "must not do X" is the requirement.

Same class as Phase 5's S1: a declared contract the write path does not
implement.

## Phase 7 implementation notes (2026-08-06)

Phase 7 shipped complete — all 19 tasks, closing all 14 triage items. Gates:
`mix test` **1280 + 135 doctests / 0** (+7 net: +5 ReqOptions, +2 provider
mirrors, +1 B1-prove, −1 deleted `:child` test), credo **284** (unchanged),
format and compile clean, unit-suite output **43 lines stdout / 27 non-dot /
0 stderr**,
E2E **107 / 0** on a full `--reset` (8.9m) — measured this round, not carried.
That closes the plan's one knowingly-carried assumption; the 107/0 the last
three phases inherited is now a number with a run behind it.

### 1. The plan's four "corrections to the triage" were themselves 50% wrong

The plan opened by re-verifying four findings and correcting them. Two of those
corrections were right (B1's real child exists; nothing passes `:child`). Two
were not:

- **Correction 2 predicted the proxy dies, and it does — but the plan was right
  that reading it a third time was not the check.** B1-prove ran, and the value
  of running it was not the answer, it was the *control*. Asserting "the proxy
  died after I killed the child" is satisfied by a proxy that was going to die
  anyway. The control test (mount, find the child, kill nothing, assert the
  proxy survives 500ms) is what makes it causal, and it cost one extra run.
- **Correction 4 said `build_direct_filename/2` uniquifies "unconditionally".**
  It does not — three branches, and the sentence describes the third. The
  *conclusion* survived, but only after checking the other two.

*This is now the audit's most durable lesson, in its fourth form: an agent
finding is a hypothesis with a `file:line`, and so is a plan's correction to
one. The plan said "reading it a second time is not the check. Running it is."
That applied to its own prose too.*

### 2. Two estimates were off by an order of magnitude, both in the same shape

S-6 was scoped as "two of the 76 baseline lines". It was **33** — each
deprecation warning carries a ~16-line stacktrace, and the finding counted the
`warning:` line only. S-7 was scoped as "very likely live"; it was live and
`node_modules/` was **98% of the tarball's `assets/` entries**.

Both under-estimates come from counting the thing named rather than the thing
emitted. Worth carrying: a line-count baseline is only meaningful if you know
whether the lines are self-contained.

Related, and worth fixing in the next baseline: **the output-line metric is
partly wrap-noise.** 1413 progress dots wrap into a variable number of lines,
so a test-count change moves the number without any output changing. The stable
figure is **non-dot lines: 29 on stdout, 0 on stderr.** Use that in Phase 8.

### 3. `mix hex.build` could not complete at all

Found by doing S-7 rather than reasoning about it: the build stops with
`Missing metadata fields: links`, so the package was unpublishable — a state no
amount of arguing about `files:` would have surfaced. The file list still
prints before the failure, which is why the audit was possible at all.

### 4. The `overwrite:` observation got broader on contact

The plan flagged `overwrite: true` + `force_filename`. Checking it showed
`build_upload_key/2` never honours `overwrite:` in any form, and that the local
filesystem path (`upload.ex:321-327`) already has the exact `if` it is missing.
Recorded above; **not actioned, decision pending.**

### 5. Both reserved decisions went the other way, and both were right to ask

The plan fenced two items as "surface, don't action". Asked, and the user took
the fix in both cases:

- **The `overwrite:` bug** — fixed, with the Mox-no-expectation RED above.
- **`assets/` in the tarball** — dropped entirely rather than narrowed.
  Final tarball **1388 files / 1.3 MB**, from 11_194 `assets/` entries alone.

Worth noting what asking bought beyond permission: writing the question forced
the check that `UPGRADE.md:796` is in the *0.44.0* section, i.e. a historical
record rather than current guidance. The plan's own phrasing ("strike the stale
line") would have falsified what 0.44.0 required. It got a dated note instead.

### Deliberately not done, and why
- **The missing-credential disagreement** (Mux/Bunny raise, Cloudflare returns
  `{:error, :not_configured}`). Fourth recording. Still pre-existing, still
  unasked-for by any finding.
- **`Brando.CDN.get_s3_config/2`'s other four `Map.from_struct/1` sites**
  (`:97, 107, 210, 348`). None warn; only `:119` ever receives a non-struct.

## Sequencing rationale
7A (harness) first for the Phase 5/6 reason — it rewrites the instrument every
later RED run is read off, and B1-fix decides whether two of S-3's four comment
sites still exist. 7B/7C/7D are mutually independent. 7E last because S-6 moves
the output-line baseline (76 → 74 expected), and measuring before it lands gives
a number Phase 8 cannot reproduce.

## Phase 8 planning decisions (2026-08-06)

Planned directly from `reviews/phase-7-review.md` — no research agents. The
findings are the research; the three highest-severity ones were re-verified
against the vendored deps during the review itself.

**Two decisions taken before writing tasks**, both because either answer would
have produced materially different work:

1. **S-3 vs B1-fix → rewrite both narration blocks in present tense.** Neither
   standard is amended. S-3's ban stands; B1-fix's argument survives but stops
   being told as history. Rejected: deleting the argument (loses a real
   why-not-the-obvious explanation), and amending S-3 (weakens the standard for
   one hard case).

2. **Bunny `AccessKey` cross-host forwarding → fix in Phase 8**, not defer, not
   prove-first. Unlike B1 there is nothing to observe:
   `remove_credentials_if_untrusted/3` (`req/steps.ex:1573-1582`) deletes
   exactly `authorization` and `:auth`, and Bunny sends neither. The fix goes in
   `built_opts` rather than as a documented default specifically because
   `Keyword.merge(configured || [], built_opts)` makes it config-proof.

**The framing that drove 8A.** The blocker is not three wrong numbers — it is
that S-2, the task whose job was re-verifying them, moved a correct citation to
a wrong one and recorded the move as a correction (`phase-7-plan.md:147`). Third
instance of the same shape in three phases. The structural answer is to stop
citing interior line numbers where a function head will do, not to read more
carefully.

## Phase 8 implementation notes (2026-08-06)

Phase 8 shipped complete — all tasks across 8A–8G. Gates: `mix test`
**1281 + 135 doctests / 0** (+1 net), credo **284** (unchanged), format and
compile clean, unit-suite output **43 stdout / 27 non-dot / 0 stderr** — exactly
the corrected baseline. Every one of the five per-test mutations was run and
watched go RED.

**E2E — measured 2026-08-06: 107 passed / 0 failed, 8.8m**, full `--reset` (DB
drop → rollback-to-baseline → forward → reseed), 1 worker, Google Chrome. Run
against this phase's tree, which includes the Bunny `redirect: false` transport
change. Recorded here rather than only in a verification table, per 8G — the
Phase 7 number was correct but had no artifact anyone could point at, which is
what made the review mark it UNCLEAR. This one has a run behind it and a date on
it.

### 1. All five B1 citations verified, and the plan's table was exactly right

Rare enough in this audit to record. Against the vendored 1.2.8: `:848` builds
the struct and `Process.monitor(pid)` is `:849`; `:856` writes `state.views`
while `pids:` is `:857`; `fetch_view_by_pid/2` is `:909-913` with `:908` blank;
`:1001` and `:542-545` hold. Replaced with function heads (`put_view/3` `:846`,
the `handle_info({:DOWN, …}, state)` clause `:542`, `fetch_view_by_pid/2`
`:909`) plus `recursive_detect_added_or_removed_children/4` by name.

### 2. W-1 was right that the doc was stale and wrong about what replaces it

The review said to swap the `Map.from_struct/1` clause for "the config error S-6
raises". Measured, that raise is **not** what a CDN-less caller hits.
`%Brando.CDN.Config{}` defaults `:s3` to a populated `%S3Config{}`, so the
fallback clause *succeeds* and hands back a keyword list of nil credentials. The
raise arrives one line later at `cdn_config.bucket` — a `BadMapError` on `nil`.
`get_s3_config/2`'s own raise needs `:cdn` present **and** carrying an explicit
`s3: nil`.

*Fifth instance of the audit's most durable lesson, and the first where the
correction offered by the finding was itself the wrong replacement.* The doc's
conclusion — raises before any network call, so callers must check first —
survived unchanged; only the mechanism was wrong.

### 3. S-1's premise does not hold, so it became a comment

The review cited `uploads.ex:385-389` as proof that a keyword-list config
reaches `Map.from_struct/1`. That code normalizes a keyword-list **CDN** config,
which is a different thing from a keyword-list **`:s3`** sub-config. Measured
all four shapes: a keyword-list CDN config raises `BadMapError` in `config/2`'s
`Map.get/3` long before the guard, so widening the guard could not catch it. The
shape that *does* slip past is a keyword-list `:s3`, which nothing in this repo,
its docs or its tests writes — and which the unguarded sibling clause would
still raise on. Recorded in the comment; no behaviour change.

### 4. A blanket mutation claim covering five tests was one test and four assumptions

W-4c was right. Only the merge-order flip reddens the precedence test. The
others need: a `Keyword.take` allowlist (pass-through, and the new `:auth`
round-trip), dropping the `|| []` (stored-nil), and dropping the `[]` default
from `get_env` (unset provider). Writing them down found an error in my own
comment: dropping the `|| []` reddens **both** nil tests, because an absent key
also yields `nil` from `Keyword.get([], :req_options)`. Only the `get_env`
mutation distinguishes them. *A per-test mutation comment is itself a claim, and
running it is what makes it true.*

### 5. The Bunny leak reproduced exactly as read

No observation was needed to justify the fix (per Decision 2), but the test
still measured it: with `redirect: false` removed, the stub receives
`{:request, "evil.example.com", ["bunny-key"]}`. The credential arrives at the
other host verbatim. `Req.TooManyRedirectsError` after ten hops, each carrying
the key.

### Deliberately not done, and why
- **Suppressing the Mux 422 log** already in the baseline. Pre-existing, and
  narrowing scope to my own new line kept the baseline comparison honest.
- **The missing-credential disagreement** (Mux/Bunny raise, Cloudflare returns
  `{:error, :not_configured}`). **Fifth recording.** Phase 9 decides or stops
  recording it, per the Phase 8 plan's own instruction.

---

## Phase 8 review, and the fixes it produced (2026-08-07)

Panel: elixir · security · testing · requirements · verification. Verdict
**REQUIRES CHANGES** — 2 BLOCKERs, 3 WARNINGs, 5 SUGGESTIONs. Full text in
`reviews/phase-8-review.md`. All findings fixed the same day; measurements
below are from the fixed tree.

### 1. The phase's own remedy was not applied to the file the phase edited

B1: `cdn.ex`'s W-1 rewrite cited `:429` for `cdn_config.bucket`. The real site
is `head_object/2`, and `:429` was a **blank line inside the docstring holding
the citation**. 8A's remedy — cite function heads — worked perfectly where it
was applied (all five `live_case.ex` citations verify); it simply was not
carried to 8B's file. W1 was the same thing at one remove: `req_options.ex`
cited `bunny.ex:422, 428`, and SEC-1's own 18-line comment moved those lines
**in the same commit**.

Both now cite by function (`head_object/2`, `api_request/3`). The lesson is not
"be careful" — it is that the remedy has to travel with the standard.

### 2. A false record about an observation, not a citation — a new category

B2 is the one worth keeping. `phase-8-plan.md:195` recorded *"RED confirmed:
killing the root yields `{:proxy_stopped, :shutdown}`."* It does not.
`client_proxy.ex`'s `handle_info({:DOWN, …}, state)` clause propagates the
monitored view's reason **verbatim**, so a root killed with `:kill` also reports
`:killed`. The review ran the mutation: `1 test, 0 failures` — the assertion
passed with the child entirely uninvolved.

Fixed by killing the child with a reason **only that kill can produce**:
`Process.exit(child.pid, :child_died)`. Measured both ways afterwards —
root → `{:proxy_stopped, :killed}` (fails), proxy survives → `:proxy_survived`
(fails). The record in the plan is amended, not replaced, per B1-record's
precedent.

*Three phases running, the audit's most durable lesson has been about
citations. This is the first time it was about a claimed **observation**, and
the generalisation is the sharper one: a claim whose only check is a re-read is
not checked. Settling it cost one edit and a 13-second run.*

### 3. The review panel reproduced the defect it was reviewing — twice

Not incidental, and cheaper to record than to rediscover:

- `elixir-reviewer` reported the doc's `BadMapError` as wrong, claiming
  `UndefinedFunctionError` on `nil.bucket/0`. **Measured: `BadMapError`.** The
  doc was right. `cdn_config` is a *variable*, so the dot takes the map path;
  the `UndefinedFunctionError` reading applies to a literal atom.
- `verification-runner` reported 32 non-dot output lines against a 27 baseline
  and flagged a regression. **Re-measured: 27**, matching Phase 7 exactly. A
  counting difference, not output.

Both were caught by measuring rather than by re-reading — the same move that
settled B2. **A review pass is not exempt from the rule it is enforcing.**

### 4. One security finding the phase surfaced but did not look for

`cdn.ex`'s `upload_image/4` raise interpolated the full S3 config into its
message — `access_key_id` and `secret_access_key` in plaintext, into a string
that reaches the Logger, Oban's `errors` column and any error reporter.
Pre-existing, and adjacent to the `Map.from_struct/1` path W-1 spent the phase
describing without anyone reading what the value *contained*.

Fixed at the raise (`Keyword.drop/2`) **and** on the struct
(`@derive {Inspect, except: …}`). Worth stating why both: by the raise the
struct is already a keyword list, so the derivation does not cover it — and the
derivation alone would have looked like a fix while changing nothing. That
asymmetry is now written into both the struct's `@moduledoc` and the CHANGELOG.

The fix had **no test at all** when first written — an unfalsifiable security
claim, which this audit treats as a defect in its own right. `test/brando/cdn/cdn_test.exs`
now carries five, and both mutations were run:

* restore `inspect(s3_config, pretty: true)` → the message comes back as
  `access_key_id: "TESTKEY", secret_access_key: "TESTSECRET"`. Reddens on the
  **first** refutation only — both values return, but they share a test, so the
  second never runs. The comment says so; the first draft said "both go red",
  which is the same overclaim W3 was about.
* remove the `@derive` → the two inspect tests redden, separately, both
  reporting.

One test deliberately asserts the **gap**: the `as: :keyword_list` return value
is *not* redacted. It pins that the two fixes are independent, so neither can be
mistaken for covering the other.

### 5. Verification, fixed tree

| Gate | Baseline | Measured |
|---|---|---|
| `mix test` | 1280 + 135 doctests | **1287 + 135, 0 failures** (+6: the `req` version pin, and five CDN credential-redaction tests) |
| `mix credo --strict` | 284 | **284** exact (2 / 118 / 152 / 12) |
| compile `--warnings-as-errors` | clean | clean |
| `mix format --check-formatted` | clean | clean |
| Unit-suite output | 43 / 27 non-dot / 0 stderr | **43 / 27 / 0** exact |
| E2E (`--reset`) | 107 / 0 | **107 / 0, 8.9m**, measured 2026-08-07 — run **twice**: once before the fixes and again against the modified `lib/`, since the second round touched `cdn.ex` and `s3_config.ex` |

Caution for whoever measures the noise figure next: a `mix test` run that also
**recompiles** adds two non-dot lines (`Compiling N files`, `Generated brando
app`). The 43/27 figure is a warm-build number. That is what the 27-vs-32
disagreement in §3 came down to, and it will recur.

### 6. `req` now has the tripwire the LiveView citations already had

`ReqOptions`' `@doc` cites `req/steps.ex` by line eight times against 0.7.2,
while `mix.exs` pins `~> 0.5 or ~> 1.0` — wide enough for all eight to go stale
silently. `req_options_test.exs` now asserts `0.7.2` the way
`form_recovery_test.exs` asserts `1.2.8`. Two different jobs, worth not
conflating: `mix.exs` says what the library will *run* with, the test says what
the prose was *checked* against.

### Still deferred, sixth recording
The three video uploaders disagree on missing credentials (Mux/Bunny raise,
Cloudflare returns `{:error, :not_configured}`, `cloudflare.ex:272-273`). No
review finding has ever asked for it. Per the Phase 8 plan: **Phase 9 either
chooses it deliberately or stops recording it.**

---

## State of the tree at end of session (2026-08-07, night)

**Nothing is committed.** Everything below is in the working tree on `next`.
Committing is the first thing to decide tomorrow; the changes are green on every
gate but they are one commit's worth of work, not eight.

Modified:

| File | Why |
|---|---|
| `lib/brando/cdn/cdn.ex` | B1 citation → `head_object/2` by name; the `:cdn`-subject comment disambiguated; credentials dropped from `upload_image/4`'s raise |
| `lib/brando/cdn/s3_config.ex` | `@derive {Inspect, except: […]}` + `@moduledoc` naming the gap it does not cover |
| `lib/brando/videos/uploaders/req_options.ex` | W1 citation → `api_request/3` by name; `:redirect_trusted` bullet now says which providers it exposes and why Bunny is not one |
| `test/brando_admin/live/form_recovery_test.exs` | B2: kill the child with `:child_died` so the reason is causal; W2 comment corrected; version-assertion failure message now names both couplings |
| `test/brando/videos/uploaders/req_options_test.exs` | W3 mutation comment corrected (`:plug` must stay in the take list); new `req` 0.7.2 version pin |
| `test/brando/cdn/cdn_test.exs` | **new** — five tests pinning the credential redaction and the gap between its two halves |
| `CHANGELOG.md` | Fixes entry for the credential redaction, above the Bunny one |
| `.claude/plans/form-audit/plan.md` | Phase 9A: `## START HERE` block; nine boxes labelled; `form.ex` line count corrected |
| `.claude/plans/form-audit/phase-8-plan.md` | W-4b's false record amended, original quoted, per B1-record's precedent |
| `.claude/plans/form-audit/phase-9-plan.md` | **new** — the plan to pick up |
| `.claude/plans/form-audit/reviews/*-p8.md`, `phase-8-review.md` | **new** — the panel output and the review |
| `.claude/plans/form-audit/reviews/.requirements-input.md` | now holds the Phase 8 plan (it is the review skill's scratch input, not a record) |

**Final gates, all measured on this tree:** `mix test` 1287 + 135 doctests / 0
failures · `mix credo --strict` 284 (2 / 118 / 152 / 12) · compile
`--warnings-as-errors` clean · `mix format --check-formatted` clean ·
unit output 43 / 27 / 0 warm · **E2E 107 / 0, 8.9m**.

**Open decision, first thing:** the video-uploader credential disagreement.
`phase-9-plan.md` §Decisions lays out (a) all raise, (b) all return
`{:error, :not_configured}`, (c) close it and delete the recording. (a) and (b)
are both breaking changes on a library. Phase 9B is deliberately unwritten until
that is answered.

