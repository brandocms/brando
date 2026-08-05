# Audit 03 — Media uploads, pickers, asset browser × form state & disconnect

Scope: `BrandoAdmin.UploadManager`, `Brando.Uploads` / `Brando.Uploads.AssetIntent` /
`Brando.Assets.ConfigTarget`, image/video/file/gallery inputs, block picture/video/gallery/file
refs, render_var vars, transformer, pickers, and the JS hooks
(`UploadManager`, `UploadTrigger`, `TransformerUploader`, provider video uploaders).

**Method**: read of every file cited below; no code executed, no browser session. Claims are
marked **verified** (read directly in this tree) or **inferred** (LiveView/Phoenix semantics
applied to code that was read).

---

## 0. TL;DR

The unified uploader is **actually built and largely coherent** — Phases 1–6 of `docs/UPLOADER.md`
all landed, `parent_uploads` is gone from the tree, and orphan-safe delivery is real for the
server transport. The remaining risk is concentrated in three places:

1. **Client-direct (S3) uploads have a genuine orphan hole** — bytes land in the bucket with no
   asset row and no reaper (§1.3).
2. **Picker *selection* is committed far later than picker *upload*** — an uploaded asset writes
   the FK immediately, a picked asset only writes it when the drawer is closed/submitted (§2).
   Different failure surface for what the user experiences as the same gesture.
3. **A handful of crash-on-missing-row and stale-assign bugs** in the video input and gallery
   inputs that take down the whole form LiveView (and therefore all unsaved work) (§B1, §B4).

Reconnect resilience is better than the doc implies: the entry-field path is recovered by
LiveView form recovery + an explicit drawer-recovery form. The *manager queue itself* is not.

---

## 1. Orphan-safe delivery (Q1)

### 1.1 The happy path — VERIFIED, and it is genuinely orphan-safe

Trace, server transport:

`assets/src/hooks/UploadTrigger/index.js:185` → `window.BrandoUploads.enqueue`
→ `assets/src/hooks/UploadManager/index.js:114` `pushEvent('intake')`
→ `lib/brando_admin/live/upload_manager.ex:65` `handle_event("intake")`
→ `AssetIntent.normalize/1` (`lib/brando/uploads/asset_intent.ex:55`)
→ `Brando.Uploads.initiate/4` (`lib/brando/uploads.ex:54`) size/ext/mime gate **before bytes move**
→ decision reply → JS tags file `"<ref>::<name>"` → `this.upload('queue', …)`
→ `upload_manager.ex:341` `handle_progress/3` → `:366` `consume_and_deliver/3`.

The ordering in `consume_and_deliver/3` is the load-bearing part and it is correct:

```elixir
# lib/brando_admin/live/upload_manager.ex:374-400
result =
  consume_uploaded_entry(socket, entry, fn meta ->
    case Uploads.store_upload(meta, clean_entry, cfg, user) do
      {:ok, asset} -> {:ok, asset}
      {:error, message} -> {:ok, {:upload_error, message}}   # always {:ok,_} so temp file is cleaned
    end
  end)
…
    deliver(item, asset)
```

`deliver/2` is a bare PubSub broadcast:

```elixir
# lib/brando_admin/live/upload_manager.ex:428-430
defp deliver(%{target: %{"deliver_topic" => topic} = target}, asset) when is_binary(topic) do
  Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:asset_ready, target, asset})
end
```

So: **the asset row exists before anyone is notified**, and notification cannot fail. The form
side additionally wraps delivery in a rescue:

```elixir
# lib/brando_admin/live_view/form/hooks.ex:481-491
defp safe_deliver_asset(target, asset, socket) do
  deliver_asset(target, asset, socket)
rescue
  error -> Logger.error("==> asset_ready: delivery failed … asset ##{asset.id} remains in the library")
end
```

and an unmatched target degrades to a debug log (`hooks.ex:726-732`). §7 of UPLOADER.md is
**implemented as specified** for the server transport. The doc is also honest that the planned
`:orphaned` status and "recent uploads" drawer list were never built — confirmed: no such status
in `upload_manager.ex`.

### 1.2 "User never saves" — accepted-by-design ORPHAN

The asset row is permanent; the FK lives only in the form changeset until save. If the user never
saves, the `Image`/`File`/`Video` stays in the library, unreferenced, forever. There is **no
GC for unreferenced assets** — `grep -rn orphan lib/` matches only `content/blocks.ex` (blocks)
and a comment in `upload_manager.ex`. This is the documented tradeoff, but it means a user who
uploads-then-abandons repeatedly silently grows the library. Worth an explicit product decision,
not a bug per se.

### 1.3 **ORPHAN (real, unhandled): direct-to-S3 completion after a manager remount**

`finalize_direct` is driven entirely from `socket.assigns.items[ref]`:

```elixir
# lib/brando_admin/live/upload_manager.ex:111-147
def handle_event("direct_complete", %{"ref" => ref}, socket) do
  case Map.get(socket.assigns.items, ref) do
    %{transport: :direct, status: :done} -> {:noreply, socket}   # replay guard, good
    %{transport: :direct, direct: direct} = item -> … Uploads.finalize_direct(…)
    _ -> {:noreply, socket}                                       # ← silently drops
  end
```

`mount/3` unconditionally assigns `items: %{}` (`upload_manager.ex:41`). If the manager process
dies (socket drop → rejoin, crash) while a presigned PUT is in flight, the bytes may still have
reached the bucket (the browser owns that XHR), but `direct_complete` arrives at a fresh process
with an empty `items` map and hits the `_ ->` clause. **The object exists in S3 with no `File`
row, no log line, and no reaper.** Contrast videos, which *do* have
`lib/brando/workers/video_upload_reaper.ex` for abandoned `:uploading` rows.

Mitigating: `UploadManager/index.js:98-104 destroyed()` aborts every `_directXhrs` entry, so the
window is narrow (disconnect without DOM teardown, e.g. brief network loss where the PUT
completes before the rejoin patch). Still: silent, unrecoverable, and invisible to ops.

**Fix direction**: log loudly in the `_ ->` clause; persist the pending-direct descriptor
(bucket key + resolved target + expected size/type) in a DB table or in the session-scoped
manager's `handle_params`-recoverable state, and add an S3 sweeper/reaper mirroring
`VideoUploadReaper` for keys with no `File` row.

### 1.4 ORPHAN (mitigated): provider video rows created before bytes move

`Videos.Uploader.initiate_upload` creates the `Video` row with `status: :uploading`
(`lib/brando/videos/uploaders/mux.ex:389`, `bunny.ex:242`, `cloudflare.ex:156`) *before* any
transfer. An aborted upload leaves the row. This **is** handled —
`lib/brando/workers/video_upload_reaper.ex:26-42` flips >24h `:uploading` rows to `:errored`
(deliberately not soft-delete, so late webhooks still resolve). Good; no action.

---

## 2. The user's scenario: asset in an open picker/drawer, not yet confirmed (Q2)

Where the state lives, per gesture:

| Gesture | Immediate destination | Survives form-LV death? |
|---|---|---|
| **Upload** into the image/file/video field drawer | entry changeset FK **immediately** (`form.ex:1166` `commit_entry_field_asset/4`) + DOM hidden input via `b:validate` | **Yes** (see §3.3) |
| **Pick existing** in ImagePicker/FilePicker/VideoPicker for a field | only `@edit_image` / `@image_changeset` in the Form live_component — **the entry changeset is NOT touched** | **No** |
| Upload into a block ref / var | BlockField op store (LV process memory) + block DOM inputs | partially (block recovery, §3.4) |
| Gallery add (upload) | `append_gallery_object/5` → entry changeset `put_assoc` (`form.ex:1196`) | via form recovery |
| Gallery add (pick) | `update_form_changeset/3` → Form `:update_changeset` (`gallery.ex:863`) | via form recovery |

The picker-select gap is the sharp edge:

```elixir
# lib/brando_admin/components/form/input/image.ex:305-336  handle_event("select_image")
send_update(BrandoAdmin.Components.ImagePicker, id: "image-picker", selected_images: [image.id])
send_update(BrandoAdmin.Components.Form, id: form_id, action: :update_edit_image, image: image)
```

`:update_edit_image` (`form.ex:217-229`) only assigns `edit_image` + `image_changeset`. The FK
reaches the entry changeset only in `handle_event("save_image", …)` (`form.ex:3903-3907`), which
fires because the drawer's close button dispatches a submit:

```elixir
# lib/brando_admin/components/form.ex:2909-2913
def close_image(js \\ %JS{}) do
  js
  |> JS.dispatch("submit", to: "#image-drawer-form", …)
  |> toggle_drawer("#image-drawer")
end
```

Consequences:

- **DATA-LOSS (medium)**: any drawer dismissal that is *not* the close button (LiveView patch that
  re-renders the drawer, a crash, navigating away, an Escape/click-away path that only toggles CSS)
  loses the picked asset. The uploaded asset in the same drawer would have survived. Two gestures,
  two durability classes, no user-visible difference.
- **BUG (low/medium)**: because close == submit, closing the image drawer always runs
  `Brando.Images.update_image/2` (`form.ex:3885`) and, if the image is not yet `:processed`,
  re-queues `Brando.Images.Processing.queue_processing/3` (`form.ex:3929-3931`) — a duplicate Oban
  job every time you peek into the drawer of a still-processing image.
- The same close-equals-submit shape exists for file (`form.ex:2903`) and video (`form.ex:2933`).

**Fix direction**: make `select_image`/`select_file`/`select_video` commit the FK through the same
`commit_entry_field_asset/4` chokepoint the upload path uses, and reduce `save_*` to metadata-only.

---

## 3. Sticky UploadManager across reconnect (Q3)

### 3.1 It does not survive a socket rejoin — **inferred (high confidence) + verified consequence**

`sticky: true` preserves a nested LiveView across `live_patch`/`live_navigate` only. A transport
rejoin re-mounts every LiveView on the page, sticky included. Verified consequence in code:
`mount/3` hard-assigns `items: %{}` / `order: []` (`upload_manager.ex:41-42`), so a remount
loses the whole queue — including the `target` maps that carry `deliver_topic`. `docs/UPLOADER.md`
§11.4 already concedes "hard-reload resilience out of scope".

- **In-flight server (`live_file_input`) uploads**: die with the process; LiveView GCs the temp
  file; no asset row; no notification. Correct, quiet, no orphan.
- **In-flight client-direct uploads**: see §1.3 — abort on `destroyed()`, but the completion race
  is an unlogged orphan.
- **External/provider uploads**: unaffected transfer-wise (the provider hooks own them), but the
  drawer rows vanish, so a long Mux upload loses its progress UI after a reconnect. The
  `external_track` clause guards against clobbering an existing item
  (`upload_manager.ex:163-168`) but there is no re-registration on remount.

### 3.2 The delivery target after a reconnect — **verified**

`BrandoAdmin.Components.Form.mount/1` generates a *fresh* topic on every mount:

```elixir
# lib/brando_admin/components/form.ex:59-63
deliver_topic = "form:" <> Ecto.UUID.generate()
if connected?(socket) do … Phoenix.PubSub.subscribe(Brando.pubsub(), deliver_topic) end
```

So even in the (impossible today) case where the manager survived and the form did not, delivery
would land on a dead topic. Symmetrically, an upload started on entry A and then `live_navigate`
to entry B delivers to A's now-unsubscribed topic — the asset stays in the library with no user
feedback (the drawer cannot know; the doc admits there is no feedback channel,
`upload_manager.ex:432-436` only logs at `:debug`).

**Fix direction (cheap, high value)**: when `deliver/2` broadcasts, also check
`Phoenix.PubSub`/Registry for subscribers, or have the form ACK; on no-ACK, flip the drawer item
to a terminal "saved to library — click to open" state instead of `:done`. That was the original
§7 "recent uploads" idea; it is still the missing half of orphan-safety *as UX*.

### 3.3 What **does** survive a reconnect for entry fields — **verified, good news**

Two independent mechanisms:

1. **LiveView form recovery.** `commit_entry_field_asset/4` pushes a targeted `b:validate` that
   writes the value into the DOM hidden input:
   ```elixir
   # lib/brando_admin/components/form.ex:1185-1188
   |> push_event("b:validate", %{target: "#{socket.assigns.singular}[#{relation_key}]", value: asset.id})
   ```
   handled at `assets/src/hooks/Form/index.js:21-33` (`target.value = opts.value`). The hidden
   relation input lives inside the main `phx-change="validate"` form
   (`input/image.ex:363`, `input/file.ex:224`, `input/video.ex:301`), so rejoin replays it into
   `handle_event("validate", …)` (`form.ex:2976`).
2. **Explicit drawer recovery.** A dedicated hidden form with
   `phx-auto-recover="recover_drawer_state"` (`form.ex:2033-2046`) restores
   `edit_image`/`edit_video`/`edit_file` + reopens the drawer
   (`form.ex:6017-6099`, `assign_drawer_recovery_state/1` at `:6101`).

Caveat: `entry_field_upload_complete` sets `editing_image?: false` (`form.ex:599`, and `:576`,
`:613` for file/video), which clears the recovery descriptor — so an upload finishing into an
*open* drawer leaves the drawer visually open but no longer recoverable. Minor **BUG**.

### 3.4 Blocks

Block refs/vars recover through `handle_event("recover_blocks", …)`
(`lib/brando_admin/components/form/block_field.ex:1140-1206`), which re-casts DOM params. Not
exhaustively traced here; flagged as *probably covered*, worth a dedicated e2e (upload into a
block ref → kill socket → verify `image_id` survives).

---

## 4. Selection semantics — "mark the unsaved value, not the DB value" (Q4)

Entry fields: **all three read the changeset, not `entry.field_id`** — verified.

- image: `image_id = changeset |> get_field(relation_field_atom)` (`input/image.ex:71`), passed to
  the picker at `input/image.ex:279`.
- file: `get_field(changeset, relation_field_atom)` (`input/file.ex:52-55`) → `input/file.ex:170`.
- video: `get_field(changeset, relation_field_atom)` (`input/video.ex:52-55`) → `input/video.ex:218`.
- All three re-push the new selection after a pick (`image.ex:312`, `file.ex:192`, `video.ex:251`).

**CONTRACT violations found (two sites open the picker with an empty selection):**

1. `lib/brando_admin/components/form/input/blocks/render_var.ex:1357-1367` — the **image var**
   picker:
   ```elixir
   def handle_event("set_target", _, %{assigns: %{myself: myself}} = socket) do
     …
     selected_images: []
   ```
   `socket.assigns.image_id` exists (set at `render_var.ex:76`, `:261`, `:1467`) and the sibling
   handlers do it right — `set_file_target` uses `if(socket.assigns.file_id, …)`
   (`render_var.ex:1381`) and `set_video_target` uses `socket.assigns.video_id`
   (`render_var.ex:1396`). Straight inconsistency.
2. `lib/brando_admin/components/form/input/blocks/video_block.ex:523-536` — the video block's
   **cover-image** picker also passes `selected_images: []` while `socket.assigns.cover_image` is
   known. It additionally passes the *video* block's `config_target` to the **ImagePicker**
   (`video_block.ex:527`), which `ImagePicker.resolve_config_target/1` (`image_picker.ex:113-120`)
   rescues down to `"default"` — so the cover picker silently browses the default image library
   rather than a cover-specific one.

Also: `Input.Gallery` derives `selected_images`/`selected_videos`/`gallery_objects` with
`assign_new` (`input/gallery.ex:149-155`, duplicated at `input/gallery_objects.ex:38-42`) — they
are computed once and never re-derived from the changeset. Any changeset change that does not go
through this component's own handlers (remote field sync, `update_changeset`, a reset) leaves the
picker marking a stale set. **BUG**, medium.

---

## 5. Contract violations (Q5)

### 5.1 CONTRACT — hand-built config-target string, with the wrong schema

```elixir
# lib/brando_admin/components/form.ex:382-387
# The upload strategy + provider settings come from `get_config_for/1` below.
config_target = "video:#{inspect(schema)}:#{field}"
case Brando.Videos.get_config_for(config_target) do
```

`schema` here is `socket.assigns.schema` — the **entry** schema — while the very same drawer's
`UploadTrigger` correctly uses `Map.get(@edit_video, :schema) || @schema`
(`form.ex:2774-2779`) and `ConfigTarget.serialize/1`. For a video field on a *nested/subform*
relation module, the provider (Mux/Bunny/Cloudflare) path therefore builds a config target for
the wrong schema → `get_config_for` fails → `video_upload_url_error` and no upload. The local/S3
path (which goes through the trigger) works. **BUG + CONTRACT.**

`lib/brando_admin/components/video_picker.ex:1118-1124` `normalize_video_config_target/1` also
hand-formats `"video:#{inspect(schema)}:#{field}"`, but only as a tuple→string shim; it is
consistent with `ConfigTarget.serialize/1` output. Lower priority, still should delegate.

### 5.2 CONTRACT — the gallery picker commits to a form id derived from the wrong module

```elixir
# lib/brando_admin/components/form/input/gallery.ex:863-874
defp update_form_changeset(changeset, field_name, new_gallery) do
  updated_changeset = put_assoc(changeset, field_name, new_gallery)
  module = changeset.data.__struct__
  form_id = "#{module.__naming__().singular}_form"
  send_update(BrandoAdmin.Components.Form, id: form_id, action: :update_changeset, …)
```

For a gallery on a nested subform, `changeset.data.__struct__` is the *nested* module, so
`form_id` names a component that does not exist → `send_update` no-ops → **picking images into a
nested gallery is silently discarded**. The upload path for the same field does it correctly via
`path` (`hooks.ex:685-704` → `form.ex:618-667` → `append_gallery_object/5` at `form.ex:1196`).
**BUG (medium) + CONTRACT.** Same shape in `gallery_objects.ex`.

It also `put_assoc`es onto a snapshot of `field.form.source`, so two rapid picker clicks can
clobber each other (the upload path was explicitly serialized with a 25 ms queue for exactly this
reason — `hooks.ex:444-477`).

### 5.3 Everything else is clean — verified

- All UploadTrigger render sites pass through `AssetIntent.normalize/1` at intake
  (`upload_manager.ex:66`); malformed kind/asset-type/path/topic/ref are rejected
  (`asset_intent.ex:58-72`), path segments and field names resolve through
  `String.to_existing_atom` only.
- Block refs go through `Block.commit_ref_data/2` everywhere (`picture_block.ex:61,92,375,385`,
  `video_block.ex:69,88,497…`, `gallery_block.ex:53,84,118,128,376,440`, `file_block.ex:184,193`).
  `commit_ref_data/2` is a pure `send_update` that returns the socket unchanged
  (`block.ex:2306-2316`), so the call sites that discard its return (e.g. `gallery_block.ex:376`)
  are harmless.
- `Transformer` uses `ConfigTarget.serialize/1` on both media (`transformer.ex:305,309,907`) and
  is the only caller that threads the client `ref` correlation token
  (`TransformerUploader/index.js:246`).
- Direct-transport finalize never trusts client keys — key + resolved target are read from
  server-side item state (`upload_manager.ex:120-133`, comment at `:275`).

---

## 6. Gallery per-type configuration (Q6) — **no leakage found, verified**

- Normalizer: `lib/brando/blueprint/asset_config_normalizer.ex:153-182`. A `%{image: …, video: …}`
  config merges each side against its own defaults; a `%{image: …}`-only config gives video the
  *defaults* (`:169`); a legacy flat config applies **only to image** (`:180-182`,
  `%{defaults | image: …}` leaves `video` at defaults). No path copies image keys into video.
- Resolution is per-context: `Brando.Images.ConfigResolver` picks `gallery_image_config/1`
  (`config_resolver.ex:88`), `Brando.Videos` picks `gallery_video_config/1`
  (`lib/brando/videos.ex:179-180`, `:230-231`).
- Call sites pass one `"gallery:Schema:field"` target for both media and let the server split it
  (`input/gallery.ex:167` image trigger vs `:308` video trigger, both `@config_target`) — correct
  by construction.
- Block galleries keep the split explicit (`gallery_block.ex:181-200`, `image_config_target` /
  `video_config_target` with `compatible_gallery_target/2` refusing cross-media targets).

One nit: `normalize_gallery_config(asset, %{video: video} = config, defaults)`
(`asset_config_normalizer.ex:173-178`) is the only clause that does **not** call
`ensure_gallery_keys!/2`, so `%{video: …, size_limit: 1}` silently routes `size_limit` to the
image config instead of raising like every sibling clause. Consistent with "legacy flat = image",
inconsistent with its own validation contract. **Low.**

---

## 7. Idiomatic Elixir / LiveView + efficiency (Q7)

**B1 — BUG (high): `{:ok, video} = …` in `Input.Video.update/2` crashes the form LiveView.**
`lib/brando_admin/components/form/input/video.ex:64, 74, 90, 117` all hard-match:
```elixir
{:ok, video} = Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]})
```
A deleted-but-still-referenced video, or line `:90` where `video_id` may be `nil` after
`EctoNestedChangeset.get_at/2`, raises `MatchError` → the whole entry form LiveView dies →
**all unsaved work lost**. `Input.Image` does the same lookup defensively with `case`
(`input/image.ex:147-158`). Fix: mirror the image input.

**B2 — dead code: `handle_info/2` on a LiveComponent.** `input/video.ex:278-280` defines
`handle_info({video, [:video, :updated]}, socket)`, which LiveComponents never receive. The
`maybe_subscribe/2` at `:133-139` subscribes the *parent LiveView*, whose
`handle_hooks_video_info/2` (`hooks.ex:767`) handles it — so the behaviour works by accident and
the component's own handler is unreachable. Delete it, and note the subscription is never
unsubscribed as `video_id` changes (leaks one subscription per distinct video per form).

**B3 — `Brando.Repo` hardcoded** in `image_picker.ex:599` (`Brando.Repo.update_all`) instead of
`Brando.repo()`, unlike the rest of the tree.

**B4 — assigns bloat / unbounded list.** `ImagePicker.assign_images/1`
(`image_picker.ex:93-106`) loads **every** image for the config target into `:images` with no
limit, then streams only the current folder's subset (`:510-534`). `VideoPicker.assign_videos/1`
(`video_picker.ex:104-110`) does the same with `preload: [:thumbnail, :file]`. On a large library
that is a full-table read plus a permanently retained list in the picker component's assigns, on
every open, refresh and folder change. **PERF (medium).** Fix: paginate/filter server-side, or at
least keep only `id`+`path` for folder derivation.

**B5 — inline style** at `video_picker.ex` upload-progress bar
(`style={"width: #{@upload_progress.percentage}%"}`), against the project's no-inline-styles rule.
Use a CSS custom property set via a class + `--progress`.

**B6 — validation-only clauses that can crash.** `handle_event("validate_image", %{"image" => …})`
(`form.ex:3785-3793`) calls `change(socket.assigns.edit_image.image)`; if `edit_image.image` is
`nil` and image params are present, `change(nil)` raises. Currently unreachable because the
metadata inputs render under `:if={@edit_image.image}`, but it is one template edit away.
`validate_file`/`validate_video` (`form.ex:3667`, `:3965`) already guard with `|| %Struct{}`.

**B7 — DUPLICATION.** `input/gallery.ex` and `input/gallery_objects.ex` are near-duplicate
implementations of the same gallery-object list (compare `gallery.ex:149-155` /
`gallery_objects.ex:38-42`, `gallery.ex:856-874` / `gallery_objects.ex:300-310`); both carry the
same `assign_new` staleness bug and the same wrong-form-id bug. The three `deliver_asset/3`
entry-field clauses (`hooks.ex:646`, `:684`, `:706`) and the three
`entry_field_upload_complete` clauses (`form.ex:565`, `:579`, `:602`) also differ only by which
drawer assigns they touch — a `{asset_type, drawer_key}` table would collapse them.

**B8 — PubSub chattiness.** Per-image subscriptions are created in five places
(`upload_manager.ex:404`, `hooks.ex:511, 531, 603, 628, 663, 692`) and unsubscribed in exactly
one (`upload_manager.ex:451, 466`, manager only). The *form* LiveView never unsubscribes from
`"brando:image:<id>"`, so a long editing session accumulates subscriptions linearly with uploads.
The manager comment at `:449-451` shows the author already knew this pattern was needed; apply it
form-side too.

**B9 — good, keep.** `allow_upload` options in `upload_manager.ex:45-54` are correct: intake is
authoritative and `max_file_size` is deliberately the transport envelope
(`Uploads.manager_max_file_size/0`, `uploads.ex:408-411`), with the reasoning captured in a
comment. `validate_queue` (`upload_manager.ex:75-97`) sweeps errored entries and releases JS
transfer slots — this is the kind of slot hygiene §5.2 of the doc asks for.

**B10 — authorization.** `handle_event("intake", …)` rejects only `current_user == nil`
(`upload_manager.ex:61`). There is no per-target permission check: any authenticated admin can
create an asset under any `config_target`. Probably acceptable for this product, but it is the
one place the Iron Law "AUTHORIZE in EVERY handle_event" is satisfied only by authentication.
`direct_progress` / `external_*` / `cancel_item` / `dismiss_item` have no user check, but they
only mutate the caller's own socket state.

---

## 8. Migration status (Q8) — **Phases 1–6 all landed; verified against the delete list**

`docs/UPLOADER.md` §10 "Delete list (grep anchors)" — every anchor is gone:

```
grep -rn "parent_uploads|register_block_upload|handle_block_image_progress|:block_uploads|
          register_var_upload|handle_var_upload_progress|var_upload_complete|:var_uploads|
          maybe_register_var_upload|handle_image_progress|handle_file_progress|
          handle_gallery_progress|handle_video_progress|maybe_send_upload_next_file|
          upload_folder_targets|QueuedUploader|BlockUpload" lib/ assets/src/
→ zero functional hits (only `allow_uploads:` the VideoConfig *field*, and comments)
```

Remaining `allow_upload` registrations in the tree (verified, all legitimately out of the
migration's scope):

| Site | Purpose |
|---|---|
| `lib/brando_admin/live/upload_manager.ex:45` | the manager itself |
| `lib/brando_admin/components/form.ex:2947` (`allow_uploads/1` at `:2941`) | `:image_editor_upload` only — the image editor's "save as new copy"; the function's own comment states this |
| `lib/brando_admin/live/images/image_list_live.ex:19` | standalone media-library list LV |
| `lib/brando_admin/live/files/file_list_live.ex:20` | standalone media-library list LV |

Legacy non-LiveView routes still present: `BrandoAdmin.API.Images.UploadController` and
`BrandoAdmin.API.Villain.VillainController` (`lib/brando/router.ex:44-45`). These are the
pre-LiveView multipart POST endpoints referenced in §2.4 as "prior art"; the doc never scheduled
them for deletion. Worth confirming whether anything still calls them (nothing in `lib/` does) —
if not, they are dead attack surface.

Also surviving: `maybe_override_image_upload_path/2` at
`lib/brando_admin/live/images/image_list_live.ex:333-335`. The doc's Phase 4 note says the
*form-side* copy was deleted; the list-LV copy is a different one and the manager has its own
equivalent (`upload_manager.ex:549-556`). Three implementations of "resolve a folder into an
upload path" now exist — candidate for consolidation.

Known gap the doc itself records and I confirmed is still open:
`maybe_resolve_dynamic_upload_path` (upload_path as a function in asset opts) is **not honored**
by the manager path for gallery fields — no such function exists anywhere in `lib/` anymore.

Repo memory said "Phase 2/3 may still be open" — **that is stale**. Phase 2 (files → S3 direct)
is implemented (`uploads.ex:284-374`) and Phase 3 (block refs) is implemented
(`picture_block.ex:200`, `gallery_block.ex:225`, `file_block.ex:102` triggers +
`hooks.ex:525-642` delivery). The one thing Phase 2 still lacks is production verification and
the bucket CORS prerequisite, per the doc header.

---

## 9. Ranked findings

| # | Class | Where | One-line fix |
|---|---|---|---|
| 1 | **BUG (high)** | `input/video.ex:64,74,90,117` — `{:ok, v} = get_video(...)` MatchError kills the form LV and all unsaved work | replace with `case`, mirroring `input/image.ex:147` |
| 2 | **DATA-LOSS (medium-high)** | Picker *select* for entry fields commits only via drawer submit (`input/image.ex:305`→`form.ex:3903`), unlike upload which commits at `form.ex:1166` | route `select_*` through `commit_entry_field_asset/4`; make `save_*` metadata-only |
| 3 | **ORPHAN (medium-high)** | `upload_manager.ex:145` `_ -> {:noreply, socket}` — direct-S3 completion after a manager remount leaves a bucket object with no `File` row, unlogged, no reaper | log + persist pending-direct state + add an S3 sweeper à la `VideoUploadReaper` |
| 4 | **BUG (medium)** | `input/gallery.ex:863-866` derives `form_id` from the *nested* module → picking into a nested gallery silently no-ops (same in `gallery_objects.ex`) | pass the real `form_id`/`path` like the upload delivery does (`form.ex:1196`) |
| 5 | **BUG/CONTRACT (medium)** | `form.ex:385` `"video:#{inspect(schema)}:#{field}"` uses the entry schema, not `edit_video.schema` → provider video upload broken for nested video fields | `ConfigTarget.serialize({"video", Map.get(edit_video, :schema) \|\| schema, field})` |
| 6 | **BUG (medium)** | `input/gallery.ex:149-155` + `gallery_objects.ex:38-42` `assign_new` never re-derives gallery state from the changeset | recompute on every `update/2` |
| 7 | **CONTRACT (medium)** | `render_var.ex:1366` and `video_block.ex:534` open the image picker with `selected_images: []` despite knowing the current id | pass the current `image_id` / `cover_image.id` |
| 8 | **PERF (medium)** | `image_picker.ex:93-106`, `video_picker.ex:104-110` load the entire library into assigns on every open/refresh | paginate / select minimal columns |
| 9 | **BUG (low-medium)** | `form.ex:3929` re-queues image processing on every drawer close; `form.ex:599` clears `editing_image?` on upload-complete, defeating drawer recovery | guard the re-queue; keep the drawer descriptor while it is open |
| 10 | **UX/ORPHAN feedback (medium)** | delivery is fire-and-forget with no ACK (`upload_manager.ex:428`); an upload delivered to a dead form vanishes silently | ACK from the form; drawer shows "saved to library" when unacknowledged |
| 11 | **PERF (low-medium)** | form-side `"brando:image:<id>"` subscriptions never unsubscribed (`hooks.ex:511,531,603,628,663,692`) | unsubscribe on `:processed`, as the manager does at `:451` |
| 12 | **DUPLICATION (low)** | `gallery.ex`↔`gallery_objects.ex`; the 3× entry-field delivery clauses (`hooks.ex:646/684/706`, `form.ex:565/579/602`); 3× folder→upload-path helpers | extract a shared gallery module; table-drive the delivery clauses |
| 13 | **Low** | `asset_config_normalizer.ex:173` skips `ensure_gallery_keys!/2`; `image_picker.ex:599` hardcodes `Brando.Repo`; `input/video.ex:278` dead `handle_info`; `video_picker.ex` inline style; `router.ex:44-45` legacy POST upload controllers | mechanical cleanups |
