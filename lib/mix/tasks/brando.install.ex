defmodule Mix.Tasks.Brando.Install do
  @shortdoc "Generates files for Brando."

  @moduledoc """
  Install Brando.
  """

  use Mix.Task

  import Mix.Generator

  @new [
    # Mix template
    {:eex, "mix.exs", "mix.exs"},

    # VERSION
    {:eex, "VERSION", "VERSION"},

    # README
    {:eex, "README.md", "README.md"},

    # Formatter
    {:eex, "formatter.exs", ".formatter.exs"},

    # Release cfg & setup
    {:eex, ".envrc", ".envrc"},
    {:eex, ".envrc.prod", ".envrc.prod"},
    {:eex, ".envrc.staging", ".envrc.staging"},
    {:eex, "rel/env.sh.eex", "rel/env.sh.eex"},
    {:eex, "rel/vm.args.eex", "rel/vm.args.eex"},
    {:eex, "lib/application_name/release_tasks.ex", "lib/application_name/release_tasks.ex"},

    # Brando migrator
    {:eex, "lib/mix/brando.upgrade.ex", "lib/mix/brando.upgrade.ex"},

    # Etc. Various OS config files and log directory.
    {:keep, "log", "log"},
    {:eex, "etc/pgbkup.sh", "etc/pgbkup.sh"},
    {:eex, "etc/logrotate/prod.conf", "etc/logrotate/prod.conf"},
    {:eex, "etc/logrotate/staging.conf", "etc/logrotate/staging.conf"},
    {:eex, "etc/nginx/prod.conf", "etc/nginx/prod.conf"},
    {:eex, "etc/nginx/staging.conf", "etc/nginx/staging.conf"},
    {:eex, "etc/nginx/502.html", "etc/nginx/502.html"},
    {:eex, "etc/systemd/prod.service", "etc/systemd/prod.service"},
    {:eex, "etc/systemd/staging.service", "etc/systemd/staging.service"},

    # Main application file
    {:eex, "lib/application_name/application.ex", "lib/application_name/application.ex"},

    # Tuple implementation for Jason
    {:eex, "lib/application_name/tuple.ex", "lib/application_name/tuple.ex"},

    # Presence
    {:eex, "lib/application_name/presence.ex", "lib/application_name/presence.ex"},

    # Router template
    {:eex, "lib/application_name_web/router.ex", "lib/application_name_web/router.ex"},

    # Lockdown files
    {:eex, "lib/application_name_web/controllers/lockdown_controller.ex",
     "lib/application_name_web/controllers/lockdown_controller.ex"},
    {:eex, "lib/application_name_web/components/layouts/lockdown.html.heex",
     "lib/application_name_web/components/layouts/lockdown.html.heex"},
    {:eex, "lib/application_name_web/controllers/lockdown_html/index.html.heex",
     "lib/application_name_web/controllers/lockdown_html/index.html.heex"},
    {:eex, "lib/application_name_web/controllers/lockdown_html.ex",
     "lib/application_name_web/controllers/lockdown_html.ex"},

    # Page files
    {:eex, "lib/application_name_web/controllers/page_controller.ex",
     "lib/application_name_web/controllers/page_controller.ex"},
    {:eex, "lib/application_name_web/controllers/page_html.ex", "lib/application_name_web/controllers/page_html.ex"},
    {:eex, "lib/application_name_web/controllers/page_html/index.html.heex",
     "lib/application_name_web/controllers/page_html/index.html.heex"},
    {:eex, "lib/application_name_web/controllers/page_html/default.html.heex",
     "lib/application_name_web/controllers/page_html/default.html.heex"},

    # Fallback and errors
    {:eex, "lib/application_name_web/controllers/fallback_controller.ex",
     "lib/application_name_web/controllers/fallback_controller.ex"},
    {:eex, "lib/application_name_web/controllers/error_html.ex", "lib/application_name_web/controllers/error_html.ex"},
    {:eex, "lib/application_name_web/controllers/error_html/404.html.heex",
     "lib/application_name_web/controllers/error_html/404.html.heex"},
    {:eex, "lib/application_name_web/controllers/error_html/500.html.heex",
     "lib/application_name_web/controllers/error_html/500.html.heex"},

    # Partials
    {:eex, "lib/application_name_web/components/partials/navigation.html.heex",
     "lib/application_name_web/components/partials/navigation.html.heex"},
    {:eex, "lib/application_name_web/components/partials/footer.html.heex",
     "lib/application_name_web/components/partials/footer.html.heex"},
    {:eex, "lib/application_name_web/components/partials/logo.html.heex",
     "lib/application_name_web/components/partials/logo.html.heex"},

    # Default Villain parser & filters
    {:eex, "lib/application_name_web/villain/parser.ex", "lib/application_name_web/villain/parser.ex"},
    {:eex, "lib/application_name_web/villain/filters.ex", "lib/application_name_web/villain/filters.ex"},

    # E2E test setup
    {:eex, "lib/application_name/factory.ex", "lib/application_name/factory.ex"},
    {:eex, "test/e2e/test_helper.exs", "test/e2e/test_helper.exs"},

    # Default configuration files
    {:eex, "config/brando.exs", "config/brando.exs"},
    {:eex, "config/config.exs", "config/config.exs"},
    {:eex, "config/dev.exs", "config/dev.exs"},
    {:eex, "config/e2e.exs", "config/e2e.exs"},
    {:eex, "config/prod.exs", "config/prod.exs"},
    {:eex, "config/staging.exs", "config/staging.exs"},
    {:eex, "config/runtime.exs", "config/runtime.exs"},

    # Initial migration files
    {:eex, "migrations/20150123230712_create_users.exs", "priv/repo/migrations/20150123230712_create_users.exs"},
    {:eex, "migrations/20150215090305_create_imagecategories.exs",
     "priv/repo/migrations/20150215090305_create_imagecategories.exs"},
    {:eex, "migrations/20150215090306_create_imageseries.exs",
     "priv/repo/migrations/20150215090306_create_imageseries.exs"},
    {:eex, "migrations/20150215090307_create_images.exs", "priv/repo/migrations/20150215090307_create_images.exs"},
    {:eex, "migrations/20171103152200_create_pages.exs", "priv/repo/migrations/20171103152200_create_pages.exs"},
    {:eex, "migrations/20171103152205_create_pagefragments.exs",
     "priv/repo/migrations/20171103152205_create_pagefragments.exs"},
    {:eex, "migrations/20190426105600_create_templates.exs", "priv/repo/migrations/20190426105600_create_templates.exs"},
    {:eex, "migrations/20190630110527_brando_01_set_image_as_jsonb.exs",
     "priv/repo/migrations/20190630110527_brando_01_set_image_as_jsonb.exs"},
    {:eex, "migrations/20190630110528_brando_02_add_fragments_to_pages.exs",
     "priv/repo/migrations/20190630110528_brando_02_add_fragments_to_pages.exs"},
    {:eex, "migrations/20190630110530_brando_03_change_table_names.exs",
     "priv/repo/migrations/20190630110530_brando_03_change_table_names.exs"},
    {:eex, "migrations/20240527120605_brando_04_delete_meta_keywords.exs",
     "priv/repo/migrations/20240527120605_brando_04_delete_meta_keywords.exs"},
    {:eex, "migrations/20240527120606_brando_05_create_organization.exs",
     "priv/repo/migrations/20240527120606_brando_05_create_organization.exs"},
    {:eex, "migrations/20240527120608_brando_06_create_link.exs",
     "priv/repo/migrations/20240527120608_brando_06_create_link.exs"},
    {:eex, "migrations/20240527120609_brando_07_delete_link.exs",
     "priv/repo/migrations/20240527120609_brando_07_delete_link.exs"},
    {:eex, "migrations/20240527120611_brando_08_add_links_and_meta.exs",
     "priv/repo/migrations/20240527120611_brando_08_add_links_and_meta.exs"},
    {:eex, "migrations/20240527120612_brando_09_add_wrapper_to_fragments.exs",
     "priv/repo/migrations/20240527120612_brando_09_add_wrapper_to_fragments.exs"},
    {:eex, "migrations/20240527120614_brando_10_add_configs_to_organization.exs",
     "priv/repo/migrations/20240527120614_brando_10_add_configs_to_organization.exs"},
    {:eex, "migrations/20240527120615_brando_11_add_sequence_to_templates.exs",
     "priv/repo/migrations/20240527120615_brando_11_add_sequence_to_templates.exs"},
    {:eex, "migrations/20240527120617_brando_12_rename_organization_add_type.exs",
     "priv/repo/migrations/20240527120617_brando_12_rename_organization_add_type.exs"},
    {:eex, "migrations/20240527120618_brando_13_add_soft_deletion.exs",
     "priv/repo/migrations/20240527120618_brando_13_add_soft_deletion.exs"},
    {:eex, "migrations/20240527120620_brando_14_change_identity_texts.exs",
     "priv/repo/migrations/20240527120620_brando_14_change_identity_texts.exs"},
    {:eex, "migrations/20240527120621_brando_15_sequence_pages_and_fragments.exs",
     "priv/repo/migrations/20240527120621_brando_15_sequence_pages_and_fragments.exs"},
    {:eex, "migrations/20240527120623_brando_16_add_titles_to_fragments.exs",
     "priv/repo/migrations/20240527120623_brando_16_add_titles_to_fragments.exs"},
    {:eex, "migrations/20240527120624_brando_17_set_cfg_as_jsonb.exs",
     "priv/repo/migrations/20240527120624_brando_17_set_cfg_as_jsonb.exs"},
    {:eex, "migrations/20240527120626_brando_18_add_vars_to_templates.exs",
     "priv/repo/migrations/20240527120626_brando_18_add_vars_to_templates.exs"},
    {:eex, "migrations/20240527120627_brando_19_add_globals.exs",
     "priv/repo/migrations/20240527120627_brando_19_add_globals.exs"},
    {:eex, "migrations/20240527120629_brando_20_add_svg_to_templates.exs",
     "priv/repo/migrations/20240527120629_brando_20_add_svg_to_templates.exs"},
    {:eex, "migrations/20240527120630_brando_21_add_meta_image_to_pages.exs",
     "priv/repo/migrations/20240527120630_brando_21_add_meta_image_to_pages.exs"},
    {:eex, "migrations/20240527120632_brando_22_add_global_categories.exs",
     "priv/repo/migrations/20240527120632_brando_22_add_global_categories.exs"},
    {:eex, "migrations/20240527120633_brando_23_add_multi_flag_to_templates.exs",
     "priv/repo/migrations/20240527120633_brando_23_add_multi_flag_to_templates.exs"},
    {:eex, "migrations/20240527120635_brando_24_add_wrapper_to_templates.exs",
     "priv/repo/migrations/20240527120635_brando_24_add_wrapper_to_templates.exs"},
    {:eex, "migrations/20240527120636_brando_25_add_template_to_page.exs",
     "priv/repo/migrations/20240527120636_brando_25_add_template_to_page.exs"},
    {:eex, "migrations/20240527120638_brando_26_unique_constraint_page_key.exs",
     "priv/repo/migrations/20240527120638_brando_26_unique_constraint_page_key.exs"},
    {:eex, "migrations/20240527120639_brando_27_unique_constraint_page_key_language.exs",
     "priv/repo/migrations/20240527120639_brando_27_unique_constraint_page_key_language.exs"},
    {:eex, "migrations/20240527120641_brando_28_restructure_globals.exs",
     "priv/repo/migrations/20240527120641_brando_28_restructure_globals.exs"},
    {:eex, "migrations/20240527120642_brando_29_migrate_user_language.exs",
     "priv/repo/migrations/20240527120642_brando_29_migrate_user_language.exs"},
    {:eex, "migrations/20240527120644_brando_30_add_users_config.exs",
     "priv/repo/migrations/20240527120644_brando_30_add_users_config.exs"},
    {:eex, "migrations/20240527120645_brando_31_rename_user_full_name_to_name.exs",
     "priv/repo/migrations/20240527120645_brando_31_rename_user_full_name_to_name.exs"},
    {:eex, "migrations/20240527120647_brando_32_migrate_template_wrapper_casing.exs",
     "priv/repo/migrations/20240527120647_brando_32_migrate_template_wrapper_casing.exs"},
    {:eex, "migrations/20240527120648_brando_33_migrate_pages_datasource_wrappers.exs",
     "priv/repo/migrations/20240527120648_brando_33_migrate_pages_datasource_wrappers.exs"},
    {:eex, "migrations/20240527120650_brando_34_add_navigation.exs",
     "priv/repo/migrations/20240527120650_brando_34_add_navigation.exs"},
    {:eex, "migrations/20240527120651_brando_35_add_oban_tables.exs",
     "priv/repo/migrations/20240527120651_brando_35_add_oban_tables.exs"},
    {:eex, "migrations/20240527120653_brando_36_add_publish_at_to_pages.exs",
     "priv/repo/migrations/20240527120653_brando_36_add_publish_at_to_pages.exs"},
    {:eex, "migrations/20240527120654_brando_37_add_is_homepage_to_pages.exs",
     "priv/repo/migrations/20240527120654_brando_37_add_is_homepage_to_pages.exs"},
    {:eex, "migrations/20240527120656_brando_38_create_page_properties.exs",
     "priv/repo/migrations/20240527120656_brando_38_create_page_properties.exs"},
    {:eex, "migrations/20240527120657_brando_39_migrate_navigation_to_embeds.exs",
     "priv/repo/migrations/20240527120657_brando_39_migrate_navigation_to_embeds.exs"},
    {:eex, "migrations/20240527120659_brando_40_add_address2_to_identity.exs",
     "priv/repo/migrations/20240527120659_brando_40_add_address2_to_identity.exs"},
    {:eex, "migrations/20240527120700_brando_41_add_address3_to_identity.exs",
     "priv/repo/migrations/20240527120700_brando_41_add_address3_to_identity.exs"},
    {:eex, "migrations/20240527120702_brando_42_rename_identity_tables.exs",
     "priv/repo/migrations/20240527120702_brando_42_rename_identity_tables.exs"},
    {:eex, "migrations/20240527120703_brando_43_add_seo.exs",
     "priv/repo/migrations/20240527120703_brando_43_add_seo.exs"},
    {:eex, "migrations/20240527120705_brando_44_add_meta_title_to_pages.exs",
     "priv/repo/migrations/20240527120705_brando_44_add_meta_title_to_pages.exs"},
    {:eex, "migrations/20240527120706_brando_45_upgrade_oban_v9.exs",
     "priv/repo/migrations/20240527120706_brando_45_upgrade_oban_v9.exs"},
    {:eex, "migrations/20240527120708_brando_46_rename_villain_templates_to_modules.exs",
     "priv/repo/migrations/20240527120708_brando_46_rename_villain_templates_to_modules.exs"},
    {:eex, "migrations/20240527120710_brando_47_upgrade_oban_v10.exs",
     "priv/repo/migrations/20240527120710_brando_47_upgrade_oban_v10.exs"},
    {:eex, "migrations/20240527120711_brando_48_rename_pages_key_to_uri.exs",
     "priv/repo/migrations/20240527120711_brando_48_rename_pages_key_to_uri.exs"},
    {:eex, "migrations/20240527120713_brando_49_fix_page_indexes.exs",
     "priv/repo/migrations/20240527120713_brando_49_fix_page_indexes.exs"},
    {:eex, "migrations/20240527120714_brando_50_add_revisions.exs",
     "priv/repo/migrations/20240527120714_brando_50_add_revisions.exs"},
    {:eex, "migrations/20240527120716_brando_51_add_previews.exs",
     "priv/repo/migrations/20240527120716_brando_51_add_previews.exs"},
    {:eex, "migrations/20240527120717_brando_52_add_navigation_language_idx.exs",
     "priv/repo/migrations/20240527120717_brando_52_add_navigation_language_idx.exs"},
    {:eex, "migrations/20240527120719_brando_53_convert_fragments_data_to_jsonb_rerun_module_renaming.exs",
     "priv/repo/migrations/20240527120719_brando_53_convert_fragments_data_to_jsonb_rerun_module_renaming.exs"},
    {:eex, "migrations/20240527120720_brando_54_add_revision_description.exs",
     "priv/repo/migrations/20240527120720_brando_54_add_revision_description.exs"},
    {:eex, "migrations/20240527120722_brando_55_unify_table_naming.exs",
     "priv/repo/migrations/20240527120722_brando_55_unify_table_naming.exs"},
    {:eex, "migrations/20240527120723_brando_56_change_users.exs",
     "priv/repo/migrations/20240527120723_brando_56_change_users.exs"},
    {:eex, "migrations/20240527120725_brando_57_role_enums.exs",
     "priv/repo/migrations/20240527120725_brando_57_role_enums.exs"},
    {:eex, "migrations/20240527120726_brando_58_villain_module_ids.exs",
     "priv/repo/migrations/20240527120726_brando_58_villain_module_ids.exs"},
    {:eex, "migrations/20240527120728_brando_59_convert_module_vars_to_list.exs",
     "priv/repo/migrations/20240527120728_brando_59_convert_module_vars_to_list.exs"},
    {:eex, "migrations/20240527120729_brando_60_convert_villain_vars_to_list.exs",
     "priv/repo/migrations/20240527120729_brando_60_convert_villain_vars_to_list.exs"},
    {:eex, "migrations/20240527120731_brando_61_convert_villain_picture_and_gallery_urls_to_path.exs",
     "priv/repo/migrations/20240527120731_brando_61_convert_villain_picture_and_gallery_urls_to_path.exs"},
    {:eex, "migrations/20240527120732_brando_62_embed_poly_globals.exs",
     "priv/repo/migrations/20240527120732_brando_62_embed_poly_globals.exs"},
    {:eex, "migrations/20240527120734_brando_63_rename_module_vars_name_to_key.exs",
     "priv/repo/migrations/20240527120734_brando_63_rename_module_vars_name_to_key.exs"},
    {:eex, "migrations/20240527120735_brando_64_move_modules_to_content_namespace.exs",
     "priv/repo/migrations/20240527120735_brando_64_move_modules_to_content_namespace.exs"},
    {:eex, "migrations/20240527120737_brando_65_add_content_sections.exs",
     "priv/repo/migrations/20240527120737_brando_65_add_content_sections.exs"},
    {:eex, "migrations/20240527120738_brando_66_add_accent_color_to_sections.exs",
     "priv/repo/migrations/20240527120738_brando_66_add_accent_color_to_sections.exs"},
    {:eex, "migrations/20240527120740_brando_67_restructure_multi_module.exs",
     "priv/repo/migrations/20240527120740_brando_67_restructure_multi_module.exs"},
    {:eex, "migrations/20240527120741_brando_68_embed_page_properties_as_vars.exs",
     "priv/repo/migrations/20240527120741_brando_68_embed_page_properties_as_vars.exs"},
    {:eex, "migrations/20240527120743_brando_69_add_language_to_global_categories.exs",
     "priv/repo/migrations/20240527120743_brando_69_add_language_to_global_categories.exs"},
    {:eex, "migrations/20240527120744_brando_70_migrate_sections_to_palettes.exs",
     "priv/repo/migrations/20240527120744_brando_70_migrate_sections_to_palettes.exs"},
    {:eex, "migrations/20240527120746_brando_71_migrate_container_sections_to_palettes.exs",
     "priv/repo/migrations/20240527120746_brando_71_migrate_container_sections_to_palettes.exs"},
    {:eex, "migrations/20240527120747_brando_72_add_creator_and_soft_delete_to_palettes.exs",
     "priv/repo/migrations/20240527120747_brando_72_add_creator_and_soft_delete_to_palettes.exs"},
    {:eex, "migrations/20240527120749_brando_73_add_content_templates.exs",
     "priv/repo/migrations/20240527120749_brando_73_add_content_templates.exs"},
    {:eex, "migrations/20240527120750_brando_74_rename_global_categories_to_global_sets.exs",
     "priv/repo/migrations/20240527120750_brando_74_rename_global_categories_to_global_sets.exs"},
    {:eex, "migrations/20240527120752_brando_75_add_language_to_identity.exs",
     "priv/repo/migrations/20240527120752_brando_75_add_language_to_identity.exs"},
    {:eex, "migrations/20240527120753_brando_76_add_language_to_seo.exs",
     "priv/repo/migrations/20240527120753_brando_76_add_language_to_seo.exs"},
    {:eex, "migrations/20240527120755_brando_77_replace_slideshow_blocks_with_gallery.exs",
     "priv/repo/migrations/20240527120755_brando_77_replace_slideshow_blocks_with_gallery.exs"},
    {:eex, "migrations/20240527120756_brando_78_move_multi_refs_and_vars_under_data.exs",
     "priv/repo/migrations/20240527120756_brando_78_move_multi_refs_and_vars_under_data.exs"},
    {:eex, "migrations/20240527120758_brando_79_strip_media_prefix_from_picture_and_gallery_blocks.exs",
     "priv/repo/migrations/20240527120758_brando_79_strip_media_prefix_from_picture_and_gallery_blocks.exs"},
    {:eex, "migrations/20240527120759_brando_80_extract_embeds_one_image_fields.exs",
     "priv/repo/migrations/20240527120759_brando_80_extract_embeds_one_image_fields.exs"},
    {:eex, "migrations/20240527120801_brando_81_flatten_images_image_embed.exs",
     "priv/repo/migrations/20240527120801_brando_81_flatten_images_image_embed.exs"},
    {:eex, "migrations/20240527120802_brando_82_add_status_to_images.exs",
     "priv/repo/migrations/20240527120802_brando_82_add_status_to_images.exs"},
    {:eex, "migrations/20240527120804_brando_83_add_galleries.exs",
     "priv/repo/migrations/20240527120804_brando_83_add_galleries.exs"},
    {:eex, "migrations/20240527120805_brando_84_migrate_villain_refs_to_tags.exs",
     "priv/repo/migrations/20240527120805_brando_84_migrate_villain_refs_to_tags.exs"},
    {:eex, "migrations/20240527120807_brando_85_update_module_entry_template_binary_id.exs",
     "priv/repo/migrations/20240527120807_brando_85_update_module_entry_template_binary_id.exs"},
    {:eex, "migrations/20240527120808_brando_86_upgrade_oban_v11.exs",
     "priv/repo/migrations/20240527120808_brando_86_upgrade_oban_v11.exs"},
    {:eex, "migrations/20240527120810_brando_87_add_files.exs",
     "priv/repo/migrations/20240527120810_brando_87_add_files.exs"},
    {:eex, "migrations/20240527120811_brando_88_set_user_config_change_password_false.exs",
     "priv/repo/migrations/20240527120811_brando_88_set_user_config_change_password_false.exs"},
    {:eex, "migrations/20240527120813_brando_89_datasource_to_module.exs",
     "priv/repo/migrations/20240527120813_brando_89_datasource_to_module.exs"},
    {:eex, "migrations/20240527120814_brando_90_add_publish_at_to_fragments.exs",
     "priv/repo/migrations/20240527120814_brando_90_add_publish_at_to_fragments.exs"},
    {:eex, "migrations/20240527120816_brando_91_add_status_to_fragments.exs",
     "priv/repo/migrations/20240527120816_brando_91_add_status_to_fragments.exs"},
    {:eex, "migrations/20240527120817_brando_92_extract_files_embeds_one.exs",
     "priv/repo/migrations/20240527120817_brando_92_extract_files_embeds_one.exs"},
    {:eex, "migrations/20240527120819_brando_93_add_translatable_alternates_tables.exs",
     "priv/repo/migrations/20240527120819_brando_93_add_translatable_alternates_tables.exs"},
    {:eex, "migrations/20240527120820_brando_94_add_unique_index_for_seo_and_identity.exs",
     "priv/repo/migrations/20240527120820_brando_94_add_unique_index_for_seo_and_identity.exs"},
    {:eex, "migrations/20240527120822_brando_95_extract_videos_embeds_one.exs",
     "priv/repo/migrations/20240527120822_brando_95_extract_videos_embeds_one.exs"},
    {:eex, "migrations/20240527120823_brando_96_change_translatable_alternates_constraints.exs",
     "priv/repo/migrations/20240527120823_brando_96_change_translatable_alternates_constraints.exs"},
    {:eex, "migrations/20240527120825_brando_97_add_status_to_palettes.exs",
     "priv/repo/migrations/20240527120825_brando_97_add_status_to_palettes.exs"},
    {:eex, "migrations/20240527120826_brando_98_add_has_url_to_pages.exs",
     "priv/repo/migrations/20240527120826_brando_98_add_has_url_to_pages.exs"},
    {:eex, "migrations/20240527120828_brando_99_encode_module_svg_to_base64.exs",
     "priv/repo/migrations/20240527120828_brando_99_encode_module_svg_to_base64.exs"},
    {:eex, "migrations/20240527120829_brando_100_create_content_identifiers.exs",
     "priv/repo/migrations/20240527120829_brando_100_create_content_identifiers.exs"},
    {:eex, "migrations/20240527120831_brando_101_migrate_entries_to_identifiers.exs",
     "priv/repo/migrations/20240527120831_brando_101_migrate_entries_to_identifiers.exs"},
    {:eex, "migrations/20240527120832_brando_102_remove_legacy_entries_fields.exs",
     "priv/repo/migrations/20240527120832_brando_102_remove_legacy_entries_fields.exs"},
    {:eex, "migrations/20240527120834_brando_103_create_blocks_table.exs",
     "priv/repo/migrations/20240527120834_brando_103_create_blocks_table.exs"},
    {:eex, "migrations/20240527120835_brando_104_create_var_tables.exs",
     "priv/repo/migrations/20240527120835_brando_104_create_var_tables.exs"},
    {:eex, "migrations/20240617170008_brando_105_add_table_templates.exs",
     "priv/repo/migrations/20240617170008_brando_105_add_table_templates.exs"},
    {:eex, "migrations/20240617170010_brando_106_add_table_rows.exs",
     "priv/repo/migrations/20240617170010_brando_106_add_table_rows.exs"},
    {:eex, "migrations/20240617170011_brando_107_migrate_old_modules.exs",
     "priv/repo/migrations/20240617170011_brando_107_migrate_old_modules.exs"},
    {:eex, "migrations/20240617170013_brando_108_migrate_old_blocks_to_assocs.exs",
     "priv/repo/migrations/20240617170013_brando_108_migrate_old_blocks_to_assocs.exs"},
    {:eex, "migrations/20240617170015_brando_109_migrate_globals_to_vars.exs",
     "priv/repo/migrations/20240617170015_brando_109_migrate_globals_to_vars.exs"},
    {:eex, "migrations/20240617170016_brando_110_migrate_page_vars_to_vars.exs",
     "priv/repo/migrations/20240617170016_brando_110_migrate_page_vars_to_vars.exs"},
    {:eex, "migrations/20240617170018_brando_111_add_width_to_vars.exs",
     "priv/repo/migrations/20240617170018_brando_111_add_width_to_vars.exs"},
    {:eex, "migrations/20240617170019_brando_112_add_config_target_to_vars.exs",
     "priv/repo/migrations/20240617170019_brando_112_add_config_target_to_vars.exs"},
    {:eex, "migrations/20240617170021_brando_113_rename_linked_identifer.exs",
     "priv/repo/migrations/20240617170021_brando_113_rename_linked_identifer.exs"},
    {:eex, "migrations/20240617170022_brando_114_add_vars_link_cfg.exs",
     "priv/repo/migrations/20240617170022_brando_114_add_vars_link_cfg.exs"},
    {:eex, "migrations/20240617170024_brando_115_add_url_to_identifier.exs",
     "priv/repo/migrations/20240617170024_brando_115_add_url_to_identifier.exs"},

    # Repo seeds
    {:eex, "repo/seeds.exs", "priv/repo/seeds.exs"},

    # Layouts
    {:eex, "lib/application_name_web/components/layouts.ex", "lib/application_name_web/components/layouts.ex"},
    {:eex, "lib/application_name_web/components/layouts/app.html.heex",
     "lib/application_name_web/components/layouts/app.html.heex"},
    {:eex, "lib/application_name_web/components/layouts/bare.html.heex",
     "lib/application_name_web/components/layouts/bare.html.heex"},

    # Gettext templates
    {:keep, "priv/static/gettext/backend/nb", "priv/static/gettext/backend/nb/LC_MESSAGES"},
    {:keep, "priv/static/gettext/frontend", "priv/static/gettext/frontend"},
    {:eex, "lib/application_name_web/gettext.ex", "lib/application_name_web/gettext.ex"},

    # Endpoint
    {:eex, "lib/application_name_web/endpoint.ex", "lib/application_name_web/endpoint.ex"},

    # Repo
    {:eex, "lib/application_name/repo.ex", "lib/application_name/repo.ex"},

    # Authorization
    {:eex, "lib/application_name/authorization.ex", "lib/application_name/authorization.ex"},

    # Telemetry
    {:eex, "lib/application_name_web/telemetry.ex", "lib/application_name_web/telemetry.ex"},

    # Live Preview
    {:eex, "lib/application_name_web/live_preview.ex", "lib/application_name_web/live_preview.ex"},

    # Admin
    {:eex, "lib/application_name_admin/menus.ex", "lib/application_name_admin/menus.ex"},
    {:eex, "lib/application_name_admin/live/dashboard_live.ex", "lib/application_name_admin/live/dashboard_live.ex"}
  ]

  @static [
    # Deployment tools
    {:copy, "gitignore", ".gitignore"},
    {:copy, "dockerignore", ".dockerignore"},
    {:copy, "Dockerfile", "Dockerfile"},
    {:copy, "fabfile.py", "fabfile.py"},
    {:eex, "deployment.cfg", "deployment.cfg"},
    {:eex, "scripts/sync_media_from_local_to_remote.sh", "scripts/sync_media_from_local_to_remote.sh"},
    {:eex, "scripts/sync_media_from_remote_to_local.sh", "scripts/sync_media_from_remote_to_local.sh"},

    # Backend tooling
    {:copy, "assets/backend/europa.config.cjs", "assets/backend/europa.config.cjs"},
    {:copy, "assets/backend/package.json", "assets/backend/package.json"},
    {:copy, "assets/backend/postcss.config.cjs", "assets/backend/postcss.config.cjs"},
    {:copy, "assets/backend/README.md", "assets/backend/README.md"},
    {:copy, "assets/backend/svelte.config.cjs", "assets/backend/svelte.config.cjs"},
    {:copy, "assets/backend/vite.config.js", "assets/backend/vite.config.js"},

    # Backend resources
    {:copy, "assets/backend/public/favicon.ico", "assets/backend/public/favicon.ico"},
    {:copy, "assets/backend/public/fonts/Mono.woff2", "assets/backend/public/fonts/Mono.woff2"},
    {:copy, "assets/backend/public/fonts/Main-Light.woff2", "assets/backend/public/fonts/Main-Light.woff2"},
    {:copy, "assets/backend/public/fonts/Main-Medium.woff2", "assets/backend/public/fonts/Main-Medium.woff2"},
    {:copy, "assets/backend/public/fonts/Main-Regular.woff2", "assets/backend/public/fonts/Main-Regular.woff2"},
    {:copy, "assets/backend/public/images/admin/avatar.svg", "assets/backend/public/images/admin/avatar.svg"},

    # Backend src
    {:copy, "assets/backend/src/main.js", "assets/backend/src/main.js"},
    {:copy, "assets/backend/css/app.css", "assets/backend/css/app.css"},
    {:copy, "assets/backend/css/blocks.css", "assets/backend/css/blocks.css"},

    # Frontend assets
    {:keep, "assets/frontend/public/fonts", "assets/frontend/public/fonts"},
    {:keep, "assets/frontend/public/fonts", "assets/frontend/public/images"},
    {:copy, "assets/frontend/eslint.config.cjs", "assets/frontend/eslint.config.cjs"},
    {:copy, "assets/frontend/europa.config.cjs", "assets/frontend/europa.config.cjs"},
    {:copy, "assets/frontend/vite.config.js", "assets/frontend/vite.config.js"},
    {:copy, "assets/frontend/postcss.config.cjs", "assets/frontend/postcss.config.cjs"},
    {:copy, "assets/frontend/yarn.lock", "assets/frontend/yarn.lock"},
    {:eex, "assets/frontend/package.json", "assets/frontend/package.json"},

    # Frontend static
    {:copy, "assets/frontend/public/favicon.ico", "assets/frontend/public/favicon.ico"},
    {:copy, "assets/frontend/public/favicon.ico", "assets/frontend/public/ico/favicon.ico"},

    # Frontend src - CSS
    {:copy, "assets/frontend/css/app.css", "assets/frontend/css/app.css"},
    {:copy, "assets/frontend/css/critical.css", "assets/frontend/css/critical.css"},
    {:copy, "assets/frontend/css/includes/cookies.css", "assets/frontend/css/includes/cookies.css"},
    {:copy, "assets/frontend/css/includes/fonts.css", "assets/frontend/css/includes/fonts.css"},
    {:copy, "assets/frontend/css/includes/modules.css", "assets/frontend/css/includes/modules.css"},
    {:copy, "assets/frontend/css/includes/navigation.css", "assets/frontend/css/includes/navigation.css"},

    # Frontend JS

    {:keep, "assets/frontend/js/modules", "assets/frontend/js/modules"},
    {:copy, "assets/frontend/js/index.js", "assets/frontend/js/index.js"},
    {:copy, "assets/frontend/js/critical.js", "assets/frontend/js/critical.js"},
    {:copy, "assets/frontend/js/config/BREAKPOINTS.js", "assets/frontend/js/config/BREAKPOINTS.js"},
    {:copy, "assets/frontend/js/config/MOBILE_MENU.js", "assets/frontend/js/config/MOBILE_MENU.js"},
    {:copy, "assets/frontend/js/config/MOONWALK.js", "assets/frontend/js/config/MOONWALK.js"},
    {:copy, "assets/frontend/js/config/HEADER.js", "assets/frontend/js/config/HEADER.js"}
  ]

  @root Path.expand("../../../priv", __DIR__)

  for {format, source, _} <- @new ++ @static do
    if format not in [:keep, :copy] do
      @external_resource Path.join([@root, "templates/brando.install", source])
      def render(unquote(Path.join("templates/brando.install", source))),
        do: unquote(File.read!(Path.join([@root, "templates/brando.install", source])))
    end
  end

  @doc """
  Copies Brando files from template and static directories to OTP app.
  """
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [module: :string])

    app = Mix.Project.config()[:app]

    binding = [
      application_module: opts[:module] || Phoenix.Naming.camelize(Atom.to_string(app)),
      application_name: Atom.to_string(app),
      secret_key_base: random_string(64),
      signing_salt: random_string(8),
      lv_signing_salt: random_string(8)
    ]

    Mix.shell().info("\nDeleting old assets")
    File.rm_rf("assets")
    File.rm_rf("lib/#{binding[:application_name]}_web/components/layouts/root.html.heex")
    File.rm_rf("lib/#{binding[:application_name]}_web/controllers/page_html/home.html.heex")

    Mix.shell().info("\nMoving test/ to test/unit/")
    File.rename("test", "test/unit")

    copy_from("templates/brando.install", "./", binding, @new)
    copy_from("templates/brando.install", "./", binding, @static)

    Mix.shell().info("\nBrando finished copying.")
  end

  defp copy_from(src_dir, target_dir, binding, mapping) when is_list(mapping) do
    application_name = Keyword.fetch!(binding, :application_name)

    for {format, source, target_path} <- mapping do
      source = Path.join([src_dir, source])

      target =
        Path.join(target_dir, String.replace(target_path, "application_name", application_name))

      case format do
        :keep ->
          File.mkdir_p!(target)

        :text ->
          create_file(target, render(source), force: true)

        :copy ->
          File.mkdir_p!(Path.dirname(target))
          File.copy!(Path.join(@root, source), target)

        :eex ->
          contents = EEx.eval_string(render(source), binding, file: source)
          create_file(target, contents, force: true)
      end
    end
  end

  defp random_string(length) do
    length |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, length)
  end
end
