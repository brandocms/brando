# Brando Unified Uploader — design & migration plan

> Status: **Phases 1–2 implemented (2026-07-05).**
> Phase 1 verified end-to-end — block file/image *vars* run through the sticky
> `BrandoAdmin.UploadManager`; measured 4 MB var upload: ~7 s, 4 diffs to the manager +
> 8 small diffs to the form (was ~106 s with ~64 full-tree re-renders). Also fixed the
> var-commit persistence bug (`update_var_in_changeset` wrote to changeset *data*, not
> *changes* — upload/pick followed directly by save was silently lost).
> Phase 2 (files → Spaces client-direct presigned PUT) implemented + unit-tested;
> opt-in per site via `cdn: %Brando.CDN.Config{enabled: true, direct: true}` on
> `Brando.Files`. Not yet live-verified — needs prod-like S3 credentials
> (`Brando.CDN.S3Config`) and the bucket CORS PUT rule (§9). Configs with
> `content_disposition` stay on server transport by design.
> Phase 3 (block refs: picture + gallery) implemented 2026-07-05 — `UploadTrigger`
> everywhere, `register_block_upload`/`handle_block_image_progress`/`:block_uploads`/the
> `BlockUpload` JS hook deleted. The folder browser is wired into the manager path
> (trigger opens it, confirmed folder/folder_id ride the intake target) — this also
> restored folder choice for image *vars*. Delivery timing: picture refs get their
> image_id at processed (via the existing `pending_block_image_updates` machinery),
> galleries add the id immediately and swap in the processed struct.
> Future idea: move the folder browser UI itself into the sticky manager (currently
> it's the form-mounted ImagePicker's browser; triggers outside forms fall back to
> the default folder).
> Transfer concurrency is configurable (added 2026-07-05):
> `config :brando, Brando.Uploads, max_concurrent_transfers: N` (default 3, set 1 for
> sequential). Enforced by the manager hook's client-side scheduler for both server
> uploads and direct PUTs; server slots release via a `b:uploads:released` push at
> consume. Processing concurrency remains governed by the `:image_processing` Oban
> queue limit + `:concurrent_image_jobs`.
> Phase 4 implemented for **file + image fields** (2026-07-06), both verified
> end-to-end incl. save persistence (Brand.font_body → DB, Brand.logo_top → DB with
> folder browser + config upload path). Target kind `entry_field` (field + JSON path
> in the trigger dataset); delivery via `entry_field_upload_complete` on the Form
> component. The commit mimics `save_file`: fresh changeset + `EctoNestedChangeset`
> FK write, asset struct onto the entry ASSOC only (never the `_id` column or the
> save cast diffs empty), targeted `b:validate` push (`%{target, value}`) because
> Input.File/Image render the hidden relation input from the assoc, and clearing
> `editing_file?`/`editing_image?` — the save handler REJECTS saves while a drawer
> is open, which masked everything during testing. Deleted: image/file `allow_upload`
> reduces, `handle_image_progress`, `handle_file_progress`, the old `external:`
> presign path, `maybe_send_upload_next_file`, form-side
> `maybe_override_image_upload_path`. Processed-image updates reach entry fields via
> the existing `"image:Schema:field"` config-target routing.
> **Gallery fields also migrated + verified (2026-07-06)** — new kind
> `entry_field_gallery`, delivery appends to the gallery assoc via the logic lifted
> from the old `handle_gallery_progress` success branch (`put_assoc` + `sequence`,
> picker selected_images + Gallery input updates); `handle_gallery_progress`,
> the gallery `allow_upload` reduce and the input's `parent_uploads` guard/errors
> deleted. Verified on a `test_gallery` asset added to brand_guide_lite's Brand
> (2 parallel uploads → folder browser → save → gallery + 2 objects in DB).
> Note: `maybe_resolve_dynamic_upload_path` (upload_path as function in asset opts)
> was dropped with the old handler — dynamic upload paths for gallery fields are
> not honored by the manager path yet.
> **Phase 4 COMPLETE except video fields (Phase 5).**
> Phase 5 COMPLETE (2026-07-06):
> (a) **Mux/Bunny uploads surface in the manager drawer** —
> `window.BrandoUploads.trackExternal/externalProgress/externalComplete/
> externalError` (visibility only; provider hooks keep owning transfer + delivery;
> no cancel for external items). Verified via simulated lifecycle.
> (b) **Local video storage FIXED** — `handle_upload_type` gained a VideoConfig
> clause (was falling into the generic image path): stores the file, creates a
> `Video{type: :upload, status: :ready}` wrapping it; `Files.get_config_for` now
> resolves `"video:"` targets so wrapped-file URLs resolve through the video
> asset's cfg. Regression-tested (`test/brando/videos/upload_test.exs`).
> (c) **Local video fields migrated to the manager** — video drawer's :local
> branch renders an UploadTrigger (`asset_type: "video"`); delivery clause
> mirrors file fields; video `allow_upload` reduce + `handle_video_progress`
> deleted. Verified in-browser (Brand.test_video: upload → save →
> Video{upload,ready} + wrapped File in DB).
> **Phase 6 COMPLETE (2026-07-06): `parent_uploads` threading DELETED** — zero
> occurrences remain in the tree (form.ex, block/render.ex, block_field, subform*,
> fieldset*, meta_drawer, transformer, villain components, all inputs, the
> module-code allowed-assigns list). The `:__dfu__` placeholder upload is gone;
> `allow_uploads/1` registers only `:image_editor_upload`. The image input no
> longer passes `upload_name`/`drop_target` to the ImagePicker (nil → the picker
> hides its field-upload button; uploads go through the drawer trigger).
> Verified: 62-block editor renders and uploads normally; a var upload produced
> 3 manager diffs + 4 small form diffs total. **The migration is complete** —
> no upload can re-render the editor tree, ever.
> **E2E: full suite green (74/74, 2026-07-06)** after: sandbox on_mount for the
> manager; folder browser on drop only (old semantics); deliver-before-processing
> + already-processed forwarding (inline-Oban/fast-queue race); gallery delivery
> serialization (25ms queue); GalleryBlock image_processed stale-pin guard;
> crash-proof config resolvers (rescue → default — note: ref:* targets must keep
> STORING "default", the picker queries by it); spec selectors updated for the
> drawer/gallery trigger inputs.
> **Gallery video uploads (2026-07-07)** — the entry-field gallery input renders an
> "Upload videos" `UploadTrigger` (`asset_type: "video"`, gated on
> `Brando.default_video_upload_strategy() == :local`; Mux/Bunny sites keep the
> video picker's provider-hook upload, which already lands in the gallery via
> `select_video`). New `entry_field_gallery` delivery clause for `%Videos.Video{}`
> → Form `:gallery_video` handler appends a `video_id` gallery object
> (`put_assoc` + `sequence`) and syncs VideoPicker selection; the Gallery input's
> `new_video` update clause renders it immediately. Video deliveries ride the same
> 25ms gallery serialization queue as images. Input markup aligned with the block
> gallery: the hook wrapper (`data-click-mode="trigger"`) wraps the whole input as
> a drop zone with real `button.tiny` actions inside (the old markup was an
> unstyled div, rendered off-row).
> ~~TODO for Phase 2 go-live: manager consume does not queue `Brando.CDN.queue_upload`
> for server-transport files on CDN-enabled sites.~~ **Fixed (2026-07-09, audit):**
> consume now queues the CDN push for non-cdn `File` assets, matching `save_file`.
> **Post-migration audit (2026-07-09):** full-tree review of the shipped system.
> Fixed: consume-time storage errors crashing the sticky manager (error shapes now
> normalized via `Brando.Uploads.store_upload/4`); strict `config_target` resolution
> (`Brando.Assets.ConfigTarget` — no atom minting, blueprints only); video default-cfg
> struct coercion; nested entry-field processed-image routing (path now rides into the
> Oban job); direct-transport `folder_id` parity (finalize reuses `:direct_to_s3`);
> `direct_complete` idempotency; CDN push parity (above); transfer-slot leaks +
> upload-error sweep in `validate_queue`; ImageProcessor now broadcasts
> `[:image, :error]` on final failure (drawer items no longer pin at :processing;
> :processing items are dismissable); intake rejections render as :error drawer items;
> per-image PubSub subscriptions unsubscribed after processing; Bunny abort reports to
> the drawer; entry-field/gallery deliveries refetch already-processed images
> (inline-Oban race); file drawer resolves nested schemas. Deleted dead code: picker
> select-mode upload machinery + QueuedUploader/DragDrop hooks, `upload_folder_targets`,
> `cancel_upload` handlers, `block:upload_processed` plumbing, `:orphaned` status,
> scoped `.upload-progress` CSS. This doc's stale spec fragments were corrected in the
> same pass (target descriptor shape, decision keys, sticky id, intent channel and
> orphan-marking never built).
> **Asset-browser + intent audit (2026-07-15):** upload targets now pass through the
> canonical `Brando.Uploads.AssetIntent` boundary; malformed kinds, destinations,
> paths, topics and config targets are rejected before transfer. File fields and file
> refs share the folder-aware `FileBrowser`; file refs and video/gallery vars are
> supported. Populated refs/vars open their contextual editor first, with the browser
> used explicitly for select/replace/add. Gallery blueprint configs can define separate
> `image:` and `video:` configs (legacy flat configs remain image configs), and gallery
> refs/vars expose allowed media plus per-media config-target overrides.
> This document is a self-contained spec. It explains *why* the current upload
> system is broken, *what* to build (a sticky, free-standing `UploadManager` LiveView
> that owns a queue and every upload mechanic), and *how* to migrate every upload source
> and storage backend onto it. All open questions are resolved in §11.

---

## 1. TL;DR

- Today, block/var/field uploads use **LiveView native uploads registered on the form**,
  and the `@uploads` map is **threaded down the entire component tree** as `parent_uploads`.
  `@uploads` changes on **every progress tick**, so every tick re-renders the whole form.
- Measured on a 115-block entry: **one 4 MB file upload took ~106 s** (65 chunks acked)
  and produced **only ~8 diffs** — i.e. the server re-rendered the whole tree ~64 times to
  emit nothing. It scales linearly with the number of blocks/uploads and eventually the
  browser main thread starves and the transfer stalls (the "stuck at 89%").
- **Fix:** move *all* uploads into a **single sticky LiveView** (`BrandoAdmin.UploadManager`,
  `live_render(..., sticky: true)`) that lives in the chrome next to `BrandoAdmin.Chrome`.
  It owns the `allow_upload`(s) and a **queue** in its **own process/socket**, so upload
  progress re-renders only the manager's drawer — never the form. This is idiomatic
  LiveView, isolates by process boundary (storm becomes structurally impossible), keeps
  parallel uploads, and survives navigation.
- **Delivery is orphan-safe:** the asset record is always created and stored; notifying the
  originating block/field is a best-effort PubSub broadcast. Navigate away mid-upload →
  the upload still finishes, the asset still exists, we just skip the (now-gone) UI update.
  Never crash.
- **Consolidates every source and backend** behind one queue, choosing the transport per
  *(asset type × storage backend)*:
  - **Server-upload** (bytes through the manager LiveView → server): **images (always)**,
    **local files**, **local video**.
  - **Client-direct** (bytes bypass the server): **files → S3/Spaces (presigned PUT)**,
    **video → Mux (UpChunk) / Bunny (tus)**, video → S3 (future).

---

## 2. Why the current system melts down

### 2.1 The root cause (measured)

`@uploads` is passed as `parent_uploads` from the form all the way down to every leaf:

```
form.ex  ──parent_uploads={@uploads}──▶ fieldset / block_field
block_field.ex:1186 ──parent_uploads={@parent_uploads}──▶ Block (×N)
block/render.ex:57,108,136,176,258,661,709,832 ──▶ subform / fields
input/image.ex:83, input/file.ex:68, input/gallery.ex:162, input/video.ex:130 ──▶ leaf consumes parent_uploads[field]
```

LiveView `allow_upload` mutates `@uploads` on **every progress event**. Because the whole
map is threaded down, `parent_uploads` looks "changed" for **every** component, so the
entire tree's `render/1` runs on each tick. Confirmed empirically (WebSocket tally, one
upload on the big entry): `sendBinary: 65`, progress events: `64`, **diffs received: ~8**,
**elapsed: 106 s**. Pure wasted render, O(blocks × progress ticks).

Key LiveView fact we rely on for any in-place fix and for the new design:
`Phoenix.Component.assign/3` **does not mark an assign changed if the new value is
structurally equal** (verified: equal map → not in `__changed__`; different map → is).

### 2.2 Fragmentation (five upload routes today)

| Route | Where registered | Assign | Register event | Progress cb | Inline input | Threads `@uploads`? |
|---|---|---|---|---|---|---|
| Schema image/file/gallery/video **fields** | `allow_uploads/1` (`form.ex:2664-2769`) | `@uploads` | compile-time field list | `handle_image/file/gallery/video_progress` | drawers + `form.ex:1772` | **yes** |
| Block **ref** image/gallery (villain refs) | `register_block_upload` (`form.ex:500`) | `:block_uploads` | `"register_block_upload"` | `handle_block_image_progress/3` (`form.ex:4456`) | `form.ex:1755-1762` | **yes** |
| Block **var** image/file (new, June `7e8d820d7`) | `register_var_upload` (`form.ex:538`) | `:var_uploads` | `"register_var_upload"` | `handle_var_upload_progress/3` (`form.ex:4563`) | `form.ex:1763-1770` | **yes** |
| **Picker** (browse existing) `FilePicker`/`ImagePicker` | picker component | n/a (browse) / `QueuedUploader` | — | `picker:upload_progress` (`image_picker.ex:190-208`) | picker drawer | **no** (isolated) |
| **Direct provider** video → Mux/Bunny | `Videos.Uploader.initiate_upload` | none | `get_video_upload_url` (`form.ex:337`) | `pushEvent video_upload_progress` (`form.ex:425`) | none | **no** (direct) |

Everything that threads `@uploads` (rows 1-3) participates in the storm. The picker and the
direct-video routes are already isolated and are the models we generalize from.

### 2.3 Storage backends

`Brando.Upload.handle_upload/4` (`upload.ex:38,44`):
- `%{uploader: "S3"}` → `handle_upload_type(upload, user, :direct_to_s3)` (`upload.ex:75-87`)
  → creates a `File` with `cdn: true` from an S3 **key**, **no processing**.
- default (local) → validate/copy → `handle_upload_type/2`; images run
  `process_upload` (sizes/formats/dominant color, `upload.ex:89-140`).
- `build_meta/1` accepts a `%Plug.Upload{}` **or** a path (`files/uploads/schema.ex:42-49`,
  `images/uploads/schema.ex:37-44`) — so the storage layer is transport-agnostic (works from
  a controller POST *or* a consumed LiveView entry).

CDN = DigitalOcean **Spaces** via `ExAws.S3` (`cdn/cdn.ex:56-57`, host
`ams3.digitaloceanspaces.com`, bucket from `BRANDO_CDN_FILES_BUCKET`).
`ExAws.S3.presigned_url/4` is available (currently unused) → **files can be uploaded
client-direct to Spaces**, then the server creates the record from the key (reusing the
existing `:direct_to_s3` path). Images/videos cannot skip the server/provider because they
need processing/transcoding.

### 2.4 Prior art already in the tree

- Legacy direct-POST upload API: `BrandoAdmin.API.Images.UploadController`,
  `BrandoAdmin.API.Villain.VillainController` (`router.ex:44-45`). Non-LiveView multipart
  POST → `handle_upload` → asset. Proof the storage layer works outside LiveView uploads.
- Sticky LiveViews are already the norm: `layouts/live.html.heex:2`
  `live_render(@socket, BrandoAdmin.Chrome, id: "brando-chrome", sticky: true)` (and Nav).
- Concurrent picker uploads already exist (`QueuedUploader` hook + `picker:upload_progress`,
  `image_picker.ex:190-208`) — a working queue model to learn from.

---

## 3. Goals / non-goals

**Goals**
1. **One** upload system for every source (fields, block refs, block vars) and every backend
   (local, Spaces/S3, Mux, Bunny).
2. **Isolation:** upload progress must never re-render the editor form. (Process boundary.)
3. **Idiomatic:** keep LiveView native uploads where the bytes go through the server; keep
   direct-to-provider where they don't. No hand-rolled chunking.
4. **Queue + parallel:** many concurrent uploads from many targets, one shared progress UI.
5. **Orphan-safe:** an upload always completes and always creates the asset, even if the
   target UI is gone. Never crash on a lost target.
6. **Survives navigation:** uploads continue across `live_patch`/`live_navigate` (sticky).
7. **Drag-drop preserved** (design decision **(b)**): you can drop a file directly on a
   block/field; a JS bridge forwards it to the manager.

**Non-goals (for v1)**
- Resumable uploads across a full page reload / browser restart (sticky survives soft nav,
  not a hard reload). Note it; don't build it yet.
- Rewriting image processing. Images keep going through the server.
- Removing the picker's *browse existing* function (kept; only *new uploads* move).

---

## 4. Target architecture

### 4.1 The sticky `UploadManager` LiveView

```
layouts/live.html.heex
  {live_render(@socket, BrandoAdmin.Chrome,         id: "brando-chrome",         sticky: true)}
  {live_render(@socket, BrandoAdmin.UploadManager,  id: "brando-upload-manager-lv", sticky: true)}  ◀── NEW
```

- Own **process + socket** ⇒ its `@uploads` cannot thread into the form. Progress ticks
  re-render **only** the manager's drawer.
- **Sticky** ⇒ persists across navigation; an upload started on entry 13 keeps running when
  you jump to entry 16. Caveat: sticky survival requires staying within a **single
  `live_session`** — true today (all admin live routes are in `:require_authenticated_user`,
  `brando/router.ex:92`); don't split admin routes into multiple live_sessions without
  revisiting this.
- Holds the **queue** and the **drawer UI** (top-of-chrome progress stack).
- **Must render a hidden `<.live_file_input upload={@uploads.queue} />`** — the JS
  `this.upload("queue", files)` API locates the upload via that DOM element; without it the
  bridge silently fails.

### 4.2 Dispatch matrix — transport per (asset × backend)

| Asset | Backend | Transport | Rationale |
|---|---|---|---|
| Image | local | **server-upload** (manager `allow_upload`) | needs sizes/thumbs/dominant color |
| Image | Spaces/S3 | **server-upload** → process → push derivatives to Spaces | needs processing |
| File | local | **server-upload** | local == server; no direct endpoint |
| **File** | **Spaces/S3** | **client-direct presigned PUT** → create record from key | no processing; bytes skip server |
| Video | local | **server-upload** | `Uploader :local` = standard flow (`videos/uploader.ex:10,166`) |
| **Video** | **Mux** | **client-direct** (UpChunk) | provider transcodes |
| **Video** | **Bunny** | **client-direct** (tus) | provider transcodes |
| Video | S3 | client-direct presigned (future; `uploader.ex:13` "not yet implemented") | — |

The manager decides transport per queued item by asking the server to **initiate** the item
(see 6.2). The queue UI is identical regardless of transport.

### 4.3 Data model

```elixir
# UploadManager assigns
%{
  open?: boolean,
  items: %{                                   # entry_ref (string) => item
    "u-1a2b" => %{
      filename: "re-nettsider.pdf",
      size: 4_280_367,
      asset_type: :file | :image | :video,
      transport: :server | :direct,
      status: :queued | :uploading | :processing | :done | :error | :orphaned,
      progress: 0..100,
      error: nil | binary,
      target: target(),                       # where to deliver (may become nil/stale)
      asset: nil | %File{} | %Image{} | %Video{}
    }
  }
}
```

**Target descriptor** — a plain, serializable map (no pids in the payload; resolve at
delivery time). It says *what to set, where*. As implemented (string keys — the map
rides the trigger's dataset through JS):

```elixir
%{
  "deliver_topic" => binary,      # per-form-INSTANCE topic, "form:<uuid>" generated at form mount (§6.3)
  "kind" => "block_var" | "block_var_gallery"
          | "block_ref_picture" | "block_ref_file" | "block_ref_video" | "block_ref_gallery"
          | "entry_var" | "entry_var_gallery"
          | "entry_field" | "entry_field_gallery",
  # identity within the form:
  "component_id" => binary,       # live_component id for the block-scoped kinds
  "var_key" => binary | nil,      # for block/entry var targets
  "field" => binary | nil,        # for entry_field / entry_field_gallery
  "path" => [atom | integer],      # validated nested changeset path
  "asset_type" => "file" | "image" | "video",
  "config_target" => binary,      # "file:Elixir.Schema:field" | "image:..." | "default"
  "folder" => binary | nil,       # folder-browser choice (rides the intake)
  "folder_id" => term | nil
}
```

`config_target` drives both **backend selection** (via `Brando.Files/Images/Videos.get_config_for/1`,
`files.ex:105-130`) and **library filtering** for the picker.

---

## 5. End-to-end flow (design decision **(b)**: drop-on-block, forwarded to manager)

### 5.1 Trigger (source → manager) — the JS bridge

Every upload source (field, block ref, block var) renders a tiny **`UploadTrigger`** hook
instead of an inline `live_file_input`. It carries the target as data attributes and a
hidden `<input type=file>` / drop zone:

```html
<div phx-hook="Brando.UploadTrigger"
     data-kind="block_var" data-component-id="…render-var component id…" data-var-key="download"
     data-asset-type="file" data-config-target="file:Elixir.MyApp.Brand:download"
     data-accept=".pdf,.zip">
  <!-- deliver_topic resolves from the closest ancestor's data-deliver-topic -->
  <input type="file" hidden />
  … drop canvas …
</div>
```

On file select/drop the hook calls a **global bridge** exposed by the manager:

```js
// UploadManager hook (mounted once) registers:
window.BrandoUploads = {
  enqueue(files, target) { /* forwards into the manager LiveView */ }
}
// UploadTrigger:
window.BrandoUploads.enqueue(files, targetFromDataset(this.el))
```

`enqueue` in the manager hook:
1. `this.pushEvent("intake", {files: [{name,size,type}], target})` → server returns, per
   file, a **decision**: `{entry_ref, transport: "server"}` or
   `{entry_ref, transport: "direct", upload_url, extra}`.
2. For **server** files: `this.upload("queue", files)` (LiveView JS upload API, into the
   manager's own `allow_upload(:queue)`). **Entry↔item matching (resolved, §11.2):** the
   bridge wraps each file as `new File([file], `${entryRef}::${file.name}`, {type: file.type})`;
   `handle_progress` splits `entry.client_name` on `"::"` to find the queued item and strips
   the prefix before `build_meta`, so stored filenames stay clean. (Robust against concurrent
   intakes and duplicate filenames — order- or name-based matching is not.)
3. For **direct** files: run the matching direct uploader in JS
   (presigned PUT via `fetch`, Mux via UpChunk, Bunny via tus) against `upload_url`, and
   `pushEvent("direct_progress"/"direct_complete", {entry_ref, ...})`.

> Cross-LiveView note: `this.upload(...)` only feeds the **manager's** input because the
> bridge runs inside the manager hook's context. The trigger hook merely hands `File`
> objects across via `window.BrandoUploads`. No file bytes cross LiveView boundaries in the
> DOM; they enter the manager's uploader directly.

> Mount race: a drop can happen before the manager hook has mounted (first paint). Ship the
> bridge as a tiny pre-registered shim that **buffers** `enqueue` calls and flushes them when
> the manager hook attaches.

### 5.2 Server-upload path (images, local files, local video)

```
UploadManager LiveView:
  allow_upload(:queue, accept: :any, max_entries: 20, auto_upload: true,
               progress: &handle_progress/3)

handle_event("intake", %{files, target}, socket):
  for each file: entry_ref = gen_ref()
    put item in :items (status: :queued, target, transport: :server)   # target stored server-side
  {:reply, %{decisions: [%{index, ref, transport: "server"}]}, socket}

handle_progress(:queue, entry, socket):
  item = lookup by entry (match on client_name/ref)
  if entry.done? ->
    asset = consume_uploaded_entry(socket, entry, fn meta ->
              Brando.Upload.handle_upload(meta_with_config_target(meta, item), entry, cfg, user) end)
    deliver(item, asset)               # broadcast, orphan-safe (see §7)
    update item status: :done (or :processing for images awaiting derivatives)
  else -> update item.progress   # re-renders ONLY the manager drawer
```

Only **one** re-render happens in the *form* — when `deliver/2` fires on completion (§7).

**Images stay async exactly as the form path does today:** `consume_uploaded_entry` only
copies the file and creates the `:unprocessed` image row (`upload.ex:125-151`); the manager
then calls `Brando.Images.Processing.queue_processing/2` → Oban `Brando.Worker.ImageProcessor`
(queue `:image_processing`) and **delivers immediately**. The worker broadcasts
`:processing`/`:updated` on `"brando:image:#{id}"` (`image_processor.ex:65-77`); the drawer
subscribes per-item to flip `:processing → :done`. (The synchronous
`Images.Uploads.Schema.handle_upload` → `process_upload` path is only used by the
image/file *list* LiveViews — do not copy it into the manager.)

**Slot hygiene:** `cancel_upload/3` every failed/cancelled entry and prune dismissed items,
or the shared `max_entries: 20` fills with dead entries and blocks new uploads.

### 5.3 Client-direct path (files→S3, video→Mux/Bunny)

```
handle_event("intake", %{files, target}, socket):
  for each file:
    {:ok, %{upload_url, key|video_id, extra}} =
        initiate_direct(target.asset_type, target.config_target, file, user)
        # File→S3:   Brando.Files.Uploader.presign_put(filename, cfg)  (NEW, ExAws.S3.presigned_url)
        # Video→Mux: Brando.Videos.Uploader.initiate_upload(...)       (exists, form.ex:337)
    store pending {entry_ref => %{key|video_id, target}}
  {:reply, %{decisions: [%{index, ref, transport: "direct", upload_url}]}, socket}

# JS uploads directly to upload_url, reports:
handle_event("direct_progress", %{entry_ref, progress}, socket): update item.progress
handle_event("direct_complete", %{entry_ref}, socket):
  asset = finalize_direct(entry_ref)   # File.create_file(cdn:true, key) / Videos webhook-tracked
  deliver(item, asset)
```

For files→S3 this reuses `handle_upload_type(:direct_to_s3)` (`upload.ex:75-87`): the record
is created from the object **key** with `cdn: true`, no bytes through the server. Video keeps
its existing Mux/Bunny orchestration, just surfaced in the shared queue.

---

## 6. Server-side pieces to build

### 6.1 `BrandoAdmin.UploadManager` (sticky LiveView)
- `mount/3`: assign empty queue; `allow_upload(:queue, …)`; get `current_user` via
  on_mount. (The planned `"upload_manager:#{user.id}"` PubSub intent channel for
  programmatic enqueueing was NOT built — the JS bridge is the only intake today.)
- `handle_event("intake", …)`, `handle_progress/3`, `handle_event("direct_progress"/"direct_complete"/"cancel"/"retry"/"dismiss", …)`.
- `render/1`: the drawer (queue rows + progress + status + target label + cancel) **plus the
  hidden `<.live_file_input upload={@uploads.queue} />`** (required by `this.upload`, §4.1).
- **No form knowledge** beyond the opaque `target` maps it echoes back on delivery.

### 6.2 Transport facade — `Brando.Uploads` (new thin module)
- `initiate(asset_type, config_target, file_meta, user) :: {:server, cfg} | {:direct, %{upload_url, ...}}`
  - resolves backend from `config_target` (`get_config_for/1`), returns transport + params.
- `finalize_direct(asset_type, key|provider_id, meta, user) :: {:ok, asset}`
  - File→S3: `Files.create_file(%{cdn: true, filename: from_key, config_target, ...}, user)`.
  - Video: existing webhook/status path.
- `Brando.Files.Uploader.presign_put/2` (NEW): `ExAws.S3.presigned_url(:put, bucket, key, expires_in: …)`.

### 6.3 Delivery — form-side handler (added to `BrandFormLive` / `Components.Form`)
- On mount, the form generates a **per-form-instance topic** `"form:#{Ecto.UUID.generate()}"`,
  subscribes to it, and passes it into every trigger's dataset as `data-deliver-topic`.
  (Resolved, §11.7 — *not* `"form:#{schema}:#{id}"`: create forms have no id yet, two tabs
  editing the same entry must not share a topic, and a random topic is unguessable so a
  client can't address another user's form.)
- `handle_info({:asset_ready, target, asset}, socket)`: route by `target.kind`:
  - `:block_var` → the existing `update_block_var` path (the `:type`→`file_id` fix
    applies here — keep it; the commit reaches the BlockField op store via the
    `assign_block_form` chokepoint, no propagation step exists anymore).
  - `:block_ref` → set the ref's `image_id`/`file_id`/`video_id` via
    `Block.commit_ref_data/2` (never raw `send_update` — the helper routes the commit
    through `update_ref_data`, and the block's form rebuild lands in the op store).
  - `:entry_field` → `EctoNestedChangeset.update_at(path, id)` (as `save_file` does today,
    `form.ex:3594-3601`).
- **This is the only place the form re-renders per upload — once, on completion.**

---

## 7. Orphan-safe delivery (hard requirement)

**Principle: asset creation ≠ delivery.** The asset is created & stored in `handle_progress`/
`finalize_direct` **before** we try to notify anyone. Delivery is fire-and-forget:

```elixir
defp deliver(item, asset) do
  # 1. asset already persisted here.
  # 2. best-effort notify; nobody listening is fine.
  Phoenix.PubSub.broadcast(Brando.pubsub(), item.target.deliver_topic,
    {:asset_ready, item.target, asset})
  # 3. keep it in the manager's "recent uploads" list so the user can grab it manually.
end
```

- Navigate away mid-upload → the originating form process may be gone; the broadcast lands
  on no subscriber; **no crash** (PubSub broadcast to an empty topic is a no-op).
- If the form is *still* mounted but the specific block was deleted, the form-side
  `handle_info` no-ops gracefully when the block/var/field can't be found (send_update to a
  missing component logs a miss), never raises. (Note: the originally planned `:orphaned`
  item status and drawer "recent uploads — click to copy/select" list were NOT built —
  delivery is fire-and-forget with no feedback channel, so the manager can't know a
  delivery missed. The guarantees below still hold.)
- The asset is always in the library (it's a real `File`/`Image`/`Video` row), so nothing is
  lost — the user can select it later via the picker.

Failure isolation: a delivery crash must never take down the sticky manager. Wrap
`handle_info`/delivery in try/rescue at the form side; the manager only broadcasts.

---

## 8. Per-source integration

All three render a `UploadTrigger` (or reuse the picker's "select existing"); only the target
descriptor differs.

- **Entry schema fields** (`input/image.ex`, `input/file.ex`, `input/video.ex`): target
  `kind: :entry_field`, `path` from `get_path_from_field_name(form.name)` (as `file.ex:107-110`
  already derives), `config_target: "file:#{schema}:#{field}"`.
- **Block refs (villain)** (`block/render.ex`, `input/image.ex`/`gallery.ex` inside refs):
  target `kind: :block_ref`, `block_uid`, `ref_name`; delivery via
  `Block.commit_ref_data/2` (`update_ref_data` under the hood).
- **Block vars** (`render_var.ex`): target `kind: :block_var`, `block_uid`, `var_key`,
  `config_target` from `@var[:config_target].value`; delivery via `update_block_var`.
  Keep the existing **"select existing"** browser path (`set_file_target`/`select_file`,
  `render_var.ex:1000-1047`) — it's already isolated; only the *upload* moves to the manager.

---

## 9. Security, config, limits

- **Auth:** the sticky manager reads `current_user` from the session at mount (same as Chrome).
  It uploads on behalf of that user; targets are opaque and validated server-side.
- **CSRF / presigned:** presigned PUT URLs are short-lived (`expires_in`), scoped to a
  computed key under the configured bucket/prefix; validate `config_target` server-side before
  presigning (never trust client-provided keys).
- **accept / max_size (resolved, §11.5):** `data-accept`/`data-max-size` on the trigger are
  UX-only. Authoritative enforcement happens in **`intake`**: resolve the asset config from
  `config_target` (`__asset_opts__`/`FileConfig`/`ImageConfig`), validate name/size/type per
  file, and reject in the intake reply **before any bytes move** (this also covers direct
  transports, where `allow_upload` never sees the file). Defensive backstop: `cancel_upload`
  in `handle_progress` if a non-conforming entry slips through.
- **config_target validation:** resolve via `get_config_for/1`; reject unknown targets.
- **Spaces CORS (Phase 2 ops prerequisite):** the bucket must allow browser `PUT` from the
  admin origin (AllowedMethods `PUT`, AllowedOrigins = admin host, AllowedHeaders `*`)
  before presigned client-direct uploads can work. Without it, uploads fail in the browser
  with an opaque CORS error.

---

## 10. Migration plan (phased, each independently shippable)

**Phase 0 — keep today's correctness fixes.** Retain in `block.ex`:
`update_changeset_data_block_var` writing `file_id`/`image_id` (the `:type` bug fix).
This is how delivery lands for vars. (The propagation half of the old fix —
`maybe_propagate_block_var` — was removed in the Phase 3 single-owner refactor: var
commits reach the BlockField op store through `assign_block_form`, nothing to propagate.)

**Phase 1 — build the manager (server-upload only), migrate block file+image *vars*.**
- Add `UploadManager` sticky LiveView + `UploadTrigger`/`UploadManager` JS hooks + the
  `window.BrandoUploads` bridge.
- Add form-side `deliver_topic` subscription + `{:asset_ready, …}` handler for `:block_var`.
- Route render_var file/image var *uploads* through the manager (keep "select existing").
- **Remove** var inline plumbing: `register_var_upload` (`form.ex:538-580`),
  `handle_var_upload_progress` (`form.ex:4563-4647`), `var_upload_complete`
  (`form.ex:606-631` + `live_view/form.ex:480-497`), form-level var `live_file_input`
  (`form.ex:1763-1770`), `:var_uploads`, and `maybe_register_var_upload` + the `upload_complete`
  branch + `BlockUpload` wiring in `render_var.ex`.
- **Measure** with the WebSocket tally on the big entry: expect ~1 form diff per completed
  upload instead of ~64.

**Phase 2 — file → Spaces client-direct.** Add `Files.Uploader.presign_put/2` + the
`Brando.Uploads.initiate/finalize_direct` direct branch + JS presigned-PUT uploader. Files with
S3 config skip the server entirely. **Ops prerequisite:** Spaces bucket CORS must allow
browser `PUT` from the admin origin (§9).

**Phase 3 — migrate block *refs* (image/gallery) onto the manager.** Remove
`register_block_upload`/`handle_block_image_progress`/`:block_uploads`
(`form.ex:500, 4456, 1755-1762`). Delivery via `Block.commit_ref_data/2`.

**Phase 4 — migrate *entry schema fields*.** Remove per-field `allow_uploads/1` inline
progress + the field drawers' `live_file_input`; keep the drawers as *pickers*. Delivery via
`EctoNestedChangeset` (reuse `save_file` logic).

**Phase 5 — fold video into the queue UI.** Surface Mux/Bunny (already direct) as manager
queue items; route local video server-upload through the manager. Refactor
`MuxUploader`/`BunnyUploader` hooks to report into the manager queue rather than ad-hoc UI.

**Phase 6 — delete `parent_uploads` threading entirely.** Once nothing in the block tree
consumes `@uploads`, remove `parent_uploads` from `form.ex`, `block_field.ex`, `block/render.ex`,
`subform*.ex`, `fieldset*.ex`, `input/{image,file,gallery,video}.ex`. This is the payoff:
the editor never re-renders for an upload again.

### Delete list (grep anchors)
- `render_var.ex`: `maybe_register_var_upload/3`, `update_many/2` `upload_complete` branch,
  file_modal inline drop zone (`~893-979`, keep the card + "select existing").
- `form.ex`: `register_var_upload` (538), `handle_var_upload_progress` (4563),
  `var_upload_complete` (606), var `live_file_input` (1763), `:var_uploads` reads
  (547/615/1763/4566). Later: `register_block_upload` (500), `handle_block_image_progress` (4456),
  block `live_file_input` (1755). Finally: all `parent_uploads={@uploads}` / `={@parent_uploads}`.
- `live_view/form.ex`: `{:var_upload_complete, …}` forwarder (480-497).
- JS: retire `BlockUpload` var usage; add `UploadManager` + `UploadTrigger`; refactor
  `MuxUploader`/`BunnyUploader` to report into the manager.
- `videos/uploader.ex:12-14` moduledoc: **stale** — it lists Bunny as "not yet implemented",
  but `Brando.Videos.Uploaders.Bunny` exists and is routed (`uploader.ex:164-165`, plus
  `bunny_webhook.ex`). Fix the doc lines (only `:cloudflare` and `:s3` are unimplemented).

---

## 11. Resolved decisions (review, 2026-07-04)

1. **Intake:** JS `window.BrandoUploads.enqueue` bridge for user uploads (real drag-drop needs
   `File` object hand-off). (The PubSub intent channel for programmatic/test enqueueing was
   decided for but never implemented; add it if a programmatic caller shows up.)
2. **entry_ref ↔ entry matching:** **filename tagging** — the bridge wraps each file as
   `new File([file], "#{entry_ref}::#{name}")`; the server splits `entry.client_name` on
   `"::"` and strips the prefix before `build_meta` (§5.1). Order- or name/size-based
   matching rejected (breaks on interleaved intakes / duplicate filenames).
3. **Images direct to Spaces:** **rejected** — the server would have to re-download the
   original to process it; net loss. Images stay server-upload → Oban → CDN push.
4. **Hard-reload resilience:** **out of scope for v1.** Sticky covers soft navigation only.
   Orphan-safety (§7) means completed uploads are never lost — only in-flight transfers die
   on a full reload.
5. **Per-target accept/size:** enforced **authoritatively in `intake`** from the resolved
   config, rejected in the intake reply before any bytes move (§9). Trigger `data-*`
   attributes are UX-only; `cancel_upload` in `handle_progress` is a defensive backstop.
6. **Naming:** keep `BrandoAdmin.UploadManager` / `Brando.Uploads` / `UploadTrigger`.
7. **deliver_topic (added in review):** per-form-instance UUID topic
   (`"form:#{Ecto.UUID.generate()}"`) generated at form mount (§6.3) — works for create
   forms (no entry id yet), isolates two tabs editing the same entry, and is unguessable.

---

## 12. Appendix — reference anchors (current code)

- Storm threading: `form.ex:1703,1711,1724,1780,1820,1836`;
  `block_field.ex:1186`; `block/render.ex:57,108,136,176,258,661,709,832`;
  leaves `input/image.ex:83-84`, `input/file.ex:68`, `input/gallery.ex:162,180`,
  `input/video.ex:130`.
- Var route: `render_var.ex:200-234` (register), `render_var.ex:34-56` (upload_complete),
  `render_var.ex:893-979` (file_modal), `render_var.ex:1000-1047` (set_file_target/select_file/reset);
  `form.ex:538-580,606-631,1763-1770,4563-4647`; `live_view/form.ex:480-497`.
- Picker (isolated, keep for browse): `file_picker.ex` (browse-only), `image_picker.ex:190-208`
  (queued upload), mounted `form.ex:1695`.
- Direct video: `form.ex:337-405` (`get_video_upload_url`/`video_upload_progress`),
  `videos/uploader.ex:150-166`, hooks `assets/src/hooks/{MuxUploader,BunnyUploader}/index.js`.
- Storage: `upload.ex:38,44,75-140`; `files.ex:67,105-130`; `cdn/cdn.ex:56-57`;
  `files/uploads/schema.ex:42-49`, `images/uploads/schema.ex:37-44`.
- Sticky precedent: `layouts/live.html.heex:2`. Legacy POST API: `router.ex:44-45`.
- LiveView assign-skip guarantee (basis for §2.1 in-place option and safe re-assigns):
  equal value ⇒ not marked changed (verified).

---

## 13. Why not the alternatives (for the record)

- **A — scope `parent_uploads` per block in place.** Fixes the storm for inline uploads but
  keeps five fragmented routes and touches the most fragile code (`Block.update/2`); doesn't
  unify or make uploads navigation-proof.
- **C — custom direct-POST endpoint for everything.** Works, but throws away idiomatic
  LiveView uploads for local/image (which genuinely benefit from the server pipeline) and
  duplicates chunking/auth. We keep C *only* where bytes should skip the server
  (files→S3, video→provider).
- **B (this plan) — sticky manager + queue.** Isolation by process boundary, idiomatic where
  it should be, direct where it should be, one queue, orphan-safe, navigation-proof.
