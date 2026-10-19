# An application whose menu puts its own screens under Configuration
# (`BrandoAdmin.Menu.config_item/3`). Tests switch to it with
# `put_test_env(:admin_module, BrandoIntegrationConfigAdmin)`.
defmodule BrandoIntegrationConfigAdmin.Gettext do
  @moduledoc false
  use Gettext.Backend, otp_app: :brando, priv: "test/fixtures/menu_gettext"
end

defmodule BrandoIntegrationConfigAdmin.Menus do
  @moduledoc false
  use BrandoAdmin.Menu
  use Gettext, backend: BrandoIntegrationConfigAdmin.Gettext

  menus do
    menu_item Brando.Pages.Page

    config_item t("Shop"), "/admin/config/shop", icon: "store"
    config_item "Storefront", "/admin/config/storefront", group: :site
    config_item "Shop sync", "/admin/config/shop-sync", icon: "refresh-cw", group: :operations
    config_item "Undeclared", "/admin/config/undeclared"

    config_item "Product blocks", "/admin/config/product-blocks",
      icon: "blocks",
      group: :building_blocks,
      roles: [:editor, :admin, :superuser]
  end
end
