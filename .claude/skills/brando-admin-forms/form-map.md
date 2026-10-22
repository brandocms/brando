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

`cast_entry_edit` is the one place params become a changeset (from `validate/3`,
which `"validate"`, `"commit_tiptap"` and `"recover_form"` all run;
`cast_entry_params` wraps it for the save paths). Server-owned asset fields:
the `-- Server-owned asset fields --` comment, `own_asset`,
`own_changed_assets`, `owned_params`, `reapply_owned_assets`. Writing the form:
`put_form` (every write; also sets `hidden_block_fields` and calls
`assign_header_status`), `assign_form`, `assign_refreshed_form`,
`maybe_assign_block_map` (on load) and `assign_block_map` (after a save and on
`event: "set_block_map"`).

## Entry field sync between editors

The `## Entry field sync` comment in form.ex defines the assigns
(`synced_values`, `unshipped_fields`, `replaced_values`, `held_remote`).
Shipping: `ship_all_field_changes`, `pending_changes`, `broadcast_field_changes`,
`event: "ship_field_changes"`, `ship_fields_to` (a joining tab), `announce_join`,
`sync_fields`, `unsynced_field_keys`. Marking edits: `take_local_edit`,
`mark_local`, `put_local_form`, `put_written_form`, `drop_echoes`, `keep_field`.
Receiving: `event: "apply_remote_field_changes"`, `receive_field_changes`,
`take_newer` (clocks), `apply_remote`, `apply_field_change`, `apply_held_remote`,
`mark_synced`. Recovery: `settle_edit`, `offline_fields`, `keep_received`,
`share_recovered`, `restore_saved`. Dirty markers: `broadcast_dirty_fields`,
`clear_dirty_fields`. Focus locks: `handle_event("focus"`, `"blur"`,
`event: "reship_active_field"`.
Another tab's save: `announce_save`, `event: "take_saved_entry"`,
`take_saved_entry`, `unsaved_edits`, `carry_edit`, `echo_value`,
`rebase_on_blocks`; relation edits: `edited_relations`, `mark_relations`,
`put_received_form`, `target_row`, and `Form.RelationRows` (`rows`,
`carry`, `take_row`).

## Messages from children (`update/2` clauses)

- Relations and whole-changeset writes: `action: :update_entry_relation`,
  `:update_changeset`, `:update_entry`, `:update_entry_hard_reset`,
  `:refresh_entry`, `event: "append_embed"`, subform ops (`action: :update_entries`,
  `SubformHelpers.apply_op`).
- Revisions and translations: `action: :load_working_copy`, `:apply_translation`,
  `apply_restored_changeset`.
- Asset delivery from the UploadManager: `event: "entry_field_upload_complete"`,
  `deliver_entry_field_asset`, `commit_entry_field_asset`, `commit_selected_asset`,
  `event: "clear_entry_field_asset"`; processing finished:
  `event: "entry_field_asset_processed"`, `"entry_gallery_image_processed"`;
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
`"run_field_action"`, `field_action_run`, `ai_context_fun`; from blocks and suggestion panels:
`event: "suggest_ref_alt_text"`, `"accept_field_action"`, `"accept_alt_suggestion"`.
Block fields a request reads are collected first: `with_ai_blocks`, `receive_ai_blocks`
(tag `{:ai_context, token}`).
