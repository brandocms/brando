- **Applications can add their own screens under Configuration.** In the
  admin menu module, `config_item` puts a screen at the end of one of
  Configuration's groups, after Brando's own:

  ```elixir
  menus do
    menu_item MyApp.Articles.Article

    config_item t("Shop"), "/admin/config/shop", icon: "store", group: :operations
  end
  ```

  `group:` is `:site`, `:publishing`, `:building_blocks` or `:operations`
  (the default); the groups themselves are fixed. Without group
  authorization the item shows to `roles:` (`[:admin, :superuser]` by
  default); with it, to those who may open the route, by the LiveView's
  `__authorization__/0`. The item appears in the command palette too. Menu
  modules that do not use `config_item` are unchanged.
