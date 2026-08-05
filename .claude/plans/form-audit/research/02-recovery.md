# Form Recovery & Reconnect Resilience Audit

Scope: `lib/brando_admin/components/form.ex`, `lib/brando_admin/components/form/block_field.ex`,
`lib/brando_admin/components/form/block/render.ex`, `lib/brando_admin/components/form/block/events.ex`,
`lib/brando_admin/live_view/form/hooks.ex`, `assets/src/hooks/BlockField/index.js`,
`assets/src/hooks/Form/index.js`, `assets/src/hooks/Admin/index.js`,
`assets/src/buildApplication.js`, `assets/src/hooks/UploadManager/index.js`,
`deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts`.

> **Revision note**: this report was corrected after the first pass mischaracterized LiveView's
> *default* form recovery as "no recovery" when a form lacks an explicit `phx-auto-recover`
> attribute. That was wrong. Section "Correction" below documents what changed and why. The
> corrected failure-mode matrix and rankings follow it.

## Correction: how LiveView's default form recovery actually works

Verified against `deps/phoenix_live_view/assets/js/phoenix_live_view/view.ts`:

- `getFormsForRecovery()` (`view.ts:2525-2603`) snapshots **every** `<form>` in the current
  (about-to-disconnect) DOM that has a `phx-change` binding, a stable `id`, at least one form
  element, and does **not** have `phx-auto-recover="ignore"` (`view.ts:2543-2555`). An explicit
  `phx-auto-recover="some_event"` only *renames* the event pushed on recovery — it is not a
  prerequisite for recovery to happen at all. **Absence of the attribute means "use the
  default" (resubmit the form's own `phx-change` event), not "no recovery."**
- On rejoin, `maybeRecoverForms()` (`view.ts:769-851`) matches old forms to new forms by `id`
  + identical `phx-change` value, and pushes the *old* (pre-disconnect) DOM values through
  that `phx-change` event, targeted via the *new* form's `phx-target` (`pushFormRecovery`,
  `view.ts:2421-2523`) — so component targeting (CID resolution) is redone against the
  freshly-mounted component tree, not a stale CID.
- Critically: **a form can only be recovered if it exists, with the same `id`, in both the old
  and the newly-rendered DOM** (`view.ts:814-816`, `.filter((newForm) => newForm.id &&
  oldForms[newForm.id])`). A form that is conditionally absent from the fresh render (e.g.
  gated by `:if` on server state that resets to `nil`/`false` on a fresh mount, or a block
  that doesn't exist in the DB yet) cannot be recovered by this mechanism — there is no
  "new form" to match against. This is the actual, precise boundary of the built-in
  mechanism, and it's why Brando's custom `recover_blocks` machinery exists at all (see below).

### (a) Does the main entry form receive default recovery on reconnect? **Yes.**

`form.ex:2048-2055`:
```elixir
<.form id={"#{@id}_form"} class="main-form" for={@form} phx-target={@myself}
       phx-submit="save" phx-change="validate">
```
Stable `id`, `phx-change` set, no `phx-auto-recover="ignore"` anywhere in the file (confirmed
by grep — the only two `phx-auto-recover` usages are the drawer and live-preview hidden
forms, both explicit event renames, `form.ex:2036`, `form.ex:5281`). This form qualifies for
default recovery and the codebase's own comment at `form.ex:4136-4144` documents the
recovery race between it and the two custom `phx-auto-recover` forms:
> "Recovery is two independent `phx-auto-recover` forms — this one and the main form's
> `validate` — and LiveView orders them however it likes..."
This confirms the authors know and rely on `validate` firing as a recovery event.

### (b) `handle_event("validate", ...)` — does recovered input survive against a fresh changeset?

`form.ex:2976-3031`, in full read. Key lines:
```elixir
def handle_event("validate", params, socket) do
  # This is also the recovery event for the main form, and it is what
  # rebuilds the entry from the recovered params — see
  # `maybe_finish_live_preview_recovery/1`.
  ...
  entry_params = Map.get(params, singular)
  entry_or_default = entry || struct(schema)
  changeset = validate(schema, entry_or_default, entry_params, current_user)
```
On a fresh remount, `socket.assigns.entry` is loaded straight from the DB (same pattern as
the block subsystem — see below). The recovered form's DOM params (`entry_params`, i.e.
whatever the user had typed before disconnect) are cast on top of that fresh entry via the
normal `validate/4` changeset pipeline — this is the *correct* recovery pattern: fresh base +
replayed diff, exactly analogous to how block recovery works. **No filtering, dropping, or
DB-value override was found in this handler that would discard recovered values.** Plain
fields (title, slug, and any input inside the unconditionally-rendered `.form_tabs` /
`MetaDrawer` / SEO fields / most subforms) **are recovered**, contrary to the first-pass
finding.

### (c) What is genuinely NOT recovered — precise enumeration

State with no corresponding DOM input, or whose DOM input is conditionally absent at the
moment of rejoin, falls outside the default mechanism:

1. **Picker/drawer *field edits* (title/credits/alt on the image/video/file being edited)** —
   confirmed gap, but for a more precise reason than the first pass gave. The drawer's real
   edit form (`form.ex:2376-2490`, `id="image-drawer-form"`, `phx-change="validate_image"`)
   is rendered `:if={@image_changeset}` (`form.ex:2380`). On a fresh mount `@image_changeset`
   is `nil` until the separate `recover_drawer_state` handler (`form.ex:4075-4089`,
   `restore_image_drawer` at `6017-6043`) re-fetches the resource and sets it — which means
   **at the moment LiveView computes `formsToRecover`, `image-drawer-form` does not exist in
   either the old or the (still-being-processed) new DOM in a way the diff can use**: it's a
   chicken-and-egg problem, not a missing-plumbing problem. Once `recover_drawer_state` does
   fire and reopens the drawer, it seeds `image_changeset: Ecto.Changeset.change(image)` from
   the **DB**, not from any recovered field edits — there is no second recovery pass for a
   form that only just appeared. Net effect stands: **unsaved title/credits/alt edits typed
   into an open drawer are lost on process death**, but the *selection itself and which
   drawer was open* is correctly restored.
2. **In-flight async image processing correlation (`pending_block_image_updates`)** —
   `lib/brando_admin/live_view/form/hooks.ex` tracks `{module, id}` targets for uploads whose
   processed result hasn't arrived yet, purely in socket assigns (`assign(:pending_block_image_updates, %{})`,
   no DOM representation). A fresh mount reinitializes this to `%{}`. If the image-processing
   Oban job's `[:image, :updated]`/`[:image, :processing]` broadcast lands after a reconnect
   but the registration that would have routed it to the right component was lost with the
   old process, `deliver_pending_image/2` (`hooks.ex:412-437`) falls through to `{:cont,
   socket}` with nowhere to deliver it for block-ref-scoped uploads (uploads with an
   `entry_field`/`entry_field_gallery` config_target are routed a different way and are less
   exposed to this). **Flag as unverified nuance** — I did not trace whether the picture/file
   ref UI has a fallback that re-derives "still processing" state on remount and re-subscribes,
   or whether the thumbnail is simply stuck.
3. **Any other purely-client, purely-transient UI state with no field backing** (e.g. scroll
   position, which drawer tab is active if not itself a hidden input) — expected and low-value
   to recover, not flagged as a real gap.

### (d) Nested/LiveComponent forms — does `phx-target={@myself}` defeat recovery?

No. `getFormsForRecovery()` scopes by `#{CSS.escape(this.id)} form[phx-change]` where
`this.id` is the owning **LiveView's** root DOM id — LiveComponents render inside that same
DOM subtree (they are not separate views), so their forms are captured and recovered exactly
like top-level forms. `pushFormRecovery` (`view.ts:2421-2523`) explicitly resolves the target
CID against the **new**, post-remount component tree (`this.targetComponentID(newForm,
targetCtx)`), not a stale CID from before disconnect. Brando's main form
(`phx-target={@myself}` on a `BrandoAdmin.Components.Form` LiveComponent) and every block form
(`phx-target={@target}` on `BrandoAdmin.Components.Form.Block`) both work through this path
without issue.

### (e) Re-examined: does an existing (persisted) block's unsaved edit get lost? **No — this was wrong. Recovery works.**

`lib/brando_admin/components/form/block/render.ex:372` (and the two structurally identical
forms at lines 495, 641):
```elixir
<.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
```
`@form` is `to_form(changeset, as: ..., id: "entry_block_form-#{uid}")` for root blocks
(`block_field.ex:296,370,841,897`) or `"child_block_form-#{uid}"` for children
(`block.ex:505,1119,1664`) — a **stable id keyed on the block's UID**, unconditionally
rendered for any block that still exists (which persisted blocks do, immediately, on a fresh
mount from the DB). No `phx-auto-recover="ignore"` is present anywhere in the block render
tree. This form qualifies for, and receives, default LiveView recovery exactly like the main
form.

`lib/brando_admin/components/form/block/events.ex:764-828` (`validate_block`, entry_block
variant), read in full: it uses `original_data = changeset.data` (the block struct as loaded
fresh from the DB on this mount) as the base, and casts the recovered DOM params
(`params["entry_block"]`) on top through the normal `block_module.changeset/3` pipeline — the
identical "fresh base + replayed diff" pattern as the main form's `validate` handler
(confirmed by direct code comparison, not by the SKILL doc's prose alone). **An edited ref
(e.g. a swapped image, per the user's original example, for an *existing* block) survives a
full LiveView process death and reconnect**, because the ref's `image_id` is committed into
the block's own `@form` via `Block.commit_ref_data` → `assign_block_form` before disconnect,
which means it is present as a real DOM input inside `entry_block_form-#{uid}`/
`child_block_form-#{uid}` at the moment of disconnect, and gets replayed on reconnect through
default recovery.

**What the custom `recover_blocks` mechanism (`assets/src/hooks/BlockField/index.js` +
`block_field.ex:1140-1211`) is actually for**: exclusively **new, unsaved root blocks that
don't exist in the database yet**. Those have no persisted row, so after a fresh mount their
form simply isn't part of the newly-rendered HTML at all — LiveView's `id`-matching default
recovery structurally cannot help (no "new form" to match against, per the boundary
established in the Correction section above). The custom sessionStorage-based mechanism is a
deliberate, correctly-scoped complement to the default mechanism, not evidence of a gap in
it. The SKILL doc's own description ("Captures all block form data... sends `recover_blocks`
event with **missing** UIDs") already said this precisely; the first pass over-read the
mechanism's existence as implying existing-block recovery must be broken, which doesn't
follow.

## Failure-mode matrix (corrected)

| # | Scenario | Plain fields (title, slug, meta, SEO, subforms) | Existing (persisted) block edits, incl. ref image swaps | New/unsaved block | Nested child block of a **new** unsaved root | Picker/drawer: which resource is open | Picker/drawer: in-progress field edits (title/credits/alt) | Mid-upload transfer |
|---|---|---|---|---|---|---|---|---|
| 1 | Brief blip, LV **survives** | safe | safe | safe | safe | safe | safe | XHR direct PUT unaffected; `pushEvent` ack behavior across a live socket not fully verified |
| 2 | Blip long enough LV **dies**, remounts | **Recovered** — default LV recovery via `validate` (`form.ex:2976-3031`) | **Recovered** — default LV recovery via `validate_block` (`block/render.ex:372`, `block/events.ex:764`) | **Recovered** — custom `recover_blocks` mechanism (`block_field.ex:1140-1211`) | **DATA-LOSS, GAP** — see finding below, unchanged from first pass | **Recovered** — `recover_drawer_state` re-fetches and reopens | **DATA-LOSS, GAP** — see (c)1 above | Unverified |
| 3 | Full reload / browser crash | Lost — form recovery is a *reconnect* mechanism (`getFormsForRecovery` runs on `join()`), not a page-load mechanism; a hard reload has no "old DOM" to diff against | Lost, same reason | Lost — sessionStorage capture (`disconnected()`, `BlockField/index.js:55-57`) may not fire on an abrupt crash/tab-close before `beforeunload` | Lost | Lost | Lost | Lost — in-flight upload aborted |
| 4 | Server deploy (all LV processes die) | Recovered, same as #2 (reconnect path, not a fresh page load) | Recovered, same as #2 | Recovered, same as #2 | Lost, same as #2 | Recovered | Lost, same as #2 | Unverified |
| 5 | Mid-upload disconnect (`UploadManager`) | n/a | n/a | n/a | n/a | n/a | n/a | **FRAGILE/GAP**, unchanged from first pass — see below |

## Ranked findings

### 1. DATA-LOSS/GAP (confirmed, unchanged) — Nested/child blocks of a *new* unsaved root are never recovered
`assets/src/hooks/BlockField/index.js:110-118` captures every form under the sortable
container (including `child_block_form-{uid}` forms, `captureBlockForms()` line 74), but the
recovery filter only ever matches `entry_block_form-${uid}` for `uid` in `missingUids` (root
UIDs). Server-side, `block_field.ex:1163-1171` builds the recovered struct with
`children: []` unconditionally, and there is no code path that folds captured
`child_block_form-*` entries back in. This is a genuine gap **and** cannot be covered by
LiveView's default recovery either, because a new root block's children don't exist in the
fresh (post-remount) DOM at all — there's no "new form" for default recovery to match, and
the custom mechanism doesn't forward child data. **Repro**: add a new container/module block,
add 2-3 children, fill them in, disconnect before saving → reconnect → container recovered,
children empty.

### 2. DATA-LOSS/GAP (confirmed, refined) — Drawer field edits (title/credits/alt) lost while a picker/drawer is open
See (c)1 above. The gap is real but narrower than the first pass suggested: the *selection*
(which image/video/file is open) is recovered; unsaved *edits to that resource's own fields*
inside the drawer are not, because the drawer's edit form is conditionally rendered and
doesn't exist at the moment LiveView's recovery diff runs.

### 3. FRAGILE (confirmed, unchanged) — sessionStorage capture has a remove-before-confirm ordering
`BlockField/index.js:98`: `sessionStorage.removeItem(key)` runs before the try block that
parses stored data and sends `recover_blocks`. A failed/late push loses the snapshot
permanently, with only a `console.warn`. This affects new/unsaved blocks only (the custom
mechanism's scope), not existing block edits (which don't depend on sessionStorage at all).

### 4. GAP, partially unverified (confirmed, unchanged) — No TTL/entry-scoping on the block-recovery sessionStorage key
Storage key is schema-scoped (`"#{singular}_form-blocks-#{field}-wrapper"`), not
entry-scoped — no `entry_id` component. Same caveats as the first pass: plausible cross-entry
leak of new-block recovery data if a user disconnects on entry A and later opens entry B of
the same schema in the same tab before a reconnect consumes the key; exact trigger path via
`push_navigate` not fully traced.

### 5. FRAGILE/GAP, unverified (unchanged) — Mid-upload disconnect via `UploadManager`
`assets/src/hooks/UploadManager/index.js:163-198` — `directUpload`'s XHR PUT is independent
of the LiveView socket and continues through a brief blip, but completion acks
(`pushEvent('direct_complete', ...)`) have no visible retry/queue logic, and I could not
confirm from source whether `UploadManager` is a genuinely independent long-lived process
(its own comment calls it "sticky") that survives the *form* LiveView's death, which would
change the severity considerably either way.

### 6. Retracted — "existing block edits silently revert" (first-pass finding #1)
Re-examined in detail in (e) above. This does not happen: `validate_block`'s entry_block
handler uses `changeset.data` (fresh DB load) as base and casts recovered DOM params on top,
identically to the main form. Retracted.

### 7. Retracted — "non-block fields have zero recovery" (first-pass finding #2)
Re-examined in (a)/(b) above. The main form has no `phx-auto-recover` attribute, which means
it uses LiveView's *default* recovery (resubmit `phx-change="validate"` with the pre-disconnect
DOM values), not that it has none. `handle_event("validate", ...)` correctly rebuilds the
changeset from a fresh DB entry plus the recovered params. Retracted.

## What is done well (do not rebuild)

- Correct, deliberate use of LiveView's built-in form recovery for the main form and for
  every persisted block form — no custom plumbing needed there, and the code doesn't fight
  the framework.
- The custom `recover_blocks` mechanism is precisely scoped to the one class of state the
  built-in mechanism structurally cannot reach (new/unsaved blocks) — a correct, minimal
  complement rather than a duplicate of default recovery.
- Deliberate three-way recovery ordering handling between the main form's `validate`, the
  drawer's `recover_drawer_state`, and the live-preview's `recover_live_preview_state`
  (`form.ex:4136-4144`), with an explicit "whichever finishes last renders" resolution
  (`maybe_finish_live_preview_recovery/1`).
- Block recovery (the custom, new-block path) reconstructs through the real changeset
  pipeline (`block_field.ex:1176-1178`), not a shortcut, and preserves root order on merge
  (`block_field.ex:1198-1206`).
- `original_block_identifiers` / `changeset.data`-as-base patterns already solve a related
  but distinct class of `cast_assoc` footguns and are reused correctly across both the
  default-recovery path and the custom one.

## Explicitly unverified (could not determine from reading alone)

- Whether Phoenix's channel actually buffers/delivers `pushEvent` calls made in the narrow
  window between `reconnected()` firing and the channel being fully rejoined, versus
  dropping them silently.
- Exact behavior of `push_navigate` vs a hard link navigation with respect to sessionStorage
  timing for the cross-entry collision in finding #4.
- Whether `UploadManager` is a genuinely independent long-lived LiveView relative to the form
  LiveView's lifecycle (finding #5) — did not locate its mount/`live_session` configuration.
- The `pending_block_image_updates` mid-processing correlation gap (c)2 — whether there is a
  fallback re-subscription/re-derivation path on remount that I didn't find.
- Whether `disconnected()` reliably fires on an abrupt tab close / browser crash (row 3 of the
  matrix) versus only on a graceful/detected disconnect — this determines whether the
  new-block sessionStorage capture is written at all in that scenario.
