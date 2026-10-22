- Admin menus style only rows with `class="menu-item"`
  ([#3212](https://github.com/brandocms/brando/pull/3212)).
  In an application's own menu rows (`MediaField.action_menu`, the `:actions` slot of a `:line`
  `MediaField.field`, a dropdown on `%admin_dropdown_panel`), add `menu-item` to each row,
  `menu-item--danger` where it wrote `destructive`, and `menu-separator` on a separator.
  Application CSS that restyles TipTap's toolbar buttons targets `.tiptap-tool` (was `.menu-item`).
