# LiveView correctness review — Phase 2 (commits cfb3639fc, d852ec7ef, a3f8a7d35)

Scope: D2 (deliver-topic handshake), D5 (gallery merge), D4-adjacent `put_gallery`,
D7 (`editing_image?`/`editing_file?`). New code only.

## 1. D5 — `merge_loaded_media` re-derivation vs. the bespoke direct-assign clauses: REAL disagreement found

`input/gallery.ex` has THREE ways `gallery_objects` gets written, and only one
(`assign_value/1`, the catch-all `update/2` clause) goes through
`Brando.Galleries.merge_loaded_media/2`. The other two bypass it entirely:

- `%{new_image:, selected_images:}` (`gallery.ex:73-81`) and its video twin
  (`:103-111`) — sent from `form.ex`'s `entry_field_upload_complete` clause
  (`:605-609`, `:649-653`) — do `assign(:gallery_objects, gallery_objects ++ [new_image])`,
  an unconditional, non-idempotent append to whatever the PREVIOUS assign held.
- `%{action: :update_image, force_validation: true}` (`:83-96`, sent from
  `hooks.ex:302/386` on Oban processing completion) patches `:image` in place by
  matching `image_id` in the current assign — again bypassing the changeset.

**The bug:** in the same `entry_field_upload_complete` handler, `form.ex` does
BOTH `send_update(Gallery, new_image: ..., selected_images: ...)` (queued) AND
`append_gallery_object/5` → `put_gallery_at/4` → `assign(:form, ...)` on itself
(`form.ex:1235`, `:1257`), which changes the `field` prop the Gallery
live_component receives from its parent's next render. Both trigger `update/2`
calls on the *same* Gallery component for the *same* event, and the new image is
already present in the changeset (`append_gallery_object` builds the new
object as an unslimmed map carrying `:image`, so `get_field(changeset, ...)`
returns it with the association already loaded — `loaded_media?/1` is true,
`merge_loaded_media/2` returns it as-is, no duplication from that side alone).
If the changeset-driven `assign_value` update runs *after* the `new_image:`
clause's raw append (order between an explicit `send_update` and a
parent-template-driven reassignment is not guaranteed by anything in this code),
`gallery_objects` ends up as `[...changeset_list_incl_new..., new_image]` —
**the new image duplicated in the UI-only assign**, persisting until some
unrelated future update forces `assign_value` to re-derive from the changeset
again (which naturally de-dupes, since it maps 1:1 over the changeset's list).
Until then, two thumbnails render for one DB row.

**A second, subtler disagreement:** `merge_loaded_media/2`
(`lib/brando/galleries.ex:101-109`) decides per-object whether to keep the
changeset's own value or borrow from the cache purely on `loaded_media?/1`
(association loaded, not: *freshness*). The `action: :update_image` clause
exists specifically to push a freshly-processed image (new `status`,
`formats`, etc.) into the cache after Oban finishes. If the changeset's own
`gallery_objects` entry *already* carries a loaded (but stale — pre-processing)
`:image` — which it will, since nothing else touched that gallery field in the
meantime — `loaded_media?` is true and `merge_loaded_media` keeps the
changeset's stale copy, **discarding** the just-applied fresh one on the very
next unrelated update to that component. The processed-image swap is therefore
transient: it survives only until the next update cycle re-derives, which
silently reverts the thumbnail/status to its pre-processing state.

Both are genuine "can disagree" cases, not pre-existing (the merge logic and
the direct-assign clauses are new/changed together in this diff). Neither is
caught by the D5 tests described in the plan (`gallery_test.exs`), which test
`merge_loaded_media/2` and the generic `update/2` clause in isolation, not the
interaction between it and the `new_image`/`action: :update_image` clauses
under concurrent `send_update` + parent-reassignment.

One-liner, pre-existing: `commit_gallery/4` (`gallery.ex:685-700`) also writes
`assign(socket, :gallery_objects, gallery_objects)` directly (the raw
add/remove result, not through merge) — same class, not part of this diff.

## 2. D2 — client-owned deliver-topic handshake

- **`pushEventTo(this.el, ...)` reaching the LiveComponent**: correct as
  documented. `phx-hook="Brando.Form"` sits on the component's own root node,
  which LiveView stamps with `data-phx-component`, so `pushEventTo` targeting
  that same element resolves to the Form LiveComponent, not the parent
  LiveView — consistent with the `BlockField` precedent cited in the comment.
- **Race: upload starting before the server has (re)subscribed** — real, and
  not limited to remounts. On a form's *very first* mount for an entry with no
  prior `sessionStorage` entry, the server has already subscribed to its own
  mount-minted topic (`form.ex:62-73`, before the page even reaches the
  client). The hook then unconditionally mints a *different* client topic and
  asks the server to switch (`claimDeliverTopic`, `index.js:147-166`) — so
  every fresh page load, not just every remount, makes the server tear down a
  perfectly good subscription and move to a new one via one extra round trip.
  Delivery during that window (upload started before `set_deliver_topic` is
  processed) goes to the client's chosen topic while the server is still
  subscribed to the old one — same silent-drop shape D2 fixes for remounts,
  reopened for first loads. Narrow in practice (a multipart upload takes far
  longer than one websocket round trip), but the code gives no ordering
  guarantee against it.
- **Optimistic `dataset.deliverTopic` write vs. morphdom — genuine gap, and it
  is the exact anti-pattern this repo's own CLAUDE.md names**: `index.js:162`
  does a plain `this.el.dataset.deliverTopic = topic` (not routed through
  `this.js()`/sticky commands). `data-deliver-topic={@deliver_topic}` is also
  server-rendered (`form.ex:1901`) from the *old* assign value until
  `set_deliver_topic` is processed and `assign(socket, :deliver_topic, topic)`
  runs. If **any other** re-render of the Form component happens in that
  window — and this codebase explicitly documents "high-frequency Presence
  diffs" hitting this same component (Phase 3 finding E, `page_form_live.ex:23`)
  — LiveView's morphdom pass reconciles the element using the last-known
  server HTML, which still has the *old* topic, and reverts the manual DOM
  mutation. If an upload trigger reads `data-deliver-topic` off that element
  after the revert but before the server's own confirming re-render lands, it
  captures the stale topic — silently, since a broadcast to a topic nobody
  (yet) subscribes to returns `:ok`. This is not hypothetical-only: the
  project's own AGENTS.md documents this exact class of failure ("plain
  classList/setAttribute mutations are wiped on the next morphdom pass") as a
  known footgun requiring the sticky-JS pattern, and this write does not use it.
- **`destroyed()` and PubSub**: does not need to unsubscribe, and doesn't —
  correctly. The subscription lives server-side, tied to the LiveComponent's
  owning process; it dies with that process. No bug here.

## 3. `Form.update(%{action: :put_gallery, ...})`

Single write point (`put_gallery_at/4`) for both the upload path
(`append_gallery_object/5`) and the picker path (`Gallery.update_form_changeset/2`
→ `Form.update(:put_gallery)`), addressed via `@form_id` threaded from
`Form.input/1` with a form-name-root fallback documented as covering only
out-of-pipeline mounts. Looks correct and matches D4's stated fix. One
pre-existing, not-introduced-here oddity: `entry_field_upload_complete`'s
`component_id = Map.get(params, :component_id) || "#{socket.assigns.singular}_#{key}"`
(`form.ex:602`, `:630`) still carries the OLD schema/singular-based fallback
`Input.Gallery`'s own `entry_form_id/1` just replaced for the same reason (D4) —
harmless only because `component_id` in practice always arrives from the
client's `data-component-id={@id}` attribute (the real id), making the fallback
dead in normal use; flagging so it isn't copied forward as a template.

## 4. `editing_image?`/`editing_file?` truthfulness — verified correct

Checked whether any UI path can close the drawer without going through a
handler that clears the flag. `Content.drawer` (`content.ex:35-79`) has **no**
Esc/backdrop/click-away dismissal — the only close affordance is the header's
`phx-click={@close}` button, and both `close_image()`/`close_file()`
(`form.ex:2931-2941`) dispatch a `submit` on the drawer's own form before
toggling visibility, which always reaches `save_image`/`save_file` (or their
no-params fallback, `:4033`) — all of which now clear the flag, matching D7's
claim. `reset_image_field`/`reset_file_field` (`:3691-3745`) clear it too, as
stated. `entry_field_upload_complete`'s shared `deliver_entry_field_asset/5`
(`:1163-1182`) does not touch the flag, also as stated, and correctly — an
upload started inside an open drawer should leave it open. No bypass path
found; D7's claim holds for every currently reachable path.

## Not investigated (turn budget)

- Whether the D5 duplication race is actually observable in practice (depends
  on Phoenix's real ordering of a `send_update`-queued update vs. a
  parent-template-triggered one for the same cid within one diff pass — not
  verified against `deps/phoenix_live_view` source in this pass).
- `video.ex`/`file.ex` equivalents of the D5 merge pattern, if any exist outside
  `gallery.ex`/`gallery_objects.ex`.
- Full trace of `gallery_block.ex`'s own `image_editor_new_copy` clause
  (`:88`) against the same disagreement shape.
