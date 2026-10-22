# Upload architecture

Every admin upload goes through one sticky LiveView, `BrandoAdmin.UploadManager`
(`lib/brando_admin/live/upload_manager.ex`). A source renders an `UploadTrigger`
and hands its files to the manager; the manager validates, transfers, stores the
asset and delivers it back to the source over PubSub. The manager owns the queue,
the transfers and the progress drawer; sources only project its state
(`assets/src/hooks/shared/uploadProgress.js`). Upload progress re-renders the
manager's drawer, never the editor form.

The shared `MediaField` renders upload, browse and configure actions and the drop
target for fields, refs and vars, populated or empty.

## Transport per asset type and backend

`Brando.Uploads.initiate/4` picks the transport at intake.

| Asset | Backend | Transport | After transfer |
|---|---|---|---|
| Image | local, or CDN without `direct` | server | `Image` row `:unprocessed`, Oban `ImageProcessor` makes sizes; CDN push from the worker |
| Image | CDN with `direct: true` | direct presigned PUT | HEAD verify, fetch original back, store `Image`, process like a server upload |
| File | local, or CDN without `direct`, or `content_disposition` set | server | `File` row; on a CDN-enabled site `Brando.CDN.queue_upload` pushes it |
| File | CDN with `direct: true` | direct presigned PUT | HEAD verify, `File{cdn: true}` from the key, no processing |
| Video | `:local` | server | `File` wrapped in `Video{type: :upload, status: :ready}` |
| Video | `:s3` (needs direct CDN with bucket and `media_url`) | direct presigned PUT | HEAD verify, CDN `File` wrapped in `Video{type: :upload, status: :ready}` |
| Video | `:mux` (UpChunk), `:bunny`, `:cloudflare`, `:vimeo` (tus) | provider hooks, outside `initiate/4` | provider transcodes; drawer shows them as `:external` items |

- Direct transport is opt-in per config: `cdn: %Brando.CDN.Config{enabled: true, direct: true}`
  plus S3 credentials (`Brando.CDN.S3Config`). Direct files and videos leave no local
  copy; a direct image's original is fetched back for processing and stays on disk with its sizes
  unless `keep_local_copy: false`.
- `initiate/4` returns `{:ok, :server}`, `{:ok, {:direct, %{upload_url, upload_headers, key, filename, resolved_target}}}`
  or `{:error, message}`. Video `:none` and provider strategies return an error
  there; providers validate through `validate_provider_video_intake/2` instead.
- Cloudflare reports completion through a signed webhook; Vimeo has no webhooks
  and `Brando.Worker.VimeoStatus` polls. Unknown strategies fail at Blueprint
  compile time; signed Mux/Cloudflare playback is rejected until a token signer
  is configured.

## Flow: trigger, intake, transfer, store, deliver

### Trigger (`assets/src/hooks/UploadTrigger`)

The trigger carries the target as data attributes (`data-kind`, `data-component-id`,
`data-var-key`, `data-asset-type`, `data-config-target`, `data-accept`,
`data-max-files`, `data-allowed-types`, `data-video-config-target`,
`data-folder-browser`, `data-click-mode`). `deliver_topic` comes from the closest
ancestor's `data-deliver-topic`; a trigger without one refuses the upload.

- `data-accept`, `data-max-files` and size hints are UX only; intake enforces.
- Mixed galleries (`data-allowed-types`) enqueue each file separately, with the
  video config target for videos.
- `data-folder-browser="true"` on a default-target image enqueues at once into the
  folder chosen for that field, else the last one used, else the config's own
  (`intake/1`, `destinationFolder/0`). **Change** beside the destination
  (`changeDestination/0`) opens the folder browser with no files waiting; its
  `b:block_upload_folder_confirmed` (matched by element id and request id) sets the
  folder for the field's next uploads, whose `folder`/`folder_id` ride the target.
  A concrete config target takes its folder from its upload config.
- Single-asset triggers send `expected_asset_id` (the current asset id or `"none"`).
- `data-click-mode="trigger"`: only `.upload-trigger` children open the file dialog.

The trigger calls `window.BrandoUploads.enqueue(files, target)`. The bridge is
registered at module import in `assets/src/hooks/UploadManager/index.js`, so a drop
before the manager hook mounts is buffered and flushed on mount. `enqueue` adds the
`scope_token` from `[data-authorization-upload]`.

### Intake (`handle_event("intake", …)`)

1. The hook pushes `intake` with `{index, name, size, type}` per file and the target.
2. `Brando.Uploads.AssetIntent.normalize/1` validates the target: kind, asset type
   compatible with the kind, `deliver_topic` shaped `"form:<uuid>"`, path segments
   that are existing atoms or integers, destination keys, `expected_asset_id`. A bad
   target becomes an `:error` item per file.
3. Single-asset kinds (`entry_field`, `entry_var`, `block_var`, `block_ref_picture`,
   `block_ref_file`, `block_ref_video`, and `file_replace`) reject more than one file.
   A new upload to the same destination marks earlier items `superseded`; a
   superseded item still stores its asset but is not delivered.
4. Each file runs `initiate/4` (or `Brando.Files.Replacement.initiate/3` for
   `file_replace`) inside `Brando.Authorization.Media.with_intent/3`.
5. The reply holds one decision per file: `{index, ref, transport: "server"}`,
   `{index, ref, transport: "direct", upload_url, upload_headers}` or
   `{index, ref, error}`. Rejected files stay in the drawer as `:error` items.

Item refs are `Ecto.UUID`s. The item keeps the target, and for direct transport
the key and resolved target, server-side.

### Server transport

- The hook renames each file to `"<ref>::<name>"` and calls `this.upload("queue", [file])`.
  `handle_progress/3` finds the item by splitting `client_name` on `"::"`, and the
  prefix is stripped before storage. Match entries this way only; order and filename
  matching break on concurrent intakes and duplicate names.
- `allow_upload(:queue, accept: :any, max_entries: 20, auto_upload: true,
  max_file_size: Uploads.manager_max_file_size())`. The max size is a transport
  backstop (default 5 GB); the config's `size_limit` was already applied at intake.
- On `entry.done?`: resolve the config, apply the confirmed folder, then
  `consume_uploaded_entry` → `Brando.Uploads.store_upload/4` (wraps
  `Brando.Uploads.Store.handle_upload/4` and normalizes every error to
  `{:ok, asset} | {:error, message}`). The consume callback always returns `{:ok, _}`
  so the temp file is cleaned up on failure too.
- The manager pushes `b:uploads:released` to free the JS transfer slot, then
  delivers, then (images) queues processing. Deliver comes first so the form has
  the asset before an inline Oban run broadcasts `:processed`.
- The manager must render the hidden `<.live_file_input upload={@uploads.queue} />`
  inside `#brando-upload-manager-queue-form`; `this.upload` finds the upload through
  it, and the form id makes it eligible for LiveView form recovery.
- Slot hygiene: `validate_queue` cancels resurrected entries (a consumed file the
  client re-sends as a new entry, which would hold a `max_entries` slot forever)
  and entries that errored without completing; `cancel_item` cancels the entry and
  dismissing drops the item. Keep all three, or dead entries fill `max_entries` and
  the queue silently stops accepting files.

### Direct transport

- `Brando.Uploads.presign_put/3` signs a PUT valid for 600 s with `Content-Type`,
  plus `x-amz-acl` only when the CDN config sets `direct_acl`. The key is
  `media/<upload_path>/<filename>`, uniquified unless the config overwrites.
- At intake the manager records a `Brando.Uploads.PendingIntent` (ref, key,
  resolved target, declared size and type, target, creator).
- The hook PUTs with exactly the signed headers via XHR, reports `direct_progress`,
  then `direct_complete` or `direct_error`.
- `direct_complete` finalizes from server-side state only (`finalize_direct/3`
  HEAD-verifies size and type against the declared values), then delivers. A replay
  for a `:done` item is a no-op. An unknown ref (the manager remounted mid-transfer)
  is recovered from the `PendingIntent` if the same user authorized it; there is no
  drawer row, but the asset lands and is delivered.
- `direct_error` and `cancel_item` delete the intent. `Brando.Worker.UploadIntentReaper`
  (daily cron) deletes intents older than 24 h and their bucket objects.

### Provider video

Mux, Bunny, Cloudflare and Vimeo hooks own their transfer and delivery and report
to the drawer through `window.BrandoUploads.trackExternal/externalProgress/externalComplete/externalError`.
`:external` items are display-only and cannot be cancelled from the drawer.
Cloudflare provisions one-time direct-user tus uploads, tracks `:uploading` →
`:processing`, verifies raw-body webhook HMACs and persists playback, thumbnail,
dimensions and duration.

### Images after storage

- The manager subscribes to `"brando:image:<id>"` and calls
  `Brando.Images.Processing.queue_processing/4`, passing the entry field path
  (`path ++ [field]`) so nested-field updates route back. `[:image, :updated]`
  flips the item to `:done`, `[:image, :error]` to `:error`; it unsubscribes either way.
- `Brando.Images.find_duplicate/1` flags an upload matching an existing image. The
  drawer offers **Use existing** (delivers the existing image with
  `expected_asset_id` set to the new one, deletes the new one) or **Upload anyway**.
- Processing can finish before delivery is handled. Delivery adapters refetch the
  image (`refresh_processed_image`, `maybe_forward_already_processed`) so the
  processed struct is not lost.
- Other editors: the worker also broadcasts on `Brando.Assets.ProcessingStatus.topic(:image, id)`
  (providers on `topic(:video, id)`). A component that shows an asset in processing
  calls `BrandoAdmin.LiveView.Form.ProcessingWatch.watch/4` from `update` and
  receives `%{event: "image_processed"}` / `%{event: "video_processed"}`.

### Concurrency

`config :brando, Brando.Uploads, max_concurrent_transfers: N` (default 3) caps
transfers per client, server and direct alike, in the manager hook's scheduler.
Server slots free on `b:uploads:released`, direct slots locally. Files for one
gallery target transfer one at a time, so the gallery keeps the chosen order;
other targets run in parallel. Processing concurrency is the `:image_processing`
Oban queue and `:concurrent_image_jobs`.

## Target descriptor

A string-keyed map that rides the trigger dataset, the intake event, the item, the
`PendingIntent` and the delivery message. Build it only through the trigger and
`AssetIntent.normalize/1`; serialize config targets with
`Brando.Assets.ConfigTarget.serialize/1`.

| Key | Meaning |
|---|---|
| `kind` | `block_var`, `block_var_gallery`, `block_ref_picture`, `block_ref_file`, `block_ref_video`, `block_ref_gallery`, `entry_var`, `entry_var_gallery`, `entry_field`, `entry_field_gallery`, `resource_gallery`, `transformer_image`, `transformer_video`, `video_picker`, `image_picker`, `asset_library`, `file_replace`, `ai_conversation` |
| `asset_type` | `image`, `file`, `video`; restricted per kind (refs, pickers, transformers, `file_replace`) |
| `deliver_topic` | `"form:<uuid>"` of the receiving LiveView |
| `component_id` | live_component id; required for every kind except `entry_field*` and `file_replace` |
| `var_key` | required for var kinds |
| `field`, `path` | entry field name and its validated nested changeset path |
| `config_target` | `"image:Elixir.Schema:field"`, `"file:…"`, `"video:…"`, `"gallery:…"` or `"default"`; picks the backend and size limit |
| `folder`, `folder_id` | confirmed destination folder |
| `expected_asset_id` | selection the upload replaces; a stale completion leaves a newer selection alone |
| `ref` | client correlation token echoed to transformers and conversations |
| `file_id` | file being replaced (`file_replace`) |
| `scope_token` | signed authorization scope (added by the bridge) |

`config_target` resolves strictly through `Brando.Assets.ConfigTarget` (Blueprint
targets only, no atom minting). Invalid function results, declaration-only
sentinels and cross-media field targets fall back to the typed default.
`Brando.Uploads.resolve_*_config/1` never raise: an unresolvable target uses the
default config.

## Delivery and the orphan-safe contract

The asset row is created and stored before anyone is notified. Delivery is one
best-effort broadcast:

```elixir
Phoenix.PubSub.broadcast(Brando.pubsub(), target["deliver_topic"], {:asset_ready, target, asset})
```

- Nobody listening is fine: the upload still completes and the asset stays in the
  library, selectable through the picker. Uploads are never cleaned up because a
  form was abandoned or its save failed (`test/brando/uploads/asset_orphan_test.exs`).
- The receiving form may lack the component; `send_update` to a missing component
  only logs. Delivery has no acknowledgement, so the manager cannot tell a miss.
- Each form mints `deliver_topic` at mount (`"form:" <> Ecto.UUID.generate()`) and
  subscribes to it. A form that remounts mid-upload listens on a new topic and
  misses that delivery. The manager logs `delivering asset #<id> to form:<8 chars>…`
  and the form logs `listening for asset delivery on …`; matching prefixes mean the
  delivery could land.
- The topic is per instance, not `schema:id`: create forms have no id, two tabs on
  one entry stay separate, and a random UUID cannot be guessed.
- The sticky manager must never crash: every `handle_event` has a catch-all,
  finalize rescues, and `store_upload/4` normalizes errors. The form side wraps
  delivery in `safe_deliver_asset` (rescue and log).
- `ai_conversation` targets also get `{:assets_reserved, target, accepted}` at intake,
  in selection order, and the delivered target carries `upload_ref`.

### Form-side routing (`BrandoAdmin.LiveView.Form.Hooks`)

`handle_asset_delivery_info/2` routes `{:asset_ready, target, asset}` by
`target["kind"]` in `deliver_asset/3`:

| Kind | Receiver |
|---|---|
| `block_var`, `entry_var`, `*_var_gallery` | `RenderVar` `upload_complete` → `update_block_var` writes `image_id`/`file_id`/`video_id`; reaches the BlockField op store through `assign_block_form` |
| `block_ref_picture` | `PictureBlock` `image_uploaded`; refreshes when processing ends |
| `block_ref_file` | `FileBlock` `live_upload_complete` |
| `block_ref_video` | `VideoBlock` `select_video` |
| `block_ref_gallery` | `GalleryBlock` adds the image id at once, swaps in the processed struct later; videos via `video_created_from_url` |
| `entry_field` | `Form` `entry_field_upload_complete` |
| `entry_field_gallery` | `Form` `entry_field_upload_complete` with `asset_type: :gallery` / `:gallery_video` |
| `image_picker`, `video_picker` | picker refresh / `upload_complete` |
| `transformer_image`, `transformer_video` | `Form.Transformer` `upload_complete` with `ref` |

Block ref components commit through `Block.commit_ref_data/2`, never a raw
`send_update` of ref data. Gallery kinds (`block_ref_gallery`, `entry_field_gallery`,
`block_var_gallery`, `entry_var_gallery`, `resource_gallery`) queue in
`gallery_delivery_queue` and apply one per 25 ms tick: batched `send_update`s would
apply several additions against the same state and drop some.

`BrandoAdmin.Images.ImageListLive`, `BrandoAdmin.Files.FileListLive` and
`BrandoAdmin.AI.AssistantLive` mint and
subscribe to their own `deliver_topic` the same way.

## Per-source integration

- **Entry fields** (`input/image.ex`, `input/file.ex`, `input/video.ex`): `kind:
  "entry_field"`, `path` from `get_path_from_field_name(form.name)`, config target
  `"<type>:<schema>:<field>"`. `Form` writes the FK at the path, puts the asset on
  the assoc in changeset data, and pushes a targeted `b:validate` (`%{target, value}`),
  because the inputs render the hidden relation input from the assoc. The clauses
  leave `editing_*?` as they are: an upload inside an open drawer keeps the drawer's
  recovery snapshot and save guard.
- **Gallery fields** (`input/gallery.ex`): `kind: "entry_field_gallery"`; delivery
  appends a gallery object (`put_assoc` + `sequence`) and updates the picker and
  input. Video uploads show when `Brando.Uploads.video_upload_available?/1` holds.
  The wrapper uses `data-click-mode="trigger"`. Blueprint gallery configs may set
  separate `image:` and `video:` configs; a flat config is the image config only.
- **Block refs** (`block/render.ex`, ref inputs): `block_ref_picture`,
  `block_ref_file`, `block_ref_video`, `block_ref_gallery` with `component_id`.
  Gallery refs and gallery vars expose allowed media and per-media config-target
  overrides.
- **Block and entry vars** (`render_var.ex`): `block_var`/`entry_var` with
  `component_id`, `var_key`, config target from `@var[:config_target]`. Selecting an
  existing asset (`set_file_target`/`select_file`) stays in the form; only uploads
  go through the manager.
- **Drawers**: populated fields, refs and vars open their contextual editor; the
  folder-aware browser (`FileBrowser` for files) is for selecting, replacing or
  adding. A picker selection commits the FK the same way an upload does.
- **Media library**: image and file listing intake uses `asset_library`; standalone
  gallery editors use `resource_gallery`.
- **Image editor "save as new copy"** is the one form-owned upload
  (`allow_upload(:image_editor_upload)` in `Form.allow_uploads/1`).

### File replacement

The Files listing's **Replace file** sends a `file_replace` target with `file_id`.
`Brando.Files.Replacement` accepts one file, resolves the config from the stored
record, requires the same extension, and always uses server transport (a presigned
PUT to the live key could leave it half-written). After validating size and MIME
type it renames atomically (local) or uploads to the existing bucket key (CDN),
keeping the record's id, URL, CDN flag, title, creator, folder, config target and
references. Failure leaves the original untouched. It then evicts cached file
queries and re-renders entries whose blocks reference the file through refs, vars
or table-row vars. Completion reaches the listing through PubSub.

### Completion callbacks

`completed_callback` (function or MFA, `Brando.Assets.CompletedCallback`) runs for
files when stored, images after processing (SVG included), local videos when
stored, and provider videos on their first ready transition. Mux/Bunny resolve it
through the stored `config_target`. It can run more than once; keep side effects
idempotent. Metadata edits do not invoke it.

## Server-side pieces

| Module | Role |
|---|---|
| `BrandoAdmin.UploadManager` | Sticky LiveView: intake, server/direct/external events, drawer, delivery |
| `Brando.Uploads` | `initiate/4`, `finalize_direct/3`, `store_upload/4`, `presign_put/3`, config resolution, intake validation, pending-intent CRUD |
| `Brando.Uploads.AssetIntent` | Target normalization at intake |
| `Brando.Uploads.Store` | Storage: `handle_upload/4`, `handle_upload_type` (`:direct_to_s3` creates a CDN `File` from a key), `:unprocessed` image rows |
| `Brando.Uploads.PendingIntent` | Persisted authorized direct uploads (`uploads_pending_intents`) |
| `Brando.Worker.UploadIntentReaper` | Removes abandoned intents and their objects |
| `Brando.Uploads.Direct` | Presign → complete/cancel for a site's own (non-admin) forms; runs as `:system` unless `user:` is given |
| `Brando.Files.Replacement` | In-place file replacement |
| `Brando.Authorization.Media` | Upload authorization and the signed `scope_token` |
| `BrandoAdmin.LiveView.Form.Hooks` | Form-side `:asset_ready` routing |
| `BrandoAdmin.LiveView.Form.ProcessingWatch` | Cross-editor processing updates |

The manager renders in `layouts/live.html.heex` and `layouts/frontend_edit.html.heex`
as `live_render(@socket, BrandoAdmin.UploadManager, id: "brando-upload-manager-lv", sticky: true)`.
Sticky survival needs one `live_session`: all admin routes share
`:require_authenticated_user` in `lib/brando/router.ex`. Uploads survive
`live_patch`/`live_navigate`, not a full reload; completed uploads are always kept.

## Security, config and limits

- **Auth:** the manager reads `current_user` on mount and drops `intake` and
  `direct_complete` without one. With the authorization engine enabled, intake,
  consume and finalize run in `Media.with_intent/3`, which verifies the
  `scope_token` belongs to the socket's user and applies its tenant prefix.
- **Validation before bytes move:** `initiate/4` authorizes the user for the asset
  type, then checks size against the config's `size_limit` (fallback 50 MB),
  extension (images `.jpg .jpeg .png .gif .webp .svg`; videos `.mp4 .webm .mov .avi .ogv`)
  and, for direct and video uploads, MIME type. Server-transport files get their
  MIME check at consume, in `Brando.Uploads.Store`.
- **Presigned PUTs** are short-lived, keyed by the server, and finalized only from
  server-side state; a client never supplies a key.
- **Bucket CORS (ops):** allow `PUT` from the admin origin, `AllowedHeaders` `*`
  (it must cover `x-amz-acl` when `direct_acl` is set). Without it the
  browser reports an opaque CORS error. AWS buckets use a bucket policy and leave
  `direct_acl` nil; Spaces setups that need object ACLs set `direct_acl: "public-read"`.
- **Config:**
  - `config :brando, Brando.Uploads, max_concurrent_transfers: 3` — client transfer cap.
  - `config :brando, Brando.Uploads, manager_max_file_size: 5_000_000_000` — transport backstop.
  - Per field: `size_limit`, `allowed_mimetypes`, `upload_path`, `cdn`, `content_disposition`,
    `random_filename`/`overwrite`/`slugify_filename`.
