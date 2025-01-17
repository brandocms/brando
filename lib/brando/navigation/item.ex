defmodule Brando.Navigation.Item do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Navigation",
    schema: "Item",
    singular: "item",
    plural: "items",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped

  identifier false
  persist_identifier false

  attributes do
    attribute :key, :string, required: true
  end

  relations do
    relation :menu, :belongs_to, module: Brando.Navigation.Menu
    relation :parent, :belongs_to, module: __MODULE__

    relation :children, :has_many,
      module: __MODULE__,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      foreign_key: :parent_id

    relation :link, :has_one,
      module: Brando.Content.Var,
      required: true,
      foreign_key: :menu_item_id,
      on_replace: :delete,
      cast: true
  end

  translations do
    context :naming do
      translate :singular, t("menu item")
      translate :plural, t("menu items")
    end
  end

  def redirect(socket, _entry, _) do
    Brando.routes().admin_live_path(socket, BrandoAdmin.Navigation.MenuListLive)
  end
end
