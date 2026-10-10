# Map of `lib/brando_admin/components/form.ex`

The Form LiveComponent is one large file. Find an area here, then grep for the
names listed and read only that region. Names, not line numbers: the file
moves daily. A `def update(%{action: :name}` or `def update(%{event: "name"}`
clause is a message from a child component, `send_update/3` or the LiveView;
a `def handle_event("name"` clause is a browser event.

## Mount and load

`mount/1`, the catch-all `update(assigns, socket)`, `finish_form_update`
(`finish_form_fields` then `finish_form_blocks`), `open_entry` (read before
the first render; `@light_block_limit` decides whether the blocks come with
it), `run_load` (`start_async`, in-process on a sandboxed E2E server),
`handle_async` (`:blocks_load`, `:entry_load`), `put_loaded_blocks`,
`entry_not_found`, `action: :render_blocks`. `blocks_ready?` false: fields
read-only, Save and recovery copies wait. Fixed per mount:
`assign_addon_statuses`, `assign_header`, `assign_transformer_statuses`
(initialised once on purpose), `assign_default_params`.

## Params to changeset, and the form assign

`cast_entry_params` is the one place params become a changeset. Server-owned
asset fields: the `-- Server-owned asset fields --` comment, `own_asset`,
`own_changed_assets`, `reapply_owned_assets`. Writing the form: `put_form`,
`assign_form`, `assign_refreshed_form`, `assign_block_map` (hidden block
fields), `assign_header_status`. Events: `"validate"`, `"commit_tiptap"`.

## Entry field sync between editors

`ship_all_field_changes`, `do_ship_field_changes`, `unsynced_field_keys`,
`mark_synced`, `reverted_fields`, `broadcast_dirty_fields`, `clear_dirty_fields`;
receiving: `event: "apply_remote_field_changes"`, `apply_field_change`;
focus locks: `handle_event("focus"`, `"blur"`, `event: "reship_active_field"`.
Once #3071 lands this section is headed "Entry field sync" and server-side
writes go through `put_local_form/2`.

## Messages from children (`update/2` clauses)

- Relations and whole-changeset writes: `action: :update_entry_relation`,
  `:update_changeset`, `:update_entry`, `:update_entry_hard_reset`,
  `:refresh_entry`, `event: "append_embed"`, subform ops (`SubformHelpers.apply_op`).
- Revisions and translations: `action: :load_working_copy`, `:apply_translation`,
  `apply_restored_changeset`.
- Asset delivery from the UploadManager: `event: "entry_field_upload_complete"`,
  `deliver_entry_field_asset`, `commit_entry_field_asset`, `commit_selected_asset`;
  galleries: `action: :put_gallery`, `append_gallery_object`, `put_gallery_at`,
  `forget_unsaved_objects`.
- Drawers: `action: :update_edit_image` / `:update_edit_file` / `:update_edit_video`,
  `:open_image_editor_from_picker`, `:open_video_drawer`, video upload actions
  (`:get_video_upload_url`, `:video_upload_progress`, `:video_upload_complete`).
- Drafts: `event: "draft_dirty"`, `"draft_part"`, `"draft_timeout"`, `handle_event("draft_`.

## Blocks, save collection and live preview

`event_tag_received` (every clause: block roots, transformer data, preview
updates), `event: "provide_root_blocks"`, `"provide_transformer_data"`,
`fetch_root_blocks`, `collect_for_save`, `recollect_blocks`,
`event: "entry_blocks_reloaded"`, `reload_all_blocks`. Preview:
`initialize_block_live_preview`, `render_preview_update`,
`event: "update_live_preview"` / `"update_live_preview_block"` / `"flush_live_preview"`,
`handle_event("open_live_preview"`, `"recover_live_preview_state"`,
`maybe_finish_live_preview_recovery`. Blocks reading entry fields:
`event: "register_block_wanting_entry"`, `assign_entry_for_blocks`,
`send_updated_entry_field_to_blocks`.

## Save

`handle_event("save_form"`, the `handle_event("save"` clauses, `save_entry`,
`mutation_opts`, `saved_entry_with_blocks`, `refresh_saved_entry_with_blocks`,
`redirect_after_save`, `assoc_all_block_fields`, `assoc_all_transformer_fields`,
`fetch_transformer_data`, `reset_transformer_changesets`, `push_errors`,
`group_constraint_items`, `store_revision`, `maybe_offer_permalink_redirect`,
`after_translation_save`.

## Image, video and file drawers

`handle_event("open_image_editor"`, `"validate_image"`, `"save_image"`,
`"validate_video"`, `"save_video"`, `"validate_file"`, `"save_file"`,
`"recover_drawer_state"`, `restore_image_drawer` (and video, file),
`assign_drawer_recovery_state`, `handle_image_editor_upload_progress`,
`start_provider_video_upload`, `requeue_processing?`, `build_crop_groups`.

## Render

`render/1` (four clauses: skeletons while `entry_loading?`, frontend edit,
the form; `EntrySkeleton` draws the loading states), `toolbar_more`, `form_presences`, `follow_frame`, `form_tabs`,
`tab_fields`, `live_preview/1`.

## AI

`handle_event("tiptap_ai_generate"`, `"suggest_alt_text"`, `"suggest_entry_alt_text"`,
`event: "suggest_ref_alt_text"`, `fetch_field_ai_opts`, `build_ai_prompt`.
