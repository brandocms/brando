defmodule BrandoAdmin.Authorization.Events do
  @moduledoc """
  What each admin event does, for a legacy `:user` account, which reads and
  exports and writes nothing but its own profile (`Brando.Authorization.Boundary`).
  A LiveView's events reach `refused_to_role?/3` through the hook
  `BrandoAdmin.Authorization` attaches, a LiveComponent's through
  `BrandoAdmin.Authorization.EventGuard`, and a block's through `Block.Events`.
  With groups the engine decides instead, and this table is not consulted.

  An event's class says what stands between it and the store:

    * `:read`: nothing leaves this LiveView process. Filling in a field counts:
      the changeset is the view's until a save.
    * `:own`: it stores only the acting account's own data.
    * `:checked`: it stores only through a function that decides by itself, and a
      `:user` needs it: for its own profile (refused otherwise), or to finish a
      provider upload (`video_upload_complete`) that `get_video_upload_url`, a
      write, authorized when the account could. The token signed then names the
      video, its creator and the request, and completing records that the file
      arrived. What the field does with the video stays in this form.
    * `:write`: anything else, refused for a `:user` here. Its context checks too
      when it is given an actor.

  An event that is not listed is a `:write`, so a forgotten event fails closed.
  `BrandoAdmin.Authorization.EventClassificationTest` reads the source and fails
  until each event is listed. For a new event, add its name to its module's list;
  the failure says which, and `:write` is right unless you have read the handler.

  A project's own admin LiveView or LiveComponent has no entry, so a `:user`'s
  events there are refused. It opens those that only read with
  `def __read_only_events__, do: ~w(open_tab)`.

  Module names are strings, as in `BrandoAdmin.Authorization`, so that this table
  gives no module a compile-time dependency on any view.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.Authorization.Boundary
  alias BrandoAdmin.Authorization

  # What these hooks take on behalf of the LiveViews they attach to. A view's
  # own entry answers first.
  @view_hooks ~w(
    BrandoAdmin.LiveView.Form.Hooks
    BrandoAdmin.LiveView.Form.Tabs
    BrandoAdmin.LiveView.Listing.Hooks
    BrandoAdmin.Reauth
  )

  # The pickers get these events from `use PickerHelpers`.
  @picker_helpers ~w(BrandoAdmin.Components.PickerHelpers)
  @pickers ~w(BrandoAdmin.Components.FilePicker BrandoAdmin.Components.ImagePicker BrandoAdmin.Components.VideoPicker)

  @table %{
    "BrandoAdmin.AI.AssistantLive" => [
      read:
        ~w(browse_library cancel_share close_preview draft preview preview_saved preview_target preview_version preview_viewport toggle_highlight toggle_history toggle_publish),
      own: ~w(cancel_run detach select_image select_video),
      write: ~w(apply cancel_proposal leave_out send share_page share_review undo)
    ],
    "BrandoAdmin.AI.GuidanceLive" => [
      read: ~w(copy discard draft restore),
      write: ~w(save)
    ],
    "BrandoAdmin.CalendarLive" => [
      read: ~w(cancel_move describe_move filter move_date start_move),
      write: ~w(move)
    ],
    "BrandoAdmin.CommandPaletteLive" => [
      read: ~w(close open search)
    ],
    "BrandoAdmin.Components.ChildrenButton" => [
      read: ~w(toggle)
    ],
    "BrandoAdmin.Components.Content.List" => [
      read:
        ~w(change_limit change_page clear_selection close_translation_dialog delete_filter export next_filter_key reset_filters select_row submit_filter toggle_boolean_filter update_filter update_select_filter update_sort update_status),
      write: ~w(sequenced)
    ],
    "BrandoAdmin.Components.Content.List.Row" => [
      read: ~w(toggle_children update_entry),
      write: ~w(remove_entry)
    ],
    "BrandoAdmin.Components.Content.List.SavedViews" => [
      read: ~w(apply close_dialog open_rename open_save validate),
      own: ~w(clear_default delete set_default submit update),
      write: ~w(share)
    ],
    "BrandoAdmin.Components.Content.SelectIdentifier" => [
      read: ~w(select_identifier select_schema)
    ],
    "BrandoAdmin.Components.ContentLanguageSwitch" => [
      read: ~w(hide_language_picker show_language_picker),
      own: ~w(select_language)
    ],
    "BrandoAdmin.Components.Form" => [
      read:
        ~w(blur browse_video_thumbnail change_preview_target close_preview_targets commit_tiptap draft_open draft_review focus keep_own_relation noop open_block_upload_folder_browser open_footnote open_image_editor open_own_image_editor push_submit push_submit_minor push_submit_new push_submit_redirect recover_drawer_state recover_form reset_file_field reset_image_field reset_video_field save_redirect_target select_tab set_video_aspect_ratio skip_permalink_redirect take_saved_relation tiptap_ai_cancel tiptap_link_dialog tiptap_link_result toggle_preview_targets toggle_revisions_drawer_status validate validate_file validate_image validate_video video_preview_dimensions),
      own:
        ~w(draft_capture draft_clean draft_discard draft_dismiss draft_restore draft_restore_compatible open_live_preview open_live_preview_standalone recover_live_preview_state refresh_live_preview select_preview_target),
      checked: ~w(save save_form),
      write:
        ~w(create_footnote create_permalink_redirect create_translation duplicate_image image_editor_save make_translation_independent make_translation_source reset_video_thumbnail run_field_action save_file save_image save_video save_video_authorized select_image share_link store_revision suggest_alt_text suggest_entry_alt_text tiptap_ai_generate)
    ],
    "BrandoAdmin.Components.Form.AltTextSuggestion" => [
      read: ~w(accept discard edit)
    ],
    "BrandoAdmin.Components.Form.AlternatesDrawer" => [
      read: ~w(get_entries_identifiers),
      write: ~w(remove_entry select_entry store_alternates)
    ],
    "BrandoAdmin.Components.Form.Block.Events" => [
      read:
        ~w(add_table_row assign_available_identifiers cancel_region_remap choose_region_remap close_block_config close_block_slot collapse_block commit_tiptap create_footnote delete_block delete_unused_collection delete_var duplicate_block fetch_missing_refs fetch_missing_vars focus insert_block insert_block_entry insert_slot_block move_block open_block_config open_block_slot open_footnote open_unused_collection paste_block paste_child_block remap_region reposition reset_ref reset_refs reset_var reset_vars restore_note_reference select_identifier show_dirty show_table_instructions show_vars_instructions tiptap_ai_cancel tiptap_link_dialog tiptap_link_result validate_block),
      own: ~w(copy_block),
      write: ~w(tiptap_ai_generate)
    ],
    "BrandoAdmin.Components.Form.BlockField" => [
      read:
        ~w(clear_block_bin collapse_multi_children collapse_root_blocks expand_multi_children expand_root_blocks insert_starting_module outline_reposition outline_root_reposition outline_scroll_to paste_block_at_end rebuild_outline recover_blocks reposition restore_block show_block_picker start_from_template undo_structure),
      own: ~w(clear_clipboard)
    ],
    "BrandoAdmin.Components.Form.BlockField.ModulePicker" => [
      read: ~w(clear_search close_modal insert_container insert_fragment insert_module search set_recent toggle_namespace)
    ],
    "BrandoAdmin.Components.Form.FieldActions" => [
      read: ~w(accept discard edit)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.FileBlock" => [
      read: ~w(focus reset_file select_file set_target)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock" => [
      read:
        ~w(close_text_editor focus open_image_editor open_text_editor open_video_picker save_object_text select_image select_video set_gallery_view set_target tiptap_link_dialog tiptap_link_result toggle_only_selected)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.MapBlock" => [
      read: ~w(url)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.MarkdownSourceBlock" => [
      read: ~w(accept_version preview refresh_versions)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.MediaBlock" => [
      read: ~w(select_block)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.PictureBlock" => [
      read: ~w(focus open_image_editor reset_image select_image set_target show_image_picker),
      write: ~w(suggest_alt_text)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.SvgBlock" => [
      read: ~w(drop_svg)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog" => [
      read: ~w(close_dialog confirm_link remove_link set_link_type validate_link)
    ],
    "BrandoAdmin.Components.Form.Input.Blocks.VideoBlock" => [
      read:
        ~w(focus open_video_picker reset_image reset_override reset_override_group reset_video select_image select_video set_target toggle_override upload_error video_upload_progress),
      checked: ~w(video_upload_complete),
      write: ~w(get_video_upload_url)
    ],
    "BrandoAdmin.Components.Form.Input.Entries" => [
      read: ~w(clear_all select_identifier select_schema)
    ],
    "BrandoAdmin.Components.Form.Input.File" => [
      read: ~w(browse_file open_file remove_file select_file)
    ],
    "BrandoAdmin.Components.Form.Input.FormFields" => [
      read: ~w(add_field add_option close_field duplicate_field remove_option reposition_vars set_width toggle_required)
    ],
    "BrandoAdmin.Components.Form.Input.Gallery" => [
      read:
        ~w(close_config_modal close_text_editor edit_image focus open_config_modal open_image_editor open_text_editor open_video_picker remove_object reposition save_object_text select_image select_video set_gallery_view set_target tiptap_link_dialog tiptap_link_result)
    ],
    "BrandoAdmin.Components.Form.Input.Gallery.ImageConfig" => [
      read: ~w(cancel_config focus reset_override save_config tiptap_link_dialog tiptap_link_result)
    ],
    "BrandoAdmin.Components.Form.Input.Gallery.VideoConfig" => [
      read:
        ~w(cancel_config change_config focus reset_override reset_override_group save_config tiptap_link_dialog tiptap_link_result toggle_override)
    ],
    "BrandoAdmin.Components.Form.Input.GalleryObjects" => [
      read: ~w(edit_image open_video_picker reposition select_image select_video set_target)
    ],
    "BrandoAdmin.Components.Form.Input.Globals" => [
      read: ~w(add_subentry force_validate remove_subentry sequenced_subform)
    ],
    "BrandoAdmin.Components.Form.Input.Image" => [
      read: ~w(browse_image open_image),
      checked: ~w(remove_image select_image)
    ],
    "BrandoAdmin.Components.Form.Input.Image.FocalPoint" => [
      read: ~w(update_focal_point)
    ],
    "BrandoAdmin.Components.Form.Input.MultiSelect" => [
      read:
        ~w(add_preset clear_invalid_options focus hide_form reset select_option show_form toggle_modal validate_new_entry),
      write: ~w(save_new_entry)
    ],
    "BrandoAdmin.Components.Form.Input.RenderVar" => [
      read:
        ~w(focus reset_file reset_gallery reset_image reset_video select_file set_file_target set_gallery_image_target set_gallery_video_target set_target set_video_target toggle_visible upload_error video_upload_progress),
      checked: ~w(video_upload_complete),
      write: ~w(get_video_upload_url remove_gallery_object select_image select_video)
    ],
    "BrandoAdmin.Components.Form.Input.Select" => [
      read:
        ~w(close_modal reset select_custom_value select_option toggle_inline_options toggle_modal update_custom_value validate_new_entry),
      write: ~w(save_new_entry)
    ],
    "BrandoAdmin.Components.Form.Input.Vars" => [
      read: ~w(add_subentry focus force_validate insert_subentry remove_subentry sequenced_subform)
    ],
    "BrandoAdmin.Components.Form.Input.Video" => [
      read: ~w(browse_video open_video remove_video select_video upload_error video_upload_progress),
      checked: ~w(video_upload_complete),
      write: ~w(get_video_upload_url)
    ],
    "BrandoAdmin.Components.Form.MetaPreviews" => [
      read: ~w(load)
    ],
    "BrandoAdmin.Components.Form.ModuleProps" => [
      read: ~w(add_select_var_option del_select_var_option focus toggle_col_var)
    ],
    "BrandoAdmin.Components.Form.NotesDrawer" => [
      read: ~w(cancel_compose compose new_note search tab toggle_thread),
      write: ~w(create reopen reply resolve)
    ],
    "BrandoAdmin.Components.Form.RevisionsDrawer" => [
      read: ~w(activity_more close_compare compare fetch_revisions load_more select_revision show_publish_at tab),
      write:
        ~w(activate_revision cancel_scheduled_revision delete_revision protect_revision purge_inactive_revisions schedule unprotect_revision)
    ],
    "BrandoAdmin.Components.Form.StructuredData" => [
      read: ~w(load select)
    ],
    "BrandoAdmin.Components.Form.Subform" => [
      read:
        ~w(add_subentry blur edit_subentry focus force_validate insert_subentry remove_subentry reposition sequenced_subform)
    ],
    "BrandoAdmin.Components.Form.Transformer" => [
      read:
        ~w(add_entry blur cancel_replacement clear_asset close_entry dismiss_upload_errors focus pick_asset register_batch register_replacement reject_files remove_entry reposition select_image select_video sequenced_subform sort_by_filename toggle_entry update_field upload_error validate video_upload_progress),
      checked: ~w(video_upload_complete),
      write: ~w(get_video_upload_url)
    ],
    "BrandoAdmin.Components.Form.UnusedNotes" => [
      read: ~w(open_unused_collection restore_note_reference),
      write: ~w(delete_unused_collection)
    ],
    "BrandoAdmin.Components.Form.VarLayout" => [
      read: ~w(hide_var move_var reposition_vars select_surface set_var_width show_var)
    ],
    "BrandoAdmin.Components.GlobalTabs" => [
      read: ~w(blur focus select_tab validate),
      write: ~w(submit)
    ],
    "BrandoAdmin.Components.ImagePicker" => [
      read:
        ~w(cancel_pending_upload clear_organize_selection confirm_block_upload_folder edit_image_from_picker load_more_images organize_select_image picker_closed picker_go_parent picker_go_root reopen search_images set_scope),
      write: ~w(delete_image_from_picker pick_library_image picker_move_to_folder)
    ],
    "BrandoAdmin.Components.ModuleFiles" => [
      read: ~w(cancel_upload export preview reset validate),
      write: ~w(apply refresh)
    ],
    "BrandoAdmin.Components.Pages.PageVars" => [
      read: ~w(add_subentry force_validate remove_subentry sequenced_subform toggle_advanced)
    ],
    "BrandoAdmin.Components.PickerHelpers" => [
      read: ~w(cancel_new_folder_form go_folder go_parent_folder go_recent_folder go_root show_new_folder_form),
      write: ~w(create_folder)
    ],
    "BrandoAdmin.Components.TwoFactor.PasskeySetup" => [
      read: ~w(error),
      own: ~w(options register)
    ],
    "BrandoAdmin.Components.TwoFactor.Setup" => [
      own: ~w(confirm)
    ],
    "BrandoAdmin.Components.VideoPicker" => [
      read:
        ~w(cancel_rename clear_organize_selection close_library close_video_player organize_select_video picker_go_parent picker_go_root play_video search_videos set_scope set_url_input start_rename toggle_url_input upload_error video_upload_progress),
      checked: ~w(video_upload_complete),
      write:
        ~w(add_from_library delete_video_from_picker get_video_upload_url more_library open_library picker_move_to_folder rename_video search_library url)
    ],
    "BrandoAdmin.Content.ModuleFormLive" => [
      read:
        ~w(blur cancel_destructive_save close_item_modal commit_tiptap create_ref create_var delete_ref delete_var duplicate_ref duplicate_var focus save_redirect_target select_tab tiptap_link_dialog tiptap_link_result validate),
      write: ~w(confirm_destructive_save generate_sketch save)
    ],
    "BrandoAdmin.Content.ModuleListLive" => [
      read:
        ~w(blur export_module_files export_modules focus open_module_files open_sketches reset_import_vars validate_module_import),
      write: ~w(create_module import_modules start_sketches)
    ],
    "BrandoAdmin.Content.SharedLibraryLive" => [
      read: ~w(refresh select_environment select_site),
      write: ~w(accept_update create customize delete disable_all dismiss_update enable_all reset set_access update)
    ],
    "BrandoAdmin.Content.StaleBlocksLive" => [
      read: ~w(cancel choose review),
      write: ~w(resolve)
    ],
    "BrandoAdmin.Files.FileListLive" => [
      read:
        ~w(assets_cancel_new_folder_form assets_clear_clipboard assets_cut_selected assets_go_folder assets_go_parent assets_go_recent assets_go_root assets_show_new_folder_form blur close_file_replacement focus replace_file sweep_close sweep_dismiss sweep_open validate),
      write:
        ~w(assets_create_folder assets_move_selected_to_folder assets_paste_selected delete_unused sweep_apply sweep_undo)
    ],
    "BrandoAdmin.Forms.SubmissionsLive" => [
      read: ~w(close filter_language load_more show),
      write: ~w(delete resend)
    ],
    "BrandoAdmin.FrontendEdit.EditorLive" => [
      read: ~w(reload select)
    ],
    "BrandoAdmin.Globals.GlobalsLive" => [
      read: ~w(blur focus)
    ],
    "BrandoAdmin.Images.AltTextLive" => [
      read: ~w(folder),
      write: ~w(accept_all_suggestions accept_suggestion describe reject_suggestion)
    ],
    "BrandoAdmin.Images.ImageListLive" => [
      read:
        ~w(assets_cancel_new_folder_form assets_clear_clipboard assets_cut_selected assets_go_folder assets_go_parent assets_go_recent assets_go_root assets_show_new_folder_form blur focus sweep_close sweep_dismiss sweep_open validate),
      write:
        ~w(assets_create_folder assets_move_selected_to_folder assets_paste_selected delete_unused sweep_apply sweep_undo)
    ],
    "BrandoAdmin.LiveView.Form.Hooks" => [
      read: ~w(block_blurred block_focused focus upload_error video_upload_progress),
      checked: ~w(video_upload_complete),
      write: ~w(get_video_upload_url)
    ],
    "BrandoAdmin.LiveView.Form.Tabs" => [
      own: ~w(brando_tab_claim)
    ],
    "BrandoAdmin.LiveView.Listing.Hooks" => [
      read: ~w(describe_delete edit_entry),
      write:
        ~w(create_entry_translation delete_entry delete_selected duplicate_entry duplicate_entry_to_language duplicate_selected_to_language rerender_entry set_status translate_entry_to_language undelete_entry)
    ],
    "BrandoAdmin.MCP.ConsentLive" => [
      read: ~w(deny return),
      write: ~w(approve)
    ],
    "BrandoAdmin.Nav" => [
      read: ~w(toggle toggle_nav)
    ],
    "BrandoAdmin.Pages.PageListLive" => [
      read: ~w(create_fragment create_subpage edit_fragment edit_subpage),
      write: ~w(delete_fragment duplicate_fragment)
    ],
    "BrandoAdmin.Reauth" => [
      read: ~w(brando:reauth:cancel brando:reauth:passkey_error brando:reauth:passkey_options),
      own: ~w(brando:reauth:passkey brando:reauth:submit)
    ],
    "BrandoAdmin.SearchLive" => [
      read: ~w(search)
    ],
    "BrandoAdmin.Sites.ActivityLive" => [
      read: ~w(close_compare compare filter filter_security load_more)
    ],
    "BrandoAdmin.Sites.AssetLive" => [
      read: ~w(refresh),
      write: ~w(activate deactivate)
    ],
    "BrandoAdmin.Sites.BlockAuditLive" => [
      read: ~w(select_all select_none toggle),
      write: ~w(remove restore)
    ],
    "BrandoAdmin.Sites.CacheLive" => [
      write: ~w(clear_cache_entry empty_caches)
    ],
    "BrandoAdmin.Sites.ContentTransferLive" => [
      read:
        ~w(cancel_import cancel_restore cancel_upload dependency_search destination_search edit_export export_options export_scope filter_type include_entry map_content map_definition_references map_dependencies map_entries new_import prepare_export preview_definitions read_bundle remove_entry review_restore search tab toggle_entry toggle_field validate_upload),
      write: ~w(apply_import install_definitions restore retry_refresh)
    ],
    "BrandoAdmin.Sites.EnvironmentLive" => [
      read: ~w(refresh),
      write:
        ~w(cancel_operation create_environment delete_environment prune_archives queue_copy queue_set_live rollback schedule_copy schedule_set_live update_domain)
    ],
    "BrandoAdmin.Sites.GlobalSetFormLive" => [
      read: ~w(add_select_var_option)
    ],
    "BrandoAdmin.Sites.MCPLive" => [
      write: ~w(disable enable revoke)
    ],
    "BrandoAdmin.Sites.MarkdownSourcesLive" => [
      read: ~w(edit history new select_documents source_mode validate),
      write: ~w(add_documents discover_folder save sync)
    ],
    "BrandoAdmin.Sites.NotificationsLive" => [
      read: ~w(replace_url validate),
      write: ~w(delete pause redeliver resume save send_test)
    ],
    "BrandoAdmin.Sites.PublishingLive" => [
      read: ~w(refresh),
      write: ~w(deploy request_build rollback save_deploy_config schedule_build)
    ],
    "BrandoAdmin.Sites.SEOLive" => [
      read: ~w(audit_scope cancel_batch confirm_batch redirect_404 sort tab toggle_picker toggle_row),
      write:
        ~w(accept_all_suggestions accept_suggestion create_redirect critique generate_description reject_suggestion rerun_audit start_batch toggle_context_field toggle_indexnow)
    ],
    "BrandoAdmin.Sites.ScheduledPublishingLive" => [
      read: ~w(refresh_jobs),
      write: ~w(delete_job)
    ],
    "BrandoAdmin.Sites.SiteLive" => [
      read: ~w(refresh),
      write: ~w(activate_site archive create_site delete grant revoke set_library_group suspend)
    ],
    "BrandoAdmin.Sites.UtilsLive" => [
      read:
        ~w(authorization_cancel_preview authorization_cancel_upload authorization_export authorization_preview authorization_report authorization_validate refresh),
      write:
        ~w(authorization_apply authorization_backfill generate_sitemap rebuild_search_index recalculate_dominant_colors recreate_changed_image_sizes recreate_image_sizes sync_identifiers)
    ],
    "BrandoAdmin.Sites.WebhooksLive" => [
      read: ~w(replace_url validate),
      write: ~w(delete pause redeliver resume rotate_secret save send_test)
    ],
    "BrandoAdmin.UploadManager" => [
      read:
        ~w(direct_progress dismiss_finished dismiss_item external_complete external_error external_progress external_track keep_new toggle validate_queue),
      own: ~w(cancel_item),
      checked: ~w(direct_complete direct_error intake use_existing)
    ],
    "BrandoAdmin.UserForgotPasswordLive" => [
      write: ~w(send)
    ],
    "BrandoAdmin.UserResetPasswordLive" => [
      read: ~w(validate),
      own: ~w(save)
    ],
    "BrandoAdmin.UserTwoFactorSetupLive" => [
      read: ~w(method)
    ],
    "BrandoAdmin.Users.GroupsLive" => [
      read:
        ~w(cancel_add_member cancel_review change clone close_effective discard effective new reload remove_retired review search_groups search_people select show_add_member tab toggle_resource),
      write: ~w(add_member delete remove_member save)
    ],
    "BrandoAdmin.Users.SignInPolicyLive" => [
      read: ~w(change),
      write: ~w(save)
    ],
    "BrandoAdmin.Users.UserFormLive" => [
      read: ~w(close_set_password open_set_password validate_set_password),
      write: ~w(log_out_everywhere reset_two_factor send_password_reset set_password)
    ],
    "BrandoAdmin.Users.UserListLive" => [
      read: ~w(cancel_delete delete_entry delete_user duplicate_entry select_transfer_user toggle_user_select),
      write: ~w(confirm_transfer_delete disable_user enable_user)
    ],
    "BrandoAdmin.Users.UserSecurityLive" => [
      read: ~w(ask_confirm close_modal new_passkey open_setup),
      own: ~w(confirm remove_passkey revoke_connected_app revoke_other_sessions revoke_session)
    ],
    "BrandoAdmin.Users.UserUpdatePasswordLive" => [
      read: ~w(validate),
      own: ~w(save)
    ],
    "BrandoAdmin.Videos.VideoListLive" => [
      read:
        ~w(assets_cancel_new_folder_form assets_clear_clipboard assets_cut_selected assets_go_folder assets_go_parent assets_go_recent assets_go_root assets_show_new_folder_form close_video play_video sweep_close sweep_dismiss sweep_open),
      write:
        ~w(assets_create_folder assets_move_selected_to_folder assets_paste_selected delete_unused fetch_metadata rename_video sweep_apply sweep_undo)
    ]
  }

  @doc "The table: module name to `class: [events]`."
  def table, do: @table

  @doc "The class the table gives `event` in the module named `name`, else nil."
  def declared_class(name, event) when is_binary(name) do
    @table
    |> Map.get(name, [])
    |> Enum.find_value(fn {class, events} -> if event in events, do: class end)
  end

  @doc "The class of `event` in the LiveView `view`, hooks included: unlisted events are writes."
  def class(view, event), do: class(view, event, @view_hooks)

  @doc "The class of `event` in the LiveComponent `module`: unlisted events are writes."
  def component_class(module, event) do
    class(module, event, if(inspect(module) in @pickers, do: @picker_helpers, else: []))
  end

  defp class(module, event, helpers) do
    cond do
      class = declared_class(inspect(module), event) -> class
      project_read_only?(module, event) -> :read
      class = Enum.find_value(helpers, &declared_class(&1, event)) -> class
      true -> :write
    end
  end

  defp project_read_only?(module, event) do
    Code.ensure_loaded?(module) and function_exported?(module, :__read_only_events__, 0) and
      event in module.__read_only_events__()
  end

  @doc """
  Whether `event` in the LiveView `view` is refused to an account of `role`: the
  role the hook that asks has just read, so that an event reads it once.
  """
  def refused_to_role?(view, event, role), do: role == :user and class(view, event) == :write

  @doc """
  Whether `event` in the LiveComponent `module` is refused to this process's
  account. No hook has read the role for a component's event. It is read only for
  a write, so typing into a form reads no role.
  """
  def component_refused?(module, event) do
    case Authorization.legacy_actor() do
      nil -> false
      actor -> component_class(module, event) == :write and Boundary.read_only_account?(actor)
    end
  end

  @doc """
  Tells the account, and changes nothing else. A component whose refused event
  also closes something in the browser defines `__event_refused__/2`, returning
  the socket for such an event, and nil for the others.
  """
  def refuse(socket, module \\ nil, event \\ nil) do
    closed = module && function_exported?(module, :__event_refused__, 2) && module.__event_refused__(event, socket)

    closed ||
      with %{id: _} = user <- Authorization.legacy_actor() do
        BrandoAdmin.Toast.send_to(user, gettext("You do not have permission for this action."), %{
          level: :error,
          type: :notification
        })

        socket
      end
  end
end
