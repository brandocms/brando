# Phase 2 review — form audit (upload & delivery robustness)

**Scope:** commits `cfb3639fc`, `d852ec7ef`, `a3f8a7d35` on `next` (`git diff HEAD~3`)
**Agents:** elixir, liveview, security, testing, ecto, oban, requirements, verification (8)
**Date:** 2026-08-05

> **RESOLVED 2026-08-05** in `3694b9769` (B1, B2, W1, W7) and `f303564f5`
> (W2–W6, W8, suggestions). Every finding is either fixed or explicitly deferred
> with a reason — see "Disposition" at the foot of this file. Final gates: 1198
> tests / 0 failures, credo unchanged from baseline, e2e re-migrated and compiling.

## Verdict: REQUIRES CHANGES

Not because the phase is wrong — the requirements check came back **20 MET / 0 PARTIAL /
0 UNMET** with no scope creep, and every gate passes. Because three defects in *new* code
survived my own testing, one of them a behaviour regression the change itself introduced.

## Requirements Coverage

| | |
|---|---|
| MET | 20 |
| PARTIAL | 0 |
| UNMET | 0 |
| UNCLEAR | 8 (not re-verified within the agent's turn budget, not disputed) |

All four claimed deviations from the original findings were independently confirmed against
the code: D6 (`video_block` genuinely had no image id), D-dup (`gallery_objects.ex` genuinely
lacked D4's bug), D7 (the guard existed and was wrong in both directions), and D2's WON'T-DO
(the `UPLOADER.md:176-178` quote is verbatim and the reasoning follows). The one unchecked
box — the file/video picker upload-root helpers — is genuinely still open.

## Gates

| gate | result |
|---|---|
| `mix compile --warnings-as-errors` | PASS |
| `mix format --check-formatted` | PASS |
| `mix test` | PASS — 135 doctests, 1188 tests, 0 failures |
| `mix credo --strict` | PASS — 2 / 118 / 152 / 12, **exactly** the baseline |
| `cd e2e && MIX_ENV=e2e mix compile --warnings-as-errors` | PASS |
| e2e Playwright suite | **NOT RUN** — do before merge |

---

## BLOCKER

### B1. D5's merge reverts a freshly-processed image `[liveview]`

`input/gallery.ex` has three write paths for `gallery_objects`; only `assign_value/1` goes
through `Galleries.merge_loaded_media/2`.

`merge_loaded_media/2` decides changeset-vs-cache on *"is the association loaded"*, not
*"which is fresher"*. So after `%{action: :update_image, force_validation: true}` (the
post-Oban-processing refresh) writes a fresh image into the cache, the very next unrelated
update re-derives from the changeset and — if the changeset's copy happens to be loaded —
silently reverts to the stale one.

**This is a regression the D5 fix introduced.** The `assign_new` it replaced could not lose a
refresh, because it never re-read. Trading staleness-on-external-mutation for
staleness-on-refresh is not the trade D5 was meant to make.

### B2. The D5 raw-append clause can duplicate an uploaded image `[liveview]`

`gallery.ex:73-111`, the `%{new_image:, selected_images:}` / `%{new_video:, …}` clauses do a
non-idempotent `assign(:gallery_objects, list ++ [new_image])` off whatever the assign held.
`form.ex`'s `entry_field_upload_complete` both `send_update`s that payload to Gallery *and*
updates its own `:form` assign, which reaches Gallery via the parent's next render and
triggers the changeset-derived path too — for the same event, with no guaranteed ordering.
If the raw append lands second, the image is duplicated in the UI until something forces
re-derivation.

Pre-existing clauses, but D5 is what put a second writer next to them.

---

## WARNING

### W1. The topic handshake writes a non-sticky DOM attribute `[liveview]`

`assets/src/hooks/Form/index.js` sets `this.el.dataset.deliverTopic = topic` as a plain DOM
mutation. **This repo's own CLAUDE.md documents that such mutations are wiped by morphdom on
the next patch** — and this component re-renders often (Presence diffs; see the plan's own
Phase 3 finding E). In the window before the server adopts the topic, a revert plus an upload
trigger reading the attribute captures the stale topic — the exact bug D2 exists to fix.

My browser check missed this: I forced a re-render *after* the server had adopted, which is
the safe side of the window.

Also: a first-ever mount (empty sessionStorage) forces an unnecessary
subscribe → unsubscribe → resubscribe round trip, reopening a narrow version of the race.

### W2. `UploadIntentReaper`'s retry is dead code `[oban]`

`reap/1` always returns `true` and `perform/1` always returns `:ok`, so `max_attempts: 2`
never engages. A delete failure gets exactly one attempt, is logged at `:warning`, and the row
is dropped in the same pass — Oban's retry is inert for precisely the failure this worker
exists to handle.

### W3. A failed reap leaves an orphaned object with no durable trace `[oban]`

Dropping the row on delete failure was deliberate (otherwise the sweep retries nightly
forever), but it means a genuinely orphaned S3 object — permissions, bucket down — survives
only as a log line. `VideoUploadReaper`'s sibling design preserves state for exactly this
reason.

### W4. The reaper shares `:default` with interactive uploads `[oban]`

`:default` has `limit: 1` and also carries `FileUploader`/`ImageUploader`.
`list_stale_pending_intents/1` is unbounded and `reap/1` does serial per-row S3 calls inside a
5-minute timeout. A backlog could block user-facing uploads for minutes. `image_processing`
already has its own queue for this reason.

### W5. Orphan finalize misattributes the creator `[security]`

`finalize_orphaned_complete/3` finalizes with the *calling socket's* `current_user` and never
compares against `intent.creator_id`. Not exploitable without knowing another admin's ref, but
it is a gap I introduced and did not consider.

### W6. Topic unguessability is the only cross-entry guard `[security]`

`validate_deliver_topic/1` checks shape, not ownership, and the receipt side (`hooks.ex`
`deliver_asset/3`, `form.ex` `entry_field_upload_complete`) has no redundant check that a
broadcast's target matches the receiving socket. A 122-bit UUID is doing all the work, with no
fail-loud fallback if one ever leaks. Partly pre-existing — but accepting a *client-supplied*
topic widened what that guess protects.

### W7. Three D1 tests don't pin the defect they claim to `[testing]`

`pending_intent_test.exs:191-229`. The pre-fix `_ -> {:noreply, socket}` produces identical
observable results to the new `nil -> finalize_orphaned_complete(…)` under every assertion
they make: with no S3 mock, `finalize_item/2` fails either way, so "intent survives" and "no
crash" hold under both. They exercise the new path but are not regression tests, contrary to
the file's own comment. `ExUnit.CaptureLog` on the new log lines fixes it cheaply.

### W8. `PendingIntent` timestamps are off-convention `[ecto]`

No `@timestamps_opts [type: :utc_datetime_usec]`, so the new table silently uses
`:naive_datetime` — inconsistent with the project, though internally consistent with
`list_stale_pending_intents/1`'s `NaiveDateTime` cutoff.

---

## SUGGESTION

- `AssetIntent.get/2` calls `String.to_existing_atom/1` unconditionally via `Map.get/3`'s
  eagerly-evaluated default, even when the key is present. Safe today only because the atoms
  exist and the function is rescue-wrapped. `[elixir]`
- Minor TOCTOU in ref-based `delete_pending_intent/1` (get-then-delete). Low risk at current
  call sites. `[ecto]`
- `processing_queued?/1`'s `args` jsonb containment is not GIN-indexed; acceptable because
  Oban's `worker`/`state` partial index narrows first. `[ecto]`
- `form.ex:602/630` `component_id` fallback still uses the schema-based pattern D4 replaced
  elsewhere. Harmless — the real id is always supplied — but inconsistent. `[liveview]`
- Two comment gaps on subtle guard ordering in `merge_loaded_media/2` and `Thumb.same?/2`;
  one dead branch in `direct_cdn_config/2`. `[elixir]`

---

## Explicitly confirmed sound

Recording these so they are not re-litigated:

- **Both broad `rescue` clauses** (`initiate_provider_upload/5`, `finalize_item/2`) — scoped to
  the single raising call rather than a whole handler, and logged. No objection to the breadth.
- **The reaper's delete-for-real reasoning** — presigned URLs are expiry-enforced server-side,
  so the contrast drawn with `VideoUploadReaper`'s webhook case is legitimate, not asserted.
- **`pushEventTo(this.el, …)`** does reach the Form LiveComponent; `destroyed()` correctly
  needs no PubSub unsubscribe.
- **`editing_image?` / `editing_file?`** verified truthful on every reachable path.
  `Content.drawer` has no Esc/backdrop dismissal — only an X button that always submits.
- **`key` is fully server-generated** at presign, never client-supplied to storage or delete.
- **`merge_loaded_media/2`'s `NotLoaded` handling**, and `matches?/3` refusing `nil == nil`.
- **The plain-`Ecto.Schema`-not-Blueprint call**, the `Ecto.UUID.cast/1` guard on the
  client-supplied ref, and both migrations being in step.
- **The `Gallery.Media` / `Gallery.Thumb` seam**, and `deliver_entry_field_asset/5`'s atom
  construction (closed 3-atom set, fixed call sites, not client input).
- **The bare-socket test idiom** including the `:myself` workaround — acceptable and commented.

## Not assessed

- e2e Playwright suite (not run).
- Rate limiting on upload intake; `handle_upload_type/3` internals; the sessionStorage topic
  beyond W6.
- `iron-law-judge` was not spawned — `elixir-reviewer` overlaps it and Phases 0/1 have
  `iron-laws.md` / `iron-laws-2.md` on this code.

---

## Disposition (2026-08-05)

| # | finding | outcome |
|---|---|---|
| B1 | merge reverted a freshly-processed image | **fixed** — compares `updated_at`, ties prefer the changeset |
| B2 | delivery could duplicate a gallery object | **fixed** — `Galleries.append_unique_media/2` |
| W1 | topic written to the DOM non-stickily | **fixed** — `this.js().setAttribute` |
| W2 | reaper's `max_attempts` was dead code | **fixed** — `perform/1` returns `{:error, _}` on failure |
| W3 | failed reap left no durable trace | **fixed** — the row is kept, which is what makes W2 work |
| W4 | reaper shared `:default` with interactive uploads | **fixed** — own `:upload_reaping` queue, 500-row batches |
| W5 | orphan finalize misattributed the creator | **fixed** — refuses on `creator_id` mismatch |
| W6 | topic unguessability the only cross-entry guard | **partly fixed** — see below |
| W7 | three D1 tests did not pin the defect | **fixed** — assert on logs; 3/3 fail pre-fix |
| W8 | `PendingIntent` timestamps off-convention | **fixed** — `:utc_datetime_usec` in schema + both migrations |
| S1 | `AssetIntent.get/2` eager `String.to_existing_atom/1` | **fixed** |
| S2 | TOCTOU in ref-based `delete_pending_intent/1` | **not fixed** — accepted; see below |
| S3 | `processing_queued?/1` not GIN-indexed | **not fixed** — accepted, Oban's partial index narrows first |
| S4 | `form.ex` `component_id` fallback style | **not fixed** — accepted, harmless |
| S5 | comment gaps / dead branch | **fixed** for `direct_cdn_config/2` |

### W6 — what was and was not done

**Done:** stopped logging topics whole. A topic is a bearer token — presenting
it subscribes a form to another form's deliveries — and the instrumentation
added earlier in this phase had put a replayable credential into every log
aggregator. That was a leak vector *introduced by this phase*, so removing it
beats adding machinery to tolerate it. Logs now carry an 8-character prefix,
enough to pair the two sides of one delivery.

**Not done:** the redundant ownership check on receipt. It needs entry identity
carried in the upload target, which is a protocol change touching the
entry-field, block, var and gallery upload paths. Doing that unverified at the
end of a long session is how the two blockers above got written in the first
place. It wants its own change and its own e2e pass.

### S2 — why the TOCTOU is accepted

`delete_pending_intent/1`'s ref clause does get-then-delete. Both call sites are
inside a single LiveView process handling one event, so there is no concurrent
deleter; and the failure mode of losing the race is a `Ecto.StaleEntryError` on
a row that is already gone, i.e. the desired end state. Not worth a
`delete_all` rewrite.

### Still not run

The e2e Playwright suite. No JS behaviour changed since the bundle was last
rebuilt except `this.js().setAttribute`, but it should run before merge.
