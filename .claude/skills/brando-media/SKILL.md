---
name: brando-media
description: Work on Brando image processing, video providers, gallery records, media URLs, derivative generation, or CDN delivery. For picker and upload event wiring also read brando-uploads.
user-invocable: true
---

# Media processing and delivery

Paths are repository-relative. Read `docs/UPLOADER.md` and
[uploads](../brando-uploads/SKILL.md) for intake, intent, picker, and ownership
contracts. This skill covers what happens to the asset after intake.

## Image pipeline

- Field configuration enters through Blueprint assets and
  `lib/brando/assets/config_target.ex`. Stored image configuration is resolved
  by `lib/brando/images/config_resolver.ex`; use that boundary for low-level
  rendering rather than depending on the whole Images context.
- `lib/brando/images/processing.ex` queues work with tenant context.
  `lib/brando/workers/image_processor.ex` resolves configuration, creates and
  performs operations, updates sizes/formats/status, invokes CompletedCallback,
  queues CDN delivery, and broadcasts the result.
- The processor is `lib/brando/images/processors/vix.ex`, backed by Image/Vix
  and libvips. Sharp CLI and ImageMagick are not the current default pipeline.
  Operation planning and focal/crop calculations live under
  `lib/brando/images/operations/` and `lib/brando/images/crop.ex`.
- Opportunistic reprocessing should check `processing_queued?/1`; blindly
  replacing an executing job can produce concurrent writes to derivatives.

## Video, gallery, and CDN boundaries

- `lib/brando/videos/uploader.ex` and `lib/brando/videos/uploaders/` dispatch
  provider work. Read `guides/videos.md` for Mux, Bunny, Cloudflare, and local
  delivery setup. Provider readiness and upload availability are separate from
  selecting an already stored video.
- `lib/brando/galleries/gallery_object.ex` is the ordered usage record. Keep
  image/video configuration per type and captions/overrides with their owner.
  Copying a gallery must produce independent usage rows; see
  `test/brando/galleries/duplicate_gallery_test.exs`.
- `lib/brando/cdn/cdn.ex` resolves per-field or default S3 settings, queues
  uploads, and builds destination keys. Preserve tenant-qualified object paths.
- `lib/brando/cdn/client.ex` is a seam for HEAD/delete. Tests mocking it do not
  validate the real upload path, which uses ExAws directly.
- Use the existing media URL helpers; provider metadata, CDN paths, local paths,
  and processing status cannot be reduced to one string concatenation rule.

## Verification

Choose the affected tests in `test/brando/images/`, `test/brando/videos/`,
`test/brando/cdn/`, `test/brando/galleries/`, and `test/brando/media/`.
For UI deliveries test the visible result and saved/reloaded selection. Follow
AGENTS.md's consumer build and focused browser-test instructions for JS/CSS.
