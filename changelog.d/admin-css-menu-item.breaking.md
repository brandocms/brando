- **Menu rows need `class="menu-item"`; the menus no longer style a bare
  button.** An application that renders its own rows in an admin menu
  (`MediaField.action_menu`, the `:actions` slot of a `:line`
  `MediaField.field`, a dropdown of its own on `%admin_dropdown_panel`)
  adds `menu-item` to each row, `menu-item--danger` where it wrote
  `destructive`, and `menu-separator` on a separator. TipTap's toolbar
  buttons are `.tiptap-tool` (was `.menu-item`), for application CSS that
  restyles them.
