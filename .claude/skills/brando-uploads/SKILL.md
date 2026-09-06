---
name: brando-uploads
description: >
  Contracts for Brando's media asset fields, asset browser, pickers, and the
  sticky UploadManager. Use when working with image, video, file or gallery
  fields, block refs or vars that carry media, asset folders, upload intents,
  transports, or config targets.
user-invocable: true
---

# Media asset fields, browsers, and uploads

The current architecture and transport matrix are documented in `docs/UPLOADER.md`.
Keep these UX and wiring contracts intact when changing image, video, file, or gallery
fields, refs, and vars:

- **The asset browser is the shared selection hub, not the contextual editor.** Use the
  folder-aware browser to browse, select, replace, or add existing assets. If a context
  already has an asset, open its field/ref/var editor directly; do not force the user
  through the browser before they can edit captions, crops, playback settings, or other
  usage-specific overrides.
- **Selection means current editing state.** Reopening a picker must mark the asset
  currently shown in the unsaved drawer/editor, not the value last persisted to the
  database. Keep image, video, and file picker behavior aligned.
- **Overrides belong to the usage context.** Blueprint field configuration supplies field
  defaults; block refs and vars may override their image/video/gallery configuration.
  Asset records and the shared browser must not absorb context-only data such as captions,
  crop choices, playback flags, or ref-specific configuration.
- **All new uploads go through the sticky `BrandoAdmin.UploadManager`.** Upload progress
  must remain isolated from the editor form process. Triggers create an intent; the manager
  owns intake, validation, transport, storage, progress, and delivery.
- **Use the canonical boundaries.** Normalize browser-to-manager targets with
  `Brando.Uploads.AssetIntent` and serialize config targets with
  `Brando.Assets.ConfigTarget.serialize/1`; never hand-build target maps or config-target
  strings at call sites.
- **Commit through the owning context.** Pickers and the upload manager deliver assets to
  the established field/ref/var/gallery adapter; they do not mutate unrelated form or
  block state directly. Block refs continue through `Block.commit_ref_data/2`.
- **Gallery media configuration is per type.** Galleries may independently configure and
  restrict images and videos. A legacy flat gallery config remains the image config; do
  not silently apply it to video.

For processing after delivery, follow `lib/brando/images/processing.ex` (especially
`processing_queued?/1` before opportunistic requeueing) and the current Image/Vix
implementation in `lib/brando/images/processors/vix.ex`. Drawer-close duplicate
processing is covered by `test/brando_admin/components/form/drawer_close_test.exs`.
