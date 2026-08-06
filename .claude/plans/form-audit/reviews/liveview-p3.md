# LiveView lifecycle review — Phase 3 (E/F perf pass)

Scope: the Phase 3 E+F changes on `next` (form.ex addon/transformer split,
`assign_new` conversions, image PubSub unsubscribe, block.ex conditional list
loading, block_field.ex `connected?` gating, image_picker cache removal,
dropped `Map.put(:action, :validate)`).

No `git` tool was available to this agent (Read/Grep/Glob/Write only), so the
diff was reconstructed by reading the current files plus the plan/scratchpad.
Items I could not close are marked **UNVERIFIED**.

---

## BLOCKERS

None found.

Everything I traced that could have been a KeyError or a lost subscription is
either always-assigned or re-established on the connected mount. Details below.

---

## WARNINGS

### W1 — `assign_new(:palette_options, …)` pins the palette list across a container change
`lib/brando_admin/components/form/block.ex:1299-1323` + `:2141-2145`

`maybe_assign_container/1` assigns `:palette_options` with `assign_new`, and
the closure reads `container.allow_custom_palette` and
`container.palette_namespace`. When the editor changes the container on a root
container block, `maybe_update_container/2` (`:2141`) re-assigns **`:container`
only** — not `:container_id`, not `:palette_options`.

User-visible: pick container A (`allow_custom_palette: false`), then switch to
container B (`allow_custom_palette: true`, namespace `"dark"`). The palette
select renders with `@palette_options == []` — an empty dropdown that only
recovers on a full block remount.

**The `assign_new` itself is pre-existing.** What Phase 3 changed is the inner
body, which now *also* branches on `renders_palette_options?/1`. That widens the
same staleness: a block that was ineligible when the value was first computed is
pinned to `[]` for the component's life. See W2 for why that turns out not to be
reachable today, and why that is luck rather than design.

Suggested: assign `:palette_options` (and `:container_id`) with `assign/3` from
`maybe_update_container/2`, or key the memo on `container_id`.

### W2 — the scoping predicate is correct only by accident
`block.ex:939-948` (`:containers`), `block.ex:1284-1285` (`renders_palette_options?/1`)

Confirming the coordinator's correction: `render.ex:528` sits inside
`container/1` (defined `:451`), whose only caller is `render(%{type: :container})`
at `:197/:200`. So `container_config` renders for **root containers**, not for
every root block. The `or belongs_to == :root` disjunct is therefore *redundant*,
not load-bearing.

Consequence for correctness: harmless — it over-includes, so no read site can
hit `[]` unexpectedly. Consequence for perf: root **module** blocks still copy
the full container list (and, via `renders_palette_options?/1`, the full palette
list) off ETS for a template they never reach. That is a meaningful slice of the
saving the change was after, on the most common block type in the editor.

Consequence for the next reader: the code comments at `block.ex:934-936` and
`:1280-1283` state the false premise as fact. Fix the comments with the fix, or
the next person will "restore" the disjunct.

**Recommendation:** narrow both predicates to `type == :container`, re-measure,
and correct the two comments. If you keep the disjunct, say why in one line.

### W3 — the justification comment for dropping `:action, :validate` is wrong on its face
`lib/brando_admin/components/form.ex:4946-4952` vs `:5556-5557`

The comment claims "both error gates in this file (`error_tag/1` and
`has_relation_error?/1`) go through `Phoenix.Component.used_input?/1`". They do
not. `has_error/2` has two clauses:

- `has_error(field, true)` (`:5546`) — relation case, correctly gated on `used_input?/1`;
- `has_error(%{errors: []}, _)` / `has_error(%{errors: _}, _)` (`:5556-5557`) —
  the **non-relation** case, which reads `field.errors` raw, no `used_input?`.

`has_error/2` is called from `:5452` (`failed = has_error(assigns.field, relation)`),
i.e. the field-label "failed" dot.

The behaviour change is real but in the *safe* direction: `to_form/1` on a
changeset with `action: nil` yields `errors: []`, so the raw-reading clause now
returns `false` for the initial/refreshed form instead of `true` for every
missing required field. That is the same class of spurious red dot the comment at
`:5548-5550` documents fixing for relations. So the change is right and the
reasoning given for it is wrong.

Risk of the reasoning being wrong: someone later re-adds
`Map.put(:action, :validate)` "because it's harmless", and blank create forms
sprout unexplained red dots on every field again. Rewrite the comment to name
`has_error/2`'s second clause as the actual mechanism.

I confirmed the three call sites are safe on the error-display axis:
- `assign_form/1` both clauses (`:4927`, `:4953`) build from empty params — only
  ever on first assign (`assign_new(:form, …)`).
- `assign_refreshed_form/1` (`:4961`) is reached only from success paths:
  `:728` (`update_entry_hard_reset`), `:3318`, `:3337`, `:3458` (post-save).
  No failed-save path routes through it, so no validation errors are erased.

### W4 — `[:image, :error]` unsubscribe assumes "final attempt", unproven here
`lib/brando_admin/live_view/form/hooks.ex:399-405`

`handle_hooks_image_info({%Image{id: id}, [:image, :error], _}, socket)`
unconditionally `PubSub.unsubscribe`es. The comment asserts ImageProcessor only
broadcasts `[:image, :error]` on its *final* attempt. **UNVERIFIED** — I could
not locate the broadcast site (`grep ":image, :error"` across `lib/` returns only
the two consumers, `upload_manager.ex:613` and this one; the producer is
presumably in an Oban worker under a name my greps missed).

If ImageProcessor ever broadcasts `:error` on an intermediate Oban attempt and
then succeeds on a retry, the form has already dropped the subscription and will
never see `[:image, :updated]`. User-visible: the image card pins on "Processing"
forever and the entry saves with an unprocessed image, with no error shown.

`upload_manager.ex:621` does the same thing, but that is pre-existing and the
manager at least sets `status: :error` in its UI. The form-side one is new and
silent (`{:cont, socket}`, "no UI to update for it").

**Action:** find the producer and pin the invariant with a test, or gate the
unsubscribe on the image's final-attempt state.

### W5 — the crop path subscribes after processing is already queued
`lib/brando_admin/components/form.ex:3547-3570`

Pre-existing, but it now interacts with the new unsubscribe. For
`params["crop_applied"]`, the controller queued processing *before* the form
subscribed (`:3550`), and the code compensates by re-fetching (`:3564-3570`).
That compensation covers "already processed by the time we look"; it does not
cover "processed a moment after we look, with the broadcast already gone". With
subscriptions now being torn down eagerly, any second, later round for the same
image id starts from no subscription at all unless it re-subscribes.

I verified the re-subscribe invariant holds for the paths I could reach:
`form.ex:3550`, `:3993`, `:4785` each sit immediately before a
`queue_processing` (or a controller-queued round), and per the coordinator's
correction there are six more in `deliver_asset/3`
(`hooks.ex:536, 556, 628, 653, 688, 717`) — **UNVERIFIED**, I did not read those
six. If any one of them subscribes *once* and expects to receive several rounds,
the `:processed` unsubscribe at `hooks.ex:429-431` will silently break it.

That is the single highest-value follow-up in this review: **audit all nine
subscribe sites for "one subscribe per processing round"**, which is the
invariant the new unsubscribe depends on.

---

## Checked and CLEAN

### `assign_new` conversions in `assign_addon_statuses/1` — `form.ex:1450-1464`
All five converted keys (`has_blocks?`, `has_revisioning?`,
`has_scheduled_publishing?`, `has_live_preview?`) derive from `schema` alone,
which is fixed for a component id. `has_meta?` and `has_alternates?` correctly
stayed plain `assign/3` for the reasons in the comment (`mount/1:98` seeds
`has_meta?: false`; `has_alternates?` reads `entry.id`, nil until create saves).

No `assign(:has_blocks?, …)` exists elsewhere in `form.ex` that `assign_new`
could shadow — `:1049` and `:1067` compute it into local variables only, and
`:3224` is a pattern match, not an assign. `handle_async(:entry_load, …)` reads
`socket.assigns.has_blocks?` at `:1107` *after* `finish_form_update()` has run
`assign_addon_statuses/1`. No KeyError.

### `assign_transformer_statuses/1` — `form.ex:1466-1481`
The split is correct and the guard is sound: `has_transformers?`,
`all_transformers_received?` and `transformer_changesets` are written only here
and in `reset_transformer_changesets/1` (`:4617-4622`), and both write all three
together. So the `%{assigns: %{transformer_changesets: _}}` early-return can
never leave `has_transformers?` unassigned. The scratchpad's framing (these are
state, not derived) is right, and re-seeding them on every parent re-render was a
real data-loss bug.

### Conditional `@fragments` / `@containers` / `@palette_options` — no KeyError path
Traced every read site:
- `@containers` — `render.ex:211` (`container/1` toolbar) and `:528`
  (`container_config`), both only inside `render(%{type: :container})`.
  `assign_new` condition is `type == :container or belongs_to == :root` → always
  true when read. ✅
- `@fragments` — `render.ex:278` and `:408`, both only inside
  `render(%{type: :fragment})`. Condition is `type == :fragment`. ✅
- `@palette_options` — `render.ex:209` and `:526`, same two container-only
  paths. ✅
- The receiving function components declare defaults anyway
  (`render.ex:327, 1094, 1143, 1144`), so even a miss would render empty rather
  than crash.

The keys are *always* assigned (to `[]` when out of scope), so there is no
"conditionally-assigned key read unconditionally" hazard. The residual risk is
staleness (W1), not absence.

Container children are passed `belongs_to={:container}` (`render.ex:257`) and get
a distinct component id (`"#{@id}-child-#{uid}"`, `:241`), so a child promoted to
root remounts and recomputes. No stale-`belongs_to` pinning across a move.
**UNVERIFIED**: I did not exhaustively confirm every move/drag path produces a
new component id.

### `connected?` gating in `block_field.ex` — `:653-684`
Correct. `connected?/1` on a LiveComponent socket reflects the parent LiveView,
which is what is wanted. The dead render's skipped subscribe cannot strand a
connected mount, because the connected mount is a **fresh process** where
`blocks_initialized` is absent, so `initialize_blocks/2` runs again and
subscribes (`:699-701`). `maybe_arm_blocks_topic/1` (`:641-649`) covers the
create-form case where `blocks_topic` was nil at init, and it routes through the
same gated `subscribe_to_blocks/1`. `request_blocks_sync/1` is gated on both
`blocks_topic` and `connected?`, so the dead render no longer makes every other
connected editor gather and broadcast its op store for a listener about to die —
a genuine saving that lands in *other* processes.

### `image_picker.ex` cache removal
`assign_config_target/1` (`:110-112`) resolves the target only; every
`assign_folder_state/2` call site (`:39, :64, :82, :180, :235`) re-queries via
`list_images/1` immediately, so dropping `socket.assigns.images` costs nothing
extra at those sites and removes a per-session copy of the whole library from
change tracking. The rendered list is already a stream (`:18`). The
`VideoPicker` asymmetry noted in the scratchpad checks out and was correctly left
alone.

One perf note, not a regression: `hooks.ex:322` fires
`send_update(ImagePicker, refresh_images: true)` on **every** `[:image, :updated]`
broadcast, which now always costs a full `list_images/1`. It did before too (the
cache was rebuilt there), so this is unchanged — but it means the picker
re-queries the whole config target on every image processed anywhere, opened or
not. Worth a `drawer_open?` gate as a follow-up.

---

## Pre-existing, one line each

- `lib/brando_admin/components/form/block.ex:1302` — `container_not_found` branch
  returns without assigning `:container` or `:palette_options`; any template that
  reaches it would KeyError.
- `lib/brando_admin/components/form.ex:3557-3570` — `crop_applied` subscribes
  after the controller queued processing; compensated only by a re-fetch.
- `lib/brando_admin/live/upload_manager.ex:621` — same unproven "final attempt"
  assumption as W4.
- `lib/brando_admin/components/form.ex:5556-5557` — `has_error/2` reads
  `field.errors` without `used_input?`, unlike its sibling clause.

---

## Recommended order of work

1. **W5** — audit the nine `"brando:image:<id>"` subscribe sites for the
   one-subscribe-per-round invariant. The new unsubscribe is load-bearing on it.
2. **W4** — find the `[:image, :error]` producer; confirm final-attempt-only.
3. **W1** — re-assign `:palette_options`/`:container_id` on container change.
4. **W2/W3** — correct both misleading comments; optionally narrow the two
   predicates to `type == :container` and re-measure.
