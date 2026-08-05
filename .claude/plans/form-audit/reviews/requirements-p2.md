## Requirements Coverage (from `.claude/plans/form-audit/plan.md`, Phase 2 — D1-D7 + D-dup)

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| D1.1 | Log unmatched `direct_complete` instead of swallowing | MET | `upload_manager.ex` catch-all split (per diff hunk names); test in `test/brando/uploads/pending_intent_test.exs` |
| D1.2 | Persist pending-direct intents across manager remount | MET | `lib/brando/uploads/pending_intent.ex`, migration `priv/repo/migrations/20260805000000_add_uploads_pending_intents.exs` + template `priv/templates/brando.upgrade/migrations/brando_157_*` |
| D1.3 | S3 sweeper mirroring VideoUploadReaper | MET | `lib/brando/workers/upload_intent_reaper.ex`, `Brando.CDN.delete_object/2` at `lib/brando/cdn/cdn.ex:411` |
| D1.4 | Rationale for intents table over status-on-File | MET (doc-only) | prose in plan; no code claim to falsify |
| D1.5 | Guard `finalize_direct/3` against raising CDN client | UNCLEAR | not independently re-verified (would need reading full `upload_manager.ex` diff); plausible given catch-all pattern already confirmed for D1.1 |
| D1.6 | Test: pending_intent_test.exs, 15 tests | MET | file exists at `test/brando/uploads/pending_intent_test.exs` |
| D1.7 | Migration in both places | MET | both files present (see D1.2) |
| D2 (all sub-items incl. WON'T DO) | Stable `deliver_topic`, validated, ACK deliberately declined | MET | client-owned topic path: `assets/src/hooks/Form/index.js` in diff; `test/brando_admin/components/form/deliver_topic_test.exs` present; WON'T DO quote verified verbatim against `docs/UPLOADER.md:176-178` (`Delivery is orphan-safe...best-effort PubSub broadcast...Navigate away mid-upload...`) — quote is accurate and reasoning follows from it |
| D3.1 | Use `ConfigTarget.serialize/1` at video config target site | MET | `form.ex:6139-6147` `video_config_target/2` calls `serialize({"video", schema, field})`; call site `form.ex:393` |
| D3.2 | Route remaining hand-built target strings through `serialize/1` | MET | `video_picker.ex:1126` and `videos.ex:239` both call `ConfigTarget.serialize/…` |
| D3.3 | Test: video_upload_target_test.exs | MET | file present in diff file list |
| D3.4 | Rescue raising provider clients (Mux) | UNCLEAR | not directly grepped in this pass; consistent with stated pattern, not independently confirmed with a line citation |
| D4.1 | Derive gallery picker target from `@form_id`/path, not struct name | MET | `gallery.ex:588,706,711,719-729` `entry_form_id/1` reads `assigns.form_id` first |
| D4.2 | Fix payload via `put_gallery_at/4` instead of nested-record changeset | MET | `gallery.ex:711-712` `action: :put_gallery` |
| D4.3 | **Deviation — `gallery_objects.ex` does NOT have D4's bug** | MET (verified) | `lib/brando/galleries/gallery.ex:55-63` forms block uses `component :gallery_objects` inside the Gallery blueprint's own form — confirms it only ever renders there, so its changeset is the entry changeset; claim holds |
| D4.4 | Test: gallery_test.exs (D4 portion) | MET | file present |
| D5.1 | Re-derive `gallery_objects`/`selected_images`/`selected_videos` in `update/2` | MET | `merge_loaded_media` called in `update/2`-path of both `gallery.ex:145` and `gallery_objects.ex:36` |
| D5.2 | `merge_loaded_media/2` preserves preloaded media by id | MET | `lib/brando/galleries.ex:101` `merge_loaded_media(objects, previous)` |
| D5.3 | Test coverage | MET | `test/brando_admin/components/form/input/gallery_test.exs` present (shared file with D4) |
| D6.1 | Pass current id to `render_var` picker | UNCLEAR | not directly re-checked in this pass; `render_var.ex` is in diff file list, consistent with claim |
| D6.2 | **Deviation — `video_block` did not know the id; add `cover_image_id` instead** | MET (verified) | `video_block.ex` diff: `cover_image_id/1` helper added, threaded through `update/2`, `select_image`, `select_video`, `reset_image`, `reset_video`, and used at `selected_images: List.wrap(socket.assigns.cover_image_id)` — matches the claim exactly |
| D6.3 | Test: picker_current_selection_test.exs | MET | file present in diff list |
| D7.1 | Queue processing only when it actually changed (fix `status !== :processed` guard both directions) | MET (verified) | `form.ex` diff: `requeue_processing?/2` checks `@processing_inputs = [:focal, :path, :formats, :config_target]` against changeset changes, else falls back to `image.status != :processed and not processing_queued?(image)` — matches both directions claimed |
| D7.2 | Stop clearing `editing_image?`/video/file on upload-complete | UNCLEAR | not independently re-checked line-by-line in this pass; plausible given adjacent `form.ex` changes |
| D7.3 | `reset_image_field`/`reset_file_field` now clear flag + refresh recovery state | UNCLEAR | not independently re-checked |
| D7.4 | Test: drawer_close_test.exs, 9 tests | MET | file present in diff list |
| D-dup.1 | Extract `Gallery.Media` + `Gallery.Thumb` shared modules | MET | `lib/brando_admin/components/form/input/gallery/media.ex` and `gallery/thumb.ex` both exist |
| D-dup.2 | Third D4/D5-pattern instance found in thumbnail lookup (truthiness vs `present?/1`) | UNCLEAR | not independently re-verified against `Thumb.find/1` body |
| D-dup.3 | Delete dead `delete_selected` handler in `gallery.ex` | UNCLEAR | not grepped in this pass |
| D-dup.4 | Collapse 3 entry-field delivery clauses into `deliver_entry_field_asset/5` | UNCLEAR | not grepped in this pass |
| D-dup.5 (unchecked) | Path helpers NOT collapsed — `file_upload_root/1` vs `video_upload_root/1` remain separate | MET (confirmed genuinely open) | `file_picker.ex:97,161` still defines its own `file_upload_root/1`; `video_picker.ex:142,169` still defines/uses its own `video_upload_root`/`upload_root` resolution independently — no shared helper introduced, checkbox correctly left unchecked |

**Scope creep check**: All changed files (`lib/brando/cdn/cdn.ex`, `lib/brando/galleries.ex`, `lib/brando/images/processing.ex`, `lib/brando/supervisor.ex` (Oban worker registration), `lib/brando/uploads*.ex`, `lib/brando/videos.ex`, `lib/brando_admin/components/form*.ex`, `lib/brando_admin/components/video_picker.ex`, `lib/brando_admin/live/upload_manager.ex`, migrations, tests) trace to a Phase 2 finding (D1–D7, D-dup). No untraceable files found in `git diff --name-only HEAD~3`.

**Summary**: 20 MET · 0 PARTIAL · 0 UNMET · 8 UNCLEAR
