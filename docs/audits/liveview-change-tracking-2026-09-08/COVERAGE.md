# Coverage inventory

This inventory records all files found by the source/HEEx scan. There are 601
HEEx templates across the `lib/` and `e2e/lib/` entries below. Zero-template
entries include shared setup, embedded-template owners, and broad-search supporting
modules; their inclusion does not imply they are LiveViews.

The audit covered all 46 modules under `lib/brando_admin/live/`, all 48
LiveComponent files under `lib/brando_admin/components/`, and nine E2E LiveViews.
Generator inputs were reviewed as source rather than passed through HEEx before
generator substitution.

Checks: assign bookkeeping, HEEx dependencies and spreads, render-time state
reads, lifecycle-derived caches, component identity, streams, ignored DOM and
hook synchronization. Findings and qualifications are in [AUDIT.md](AUDIT.md).
A dash means no additional actionable finding was established, not full runtime
coverage of that file.

| Source | HEEx templates | Finding / note |
| --- | ---: | --- |
| [lib/brando/blueprint/listings/components.ex](../../../lib/brando/blueprint/listings/components.ex) | 0 | Supporting source / setup |
| [lib/brando/blueprint/listings/components/children.ex](../../../lib/brando/blueprint/listings/components/children.ex) | 1 | — |
| [lib/brando/blueprint/listings/components/core.ex](../../../lib/brando/blueprint/listings/components/core.ex) | 3 | — |
| [lib/brando/blueprint/listings/components/cover.ex](../../../lib/brando/blueprint/listings/components/cover.ex) | 1 | — |
| [lib/brando/content/container.ex](../../../lib/brando/content/container.ex) | 1 | — |
| [lib/brando/content/module.ex](../../../lib/brando/content/module.ex) | 2 | — |
| [lib/brando/content/module_set.ex](../../../lib/brando/content/module_set.ex) | 1 | — |
| [lib/brando/content/palette.ex](../../../lib/brando/content/palette.ex) | 1 | — |
| [lib/brando/content/table_template.ex](../../../lib/brando/content/table_template.ex) | 1 | — |
| [lib/brando/content/template.ex](../../../lib/brando/content/template.ex) | 1 | — |
| [lib/brando/files.ex](../../../lib/brando/files.ex) | 0 | Supporting source / setup |
| [lib/brando/files/file.ex](../../../lib/brando/files/file.ex) | 1 | — |
| [lib/brando/galleries.ex](../../../lib/brando/galleries.ex) | 0 | Supporting source / setup |
| [lib/brando/galleries/gallery.ex](../../../lib/brando/galleries/gallery.ex) | 1 | — |
| [lib/brando/html.ex](../../../lib/brando/html.ex) | 42 | — |
| [lib/brando/html/i18n.ex](../../../lib/brando/html/i18n.ex) | 2 | — |
| [lib/brando/html/icon.ex](../../../lib/brando/html/icon.ex) | 1 | — |
| [lib/brando/html/images.ex](../../../lib/brando/html/images.ex) | 15 | — |
| [lib/brando/html/video.ex](../../../lib/brando/html/video.ex) | 9 | — |
| [lib/brando/images.ex](../../../lib/brando/images.ex) | 0 | Supporting source / setup |
| [lib/brando/images/image.ex](../../../lib/brando/images/image.ex) | 1 | — |
| [lib/brando/json_ld/html.ex](../../../lib/brando/json_ld/html.ex) | 3 | — |
| [lib/brando/meta/html.ex](../../../lib/brando/meta/html.ex) | 4 | — |
| [lib/brando/navigation/menu.ex](../../../lib/brando/navigation/menu.ex) | 1 | — |
| [lib/brando/pages/page.ex](../../../lib/brando/pages/page.ex) | 4 | — |
| [lib/brando/pages/pages.ex](../../../lib/brando/pages/pages.ex) | 0 | Supporting source / setup |
| [lib/brando/sites/global_set.ex](../../../lib/brando/sites/global_set.ex) | 1 | — |
| [lib/brando/sites/preview.ex](../../../lib/brando/sites/preview.ex) | 1 | — |
| [lib/brando/sites/seo.ex](../../../lib/brando/sites/seo.ex) | 1 | — |
| [lib/brando/ssg/preview_controller.ex](../../../lib/brando/ssg/preview_controller.ex) | 0 | Supporting source / setup |
| [lib/brando/system.ex](../../../lib/brando/system.ex) | 0 | Supporting source / setup |
| [lib/brando/users/user.ex](../../../lib/brando/users/user.ex) | 2 | — |
| [lib/brando/users/users.ex](../../../lib/brando/users/users.ex) | 0 | Supporting source / setup |
| [lib/brando/videos.ex](../../../lib/brando/videos.ex) | 0 | Supporting source / setup |
| [lib/brando/videos/video.ex](../../../lib/brando/videos/video.ex) | 1 | — |
| [lib/brando/villain/components.ex](../../../lib/brando/villain/components.ex) | 12 | — |
| [lib/brando/villain/filters.ex](../../../lib/brando/villain/filters.ex) | 8 | — |
| [lib/brando/villain/heex_renderer.ex](../../../lib/brando/villain/heex_renderer.ex) | 0 | Supporting source / setup |
| [lib/brando/villain/parser.ex](../../../lib/brando/villain/parser.ex) | 6 | — |
| [lib/brando/villain/tags/inspect.ex](../../../lib/brando/villain/tags/inspect.ex) | 1 | — |
| [lib/brando/villain/tags/picture.ex](../../../lib/brando/villain/tags/picture.ex) | 1 | — |
| [lib/brando/villain/tags/video.ex](../../../lib/brando/villain/tags/video.ex) | 1 | — |
| [lib/brando_admin.ex](../../../lib/brando_admin.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/api/content/upload/image_controller.ex](../../../lib/brando_admin/api/content/upload/image_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/components/assets/file_browser.ex](../../../lib/brando_admin/components/assets/file_browser.ex) | 5 | F7 |
| [lib/brando_admin/components/assets/media_field.ex](../../../lib/brando_admin/components/assets/media_field.ex) | 1 | — |
| [lib/brando_admin/components/authorization_tools.ex](../../../lib/brando_admin/components/authorization_tools.ex) | 1 | — |
| [lib/brando_admin/components/badge.ex](../../../lib/brando_admin/components/badge.ex) | 1 | — |
| [lib/brando_admin/components/child_listing_button.ex](../../../lib/brando_admin/components/child_listing_button.ex) | 1 | — |
| [lib/brando_admin/components/children_button.ex](../../../lib/brando_admin/components/children_button.ex) | 1 | — |
| [lib/brando_admin/components/circle_dropdown.ex](../../../lib/brando_admin/components/circle_dropdown.ex) | 1 | — |
| [lib/brando_admin/components/content.ex](../../../lib/brando_admin/components/content.ex) | 5 | — |
| [lib/brando_admin/components/content/list.ex](../../../lib/brando_admin/components/content/list.ex) | 17 | — |
| [lib/brando_admin/components/content/list/checklist.ex](../../../lib/brando_admin/components/content/list/checklist.ex) | 2 | — |
| [lib/brando_admin/components/content/list/row.ex](../../../lib/brando_admin/components/content/list/row.ex) | 18 | — |
| [lib/brando_admin/components/content/select_identifier.ex](../../../lib/brando_admin/components/content/select_identifier.ex) | 5 | F9 |
| [lib/brando_admin/components/content_language_switch.ex](../../../lib/brando_admin/components/content_language_switch.ex) | 1 | — |
| [lib/brando_admin/components/dashboard.ex](../../../lib/brando_admin/components/dashboard.ex) | 2 | — |
| [lib/brando_admin/components/dropdown_button.ex](../../../lib/brando_admin/components/dropdown_button.ex) | 1 | — |
| [lib/brando_admin/components/file_picker.ex](../../../lib/brando_admin/components/file_picker.ex) | 2 | — |
| [lib/brando_admin/components/form.ex](../../../lib/brando_admin/components/form.ex) | 7 | — |
| [lib/brando_admin/components/form/alternates_drawer.ex](../../../lib/brando_admin/components/form/alternates_drawer.ex) | 1 | — |
| [lib/brando_admin/components/form/block.ex](../../../lib/brando_admin/components/form/block.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/components/form/block/render.ex](../../../lib/brando_admin/components/form/block/render.ex) | 45 | F7; F2 identity path; render-time module lookup |
| [lib/brando_admin/components/form/block_field.ex](../../../lib/brando_admin/components/form/block_field.ex) | 1 | — |
| [lib/brando_admin/components/form/block_field/module_picker.ex](../../../lib/brando_admin/components/form/block_field/module_picker.ex) | 1 | — |
| [lib/brando_admin/components/form/block_field/outline.ex](../../../lib/brando_admin/components/form/block_field/outline.ex) | 4 | — |
| [lib/brando_admin/components/form/draft_recovery.ex](../../../lib/brando_admin/components/form/draft_recovery.ex) | 4 | — |
| [lib/brando_admin/components/form/fieldset.ex](../../../lib/brando_admin/components/form/fieldset.ex) | 1 | — |
| [lib/brando_admin/components/form/fieldset/field.ex](../../../lib/brando_admin/components/form/fieldset/field.ex) | 1 | — |
| [lib/brando_admin/components/form/file_drawer.ex](../../../lib/brando_admin/components/form/file_drawer.ex) | 1 | — |
| [lib/brando_admin/components/form/image_drawer.ex](../../../lib/brando_admin/components/form/image_drawer.ex) | 2 | — |
| [lib/brando_admin/components/form/input.ex](../../../lib/brando_admin/components/form/input.ex) | 28 | F4/F5; render-time palette lookup |
| [lib/brando_admin/components/form/input/blocks/file_block.ex](../../../lib/brando_admin/components/form/input/blocks/file_block.ex) | 1 | — |
| [lib/brando_admin/components/form/input/blocks/gallery_block.ex](../../../lib/brando_admin/components/form/input/blocks/gallery_block.ex) | 2 | — |
| [lib/brando_admin/components/form/input/blocks/gallery_block/object.ex](../../../lib/brando_admin/components/form/input/blocks/gallery_block/object.ex) | 3 | — |
| [lib/brando_admin/components/form/input/blocks/gallery_block/override_form.ex](../../../lib/brando_admin/components/form/input/blocks/gallery_block/override_form.ex) | 2 | — |
| [lib/brando_admin/components/form/input/blocks/map_block.ex](../../../lib/brando_admin/components/form/input/blocks/map_block.ex) | 1 | — |
| [lib/brando_admin/components/form/input/blocks/media_block.ex](../../../lib/brando_admin/components/form/input/blocks/media_block.ex) | 7 | — |
| [lib/brando_admin/components/form/input/blocks/picture_block.ex](../../../lib/brando_admin/components/form/input/blocks/picture_block.ex) | 1 | F2 |
| [lib/brando_admin/components/form/input/blocks/render_var.ex](../../../lib/brando_admin/components/form/input/blocks/render_var.ex) | 21 | F1; F8/F9 caller |
| [lib/brando_admin/components/form/input/blocks/svg_block.ex](../../../lib/brando_admin/components/form/input/blocks/svg_block.ex) | 1 | — |
| [lib/brando_admin/components/form/input/blocks/tiptap_link_dialog.ex](../../../lib/brando_admin/components/form/input/blocks/tiptap_link_dialog.ex) | 1 | — |
| [lib/brando_admin/components/form/input/blocks/video_block.ex](../../../lib/brando_admin/components/form/input/blocks/video_block.ex) | 1 | F2 |
| [lib/brando_admin/components/form/input/entries.ex](../../../lib/brando_admin/components/form/input/entries.ex) | 8 | Related cached identifier state; see follow-up notes |
| [lib/brando_admin/components/form/input/file.ex](../../../lib/brando_admin/components/form/input/file.ex) | 2 | — |
| [lib/brando_admin/components/form/input/gallery.ex](../../../lib/brando_admin/components/form/input/gallery.ex) | 5 | F6 |
| [lib/brando_admin/components/form/input/gallery/image_config.ex](../../../lib/brando_admin/components/form/input/gallery/image_config.ex) | 1 | — |
| [lib/brando_admin/components/form/input/gallery/image_preview.ex](../../../lib/brando_admin/components/form/input/gallery/image_preview.ex) | 1 | — |
| [lib/brando_admin/components/form/input/gallery/thumb.ex](../../../lib/brando_admin/components/form/input/gallery/thumb.ex) | 1 | Local template binding |
| [lib/brando_admin/components/form/input/gallery/video_config.ex](../../../lib/brando_admin/components/form/input/gallery/video_config.ex) | 1 | — |
| [lib/brando_admin/components/form/input/gallery_objects.ex](../../../lib/brando_admin/components/form/input/gallery_objects.ex) | 1 | — |
| [lib/brando_admin/components/form/input/globals.ex](../../../lib/brando_admin/components/form/input/globals.ex) | 1 | — |
| [lib/brando_admin/components/form/input/identity_type_config.ex](../../../lib/brando_admin/components/form/input/identity_type_config.ex) | 3 | — |
| [lib/brando_admin/components/form/input/image.ex](../../../lib/brando_admin/components/form/input/image.ex) | 2 | — |
| [lib/brando_admin/components/form/input/image/focal_point.ex](../../../lib/brando_admin/components/form/input/image/focal_point.ex) | 1 | — |
| [lib/brando_admin/components/form/input/link.ex](../../../lib/brando_admin/components/form/input/link.ex) | 1 | — |
| [lib/brando_admin/components/form/input/multi_select.ex](../../../lib/brando_admin/components/form/input/multi_select.ex) | 13 | F8 |
| [lib/brando_admin/components/form/input/select.ex](../../../lib/brando_admin/components/form/input/select.ex) | 5 | F8 |
| [lib/brando_admin/components/form/input/vars.ex](../../../lib/brando_admin/components/form/input/vars.ex) | 1 | — |
| [lib/brando_admin/components/form/input/video.ex](../../../lib/brando_admin/components/form/input/video.ex) | 5 | Local template binding |
| [lib/brando_admin/components/form/meta_drawer.ex](../../../lib/brando_admin/components/form/meta_drawer.ex) | 1 | — |
| [lib/brando_admin/components/form/module_props.ex](../../../lib/brando_admin/components/form/module_props.ex) | 3 | — |
| [lib/brando_admin/components/form/module_props/ref_block_form.ex](../../../lib/brando_admin/components/form/module_props/ref_block_form.ex) | 22 | — |
| [lib/brando_admin/components/form/primitives.ex](../../../lib/brando_admin/components/form/primitives.ex) | 11 | — |
| [lib/brando_admin/components/form/revisions_drawer.ex](../../../lib/brando_admin/components/form/revisions_drawer.ex) | 1 | — |
| [lib/brando_admin/components/form/scheduled_publishing_drawer.ex](../../../lib/brando_admin/components/form/scheduled_publishing_drawer.ex) | 1 | — |
| [lib/brando_admin/components/form/subform.ex](../../../lib/brando_admin/components/form/subform.ex) | 7 | — |
| [lib/brando_admin/components/form/subform/field.ex](../../../lib/brando_admin/components/form/subform/field.ex) | 1 | — |
| [lib/brando_admin/components/form/tab.ex](../../../lib/brando_admin/components/form/tab.ex) | 3 | — |
| [lib/brando_admin/components/form/transformer.ex](../../../lib/brando_admin/components/form/transformer.ex) | 7 | — |
| [lib/brando_admin/components/form/unused_notes.ex](../../../lib/brando_admin/components/form/unused_notes.ex) | 1 | — |
| [lib/brando_admin/components/form/var_layout.ex](../../../lib/brando_admin/components/form/var_layout.ex) | 3 | — |
| [lib/brando_admin/components/form/video_drawer.ex](../../../lib/brando_admin/components/form/video_drawer.ex) | 4 | — |
| [lib/brando_admin/components/global_tabs.ex](../../../lib/brando_admin/components/global_tabs.ex) | 2 | — |
| [lib/brando_admin/components/image.ex](../../../lib/brando_admin/components/image.ex) | 1 | — |
| [lib/brando_admin/components/image_picker.ex](../../../lib/brando_admin/components/image_picker.ex) | 2 | — |
| [lib/brando_admin/components/layouts.ex](../../../lib/brando_admin/components/layouts.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/components/pages/page_vars.ex](../../../lib/brando_admin/components/pages/page_vars.ex) | 1 | — |
| [lib/brando_admin/components/picker_helpers.ex](../../../lib/brando_admin/components/picker_helpers.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/components/split_dropdown.ex](../../../lib/brando_admin/components/split_dropdown.ex) | 2 | — |
| [lib/brando_admin/components/video_picker.ex](../../../lib/brando_admin/components/video_picker.ex) | 4 | — |
| [lib/brando_admin/components/workspace.ex](../../../lib/brando_admin/components/workspace.ex) | 2 | — |
| [lib/brando_admin/controllers/access_denied_controller.ex](../../../lib/brando_admin/controllers/access_denied_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/admin_controller.ex](../../../lib/brando_admin/controllers/admin_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/admin_html.ex](../../../lib/brando_admin/controllers/admin_html.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/environment_controller.ex](../../../lib/brando_admin/controllers/environment_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/error_html.ex](../../../lib/brando_admin/controllers/error_html.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/preview_controller.ex](../../../lib/brando_admin/controllers/preview_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/seo_controller.ex](../../../lib/brando_admin/controllers/seo_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/sitemap_controller.ex](../../../lib/brando_admin/controllers/sitemap_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/controllers/user_session_controller.ex](../../../lib/brando_admin/controllers/user_session_controller.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/live/chrome.ex](../../../lib/brando_admin/live/chrome.ex) | 3 | F3 |
| [lib/brando_admin/live/config/asset_live.ex](../../../lib/brando_admin/live/config/asset_live.ex) | 2 | — |
| [lib/brando_admin/live/config/cache_live.ex](../../../lib/brando_admin/live/config/cache_live.ex) | 3 | — |
| [lib/brando_admin/live/config/environment_live.ex](../../../lib/brando_admin/live/config/environment_live.ex) | 4 | — |
| [lib/brando_admin/live/config/global_set_form_live.ex](../../../lib/brando_admin/live/config/global_set_form_live.ex) | 1 | — |
| [lib/brando_admin/live/config/global_set_list_live.ex](../../../lib/brando_admin/live/config/global_set_list_live.ex) | 1 | — |
| [lib/brando_admin/live/config/identity_live.ex](../../../lib/brando_admin/live/config/identity_live.ex) | 1 | — |
| [lib/brando_admin/live/config/publishing_live.ex](../../../lib/brando_admin/live/config/publishing_live.ex) | 2 | — |
| [lib/brando_admin/live/config/scheduled_publishing_live.ex](../../../lib/brando_admin/live/config/scheduled_publishing_live.ex) | 2 | — |
| [lib/brando_admin/live/config/seo_live.ex](../../../lib/brando_admin/live/config/seo_live.ex) | 1 | — |
| [lib/brando_admin/live/config/site_live.ex](../../../lib/brando_admin/live/config/site_live.ex) | 2 | — |
| [lib/brando_admin/live/config/utils_live.ex](../../../lib/brando_admin/live/config/utils_live.ex) | 2 | — |
| [lib/brando_admin/live/content/container_form_live.ex](../../../lib/brando_admin/live/content/container_form_live.ex) | 1 | — |
| [lib/brando_admin/live/content/container_list_live.ex](../../../lib/brando_admin/live/content/container_list_live.ex) | 1 | — |
| [lib/brando_admin/live/content/module_form_live.ex](../../../lib/brando_admin/live/content/module_form_live.ex) | 4 | — |
| [lib/brando_admin/live/content/module_set_form_live.ex](../../../lib/brando_admin/live/content/module_set_form_live.ex) | 1 | — |
| [lib/brando_admin/live/content/module_set_list_live.ex](../../../lib/brando_admin/live/content/module_set_list_live.ex) | 1 | — |
| [lib/brando_admin/live/content/modules_list_live.ex](../../../lib/brando_admin/live/content/modules_list_live.ex) | 1 | — |
| [lib/brando_admin/live/content/palette_form_live.ex](../../../lib/brando_admin/live/content/palette_form_live.ex) | 1 | — |
| [lib/brando_admin/live/content/palette_list_live.ex](../../../lib/brando_admin/live/content/palette_list_live.ex) | 1 | — |
| [lib/brando_admin/live/content/shared_library_live.ex](../../../lib/brando_admin/live/content/shared_library_live.ex) | 5 | Local template bindings |
| [lib/brando_admin/live/content/table_template_form_live.ex](../../../lib/brando_admin/live/content/table_template_form_live.ex) | 1 | — |
| [lib/brando_admin/live/content/table_template_list_live.ex](../../../lib/brando_admin/live/content/table_template_list_live.ex) | 1 | — |
| [lib/brando_admin/live/content/template_form_live.ex](../../../lib/brando_admin/live/content/template_form_live.ex) | 1 | — |
| [lib/brando_admin/live/content/template_list_live.ex](../../../lib/brando_admin/live/content/template_list_live.ex) | 1 | — |
| [lib/brando_admin/live/files/file_list_live.ex](../../../lib/brando_admin/live/files/file_list_live.ex) | 1 | — |
| [lib/brando_admin/live/galleries/gallery_form_live.ex](../../../lib/brando_admin/live/galleries/gallery_form_live.ex) | 1 | — |
| [lib/brando_admin/live/galleries/gallery_list_live.ex](../../../lib/brando_admin/live/galleries/gallery_list_live.ex) | 1 | — |
| [lib/brando_admin/live/globals/globals_live.ex](../../../lib/brando_admin/live/globals/globals_live.ex) | 1 | — |
| [lib/brando_admin/live/images/image_form_live.ex](../../../lib/brando_admin/live/images/image_form_live.ex) | 1 | — |
| [lib/brando_admin/live/images/image_list_live.ex](../../../lib/brando_admin/live/images/image_list_live.ex) | 1 | — |
| [lib/brando_admin/live/nav.ex](../../../lib/brando_admin/live/nav.ex) | 1 | — |
| [lib/brando_admin/live/navigation/item_form_live.ex](../../../lib/brando_admin/live/navigation/item_form_live.ex) | 1 | — |
| [lib/brando_admin/live/navigation/menu_form_live.ex](../../../lib/brando_admin/live/navigation/menu_form_live.ex) | 1 | — |
| [lib/brando_admin/live/navigation/menu_list_live.ex](../../../lib/brando_admin/live/navigation/menu_list_live.ex) | 1 | — |
| [lib/brando_admin/live/pages/fragment_form_live.ex](../../../lib/brando_admin/live/pages/fragment_form_live.ex) | 1 | — |
| [lib/brando_admin/live/pages/page_form_live.ex](../../../lib/brando_admin/live/pages/page_form_live.ex) | 1 | — |
| [lib/brando_admin/live/pages/page_list_live.ex](../../../lib/brando_admin/live/pages/page_list_live.ex) | 1 | — |
| [lib/brando_admin/live/upload_manager.ex](../../../lib/brando_admin/live/upload_manager.ex) | 1 | — |
| [lib/brando_admin/live/user_login_live.ex](../../../lib/brando_admin/live/user_login_live.ex) | 5 | — |
| [lib/brando_admin/live/users/groups_live.ex](../../../lib/brando_admin/live/users/groups_live.ex) | 4 | — |
| [lib/brando_admin/live/users/user_form_live.ex](../../../lib/brando_admin/live/users/user_form_live.ex) | 1 | — |
| [lib/brando_admin/live/users/user_list_live.ex](../../../lib/brando_admin/live/users/user_list_live.ex) | 1 | — |
| [lib/brando_admin/live/users/user_update_password_live.ex](../../../lib/brando_admin/live/users/user_update_password_live.ex) | 1 | — |
| [lib/brando_admin/live/videos/video_form_live.ex](../../../lib/brando_admin/live/videos/video_form_live.ex) | 1 | — |
| [lib/brando_admin/live/videos/video_list_live.ex](../../../lib/brando_admin/live/videos/video_list_live.ex) | 1 | — |
| [lib/brando_admin/live_view/form.ex](../../../lib/brando_admin/live_view/form.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/live_view/form/compiler.ex](../../../lib/brando_admin/live_view/form/compiler.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/live_view/listing.ex](../../../lib/brando_admin/live_view/listing.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/live_view/listing/compiler.ex](../../../lib/brando_admin/live_view/listing/compiler.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/utils.ex](../../../lib/brando_admin/utils.ex) | 0 | Supporting source / setup |
| [lib/brando_web.ex](../../../lib/brando_web.ex) | 0 | Supporting source / setup |
| [lib/brando_admin/components/content/list.html.heex](../../../lib/brando_admin/components/content/list.html.heex) | 1 | — |
| [lib/brando_admin/components/layouts/app.html.heex](../../../lib/brando_admin/components/layouts/app.html.heex) | 1 | — |
| [lib/brando_admin/components/layouts/auth.html.heex](../../../lib/brando_admin/components/layouts/auth.html.heex) | 1 | — |
| [lib/brando_admin/components/layouts/live.html.heex](../../../lib/brando_admin/components/layouts/live.html.heex) | 1 | — |
| [lib/brando_admin/components/layouts/live_child.html.heex](../../../lib/brando_admin/components/layouts/live_child.html.heex) | 1 | — |
| [lib/brando_admin/components/layouts/root.html.heex](../../../lib/brando_admin/components/layouts/root.html.heex) | 1 | — |
| [lib/brando_admin/controllers/admin_html/sidebar.html.heex](../../../lib/brando_admin/controllers/admin_html/sidebar.html.heex) | 1 | — |
| [lib/brando_admin/controllers/error_html/400.html.heex](../../../lib/brando_admin/controllers/error_html/400.html.heex) | 1 | — |
| [lib/brando_admin/controllers/error_html/404.html.heex](../../../lib/brando_admin/controllers/error_html/404.html.heex) | 1 | — |
| [lib/brando_admin/controllers/error_html/406.html.heex](../../../lib/brando_admin/controllers/error_html/406.html.heex) | 1 | — |
| [lib/brando_admin/controllers/error_html/500.html.heex](../../../lib/brando_admin/controllers/error_html/500.html.heex) | 1 | — |
| [e2e/lib/e2e_project/presence.ex](../../../e2e/lib/e2e_project/presence.ex) | 0 | Supporting source / setup |
| [e2e/lib/e2e_project/prices/price_category.ex](../../../e2e/lib/e2e_project/prices/price_category.ex) | 2 | — |
| [e2e/lib/e2e_project/projects/category.ex](../../../e2e/lib/e2e_project/projects/category.ex) | 2 | — |
| [e2e/lib/e2e_project/projects/client.ex](../../../e2e/lib/e2e_project/projects/client.ex) | 2 | — |
| [e2e/lib/e2e_project/projects/project.ex](../../../e2e/lib/e2e_project/projects/project.ex) | 2 | — |
| [e2e/lib/e2e_project/projects/project_category.ex](../../../e2e/lib/e2e_project/projects/project_category.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/dashboard_live.ex](../../../e2e/lib/e2e_project_admin/live/dashboard_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/prices/price_category_form_live.ex](../../../e2e/lib/e2e_project_admin/live/prices/price_category_form_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/prices/price_category_list_live.ex](../../../e2e/lib/e2e_project_admin/live/prices/price_category_list_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/projects/category_form_live.ex](../../../e2e/lib/e2e_project_admin/live/projects/category_form_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/projects/category_list_live.ex](../../../e2e/lib/e2e_project_admin/live/projects/category_list_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/projects/client_form_live.ex](../../../e2e/lib/e2e_project_admin/live/projects/client_form_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/projects/client_list_live.ex](../../../e2e/lib/e2e_project_admin/live/projects/client_list_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/projects/project_form_live.ex](../../../e2e/lib/e2e_project_admin/live/projects/project_form_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/live/projects/project_list_live.ex](../../../e2e/lib/e2e_project_admin/live/projects/project_list_live.ex) | 1 | — |
| [e2e/lib/e2e_project_admin/menus.ex](../../../e2e/lib/e2e_project_admin/menus.ex) | 0 | Supporting source / setup |
| [e2e/lib/e2e_project_web.ex](../../../e2e/lib/e2e_project_web.ex) | 0 | Supporting source / setup |
| [e2e/lib/e2e_project_web/components/core_components.ex](../../../e2e/lib/e2e_project_web/components/core_components.ex) | 16 | — |
| [e2e/lib/e2e_project_web/controllers/category_html.ex](../../../e2e/lib/e2e_project_web/controllers/category_html.ex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/client_html.ex](../../../e2e/lib/e2e_project_web/controllers/client_html.ex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/project_html.ex](../../../e2e/lib/e2e_project_web/controllers/project_html.ex) | 1 | — |
| [e2e/lib/e2e_project_web/components/layouts/app.html.heex](../../../e2e/lib/e2e_project_web/components/layouts/app.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/components/layouts/bare.html.heex](../../../e2e/lib/e2e_project_web/components/layouts/bare.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/components/layouts/lockdown.html.heex](../../../e2e/lib/e2e_project_web/components/layouts/lockdown.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/components/partials/footer.html.heex](../../../e2e/lib/e2e_project_web/components/partials/footer.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/components/partials/logo.html.heex](../../../e2e/lib/e2e_project_web/components/partials/logo.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/components/partials/navigation.html.heex](../../../e2e/lib/e2e_project_web/components/partials/navigation.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/category_html/detail.html.heex](../../../e2e/lib/e2e_project_web/controllers/category_html/detail.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/category_html/list.html.heex](../../../e2e/lib/e2e_project_web/controllers/category_html/list.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/client_html/detail.html.heex](../../../e2e/lib/e2e_project_web/controllers/client_html/detail.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/client_html/list.html.heex](../../../e2e/lib/e2e_project_web/controllers/client_html/list.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/error_html/404.html.heex](../../../e2e/lib/e2e_project_web/controllers/error_html/404.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/error_html/500.html.heex](../../../e2e/lib/e2e_project_web/controllers/error_html/500.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/lockdown_html/index.html.heex](../../../e2e/lib/e2e_project_web/controllers/lockdown_html/index.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/page_html/default.html.heex](../../../e2e/lib/e2e_project_web/controllers/page_html/default.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/page_html/index.html.heex](../../../e2e/lib/e2e_project_web/controllers/page_html/index.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/page_html/listing_preview.html.heex](../../../e2e/lib/e2e_project_web/controllers/page_html/listing_preview.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/project_html/detail.html.heex](../../../e2e/lib/e2e_project_web/controllers/project_html/detail.html.heex) | 1 | — |
| [e2e/lib/e2e_project_web/controllers/project_html/list.html.heex](../../../e2e/lib/e2e_project_web/controllers/project_html/list.html.heex) | 1 | — |

## Generator/template sources

- [priv/templates/brando.gen.blueprint/blueprint.ex](../../../priv/templates/brando.gen.blueprint/blueprint.ex)
- [priv/templates/brando.gen.site/html.ex](../../../priv/templates/brando.gen.site/html.ex)
- [priv/templates/brando.gen.site/layouts.ex](../../../priv/templates/brando.gen.site/layouts.ex)
- [priv/templates/brando.gen/html.ex](../../../priv/templates/brando.gen/html.ex)
- [priv/templates/brando.gen/admin/list.ex](../../../priv/templates/brando.gen/admin/list.ex)
- [priv/templates/brando.gen/admin/form.ex](../../../priv/templates/brando.gen/admin/form.ex)
- [priv/templates/brando.install/lib/application_name_web/controllers/lockdown_html/index.html.heex](../../../priv/templates/brando.install/lib/application_name_web/controllers/lockdown_html/index.html.heex)
- [priv/templates/brando.install/lib/application_name_web/controllers/page_html/index.html.heex](../../../priv/templates/brando.install/lib/application_name_web/controllers/page_html/index.html.heex)
- [priv/templates/brando.install/lib/application_name_web/controllers/page_html/default.html.heex](../../../priv/templates/brando.install/lib/application_name_web/controllers/page_html/default.html.heex)
- [priv/templates/brando.install/lib/application_name_web/controllers/error_html/404.html.heex](../../../priv/templates/brando.install/lib/application_name_web/controllers/error_html/404.html.heex)
- [priv/templates/brando.install/lib/application_name_web/controllers/error_html/500.html.heex](../../../priv/templates/brando.install/lib/application_name_web/controllers/error_html/500.html.heex)
- [priv/templates/brando.install/lib/application_name_web/components/layouts/lockdown.html.heex](../../../priv/templates/brando.install/lib/application_name_web/components/layouts/lockdown.html.heex)
- [priv/templates/brando.install/lib/application_name_web/components/layouts/bare.html.heex](../../../priv/templates/brando.install/lib/application_name_web/components/layouts/bare.html.heex)
- [priv/templates/brando.install/lib/application_name_web/components/layouts/app.html.heex](../../../priv/templates/brando.install/lib/application_name_web/components/layouts/app.html.heex)
- [priv/templates/brando.install/lib/application_name_web/components/partials/navigation.html.heex](../../../priv/templates/brando.install/lib/application_name_web/components/partials/navigation.html.heex)
- [priv/templates/brando.install/lib/application_name_web/components/partials/logo.html.heex](../../../priv/templates/brando.install/lib/application_name_web/components/partials/logo.html.heex)
- [priv/templates/brando.install/lib/application_name_web/components/partials/footer.html.heex](../../../priv/templates/brando.install/lib/application_name_web/components/partials/footer.html.heex)
- [priv/templates/brando.install/lib/application_name_admin/live/dashboard_live.ex](../../../priv/templates/brando.install/lib/application_name_admin/live/dashboard_live.ex)

## JavaScript review boundary

The audit searched all `assets/src` hooks for persistent DOM mutation and examined
the hooks corresponding to ignored/streamed component markup. The detailed
checks included DatePicker, DateTimePicker, CodeEditor, TipTap, Block, BlockField,
Form, FocalPoint, ColorPicker, ImageEditor, ImagePickerGrid, VideoPickerGrid,
MapURLParser, the presence helpers, and the remount handlers in buildApplication.
This is not a general audit of every JavaScript feature or third-party dependency.
