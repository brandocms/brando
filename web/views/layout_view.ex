defmodule Brando.Admin.LayoutView do
  @moduledoc """
  Main layout view for Brando admin.
  """
  use Brando.Web, :view
  use Linguist.Vocabulary

  @doc """
  Returns menus for admin.
  Modules are registered with `:modules` in `config.exs`

  ## Example:

      config :brando, Brando.Menu,
        modules: [Brando.Admin, Brando.Users]

  """
  def get_menus(language) do
    modules = Brando.config(Brando.Menu)[:modules]
    colors = Brando.config(Brando.Menu)[:colors]
    for {mod, color} <- Enum.zip(modules, colors) do
      {color, mod.get_menu(language)}
    end
  end

  locale "en", [
    global: [
      back_to_index: "Back to index",
      create: "Create",
      configure: "Configure",
      edit: "Edit",
      delete: "Delete"
    ],
    message: [
      confirm_delete: "You are about to delete this object. " <>
                      "Please check carefully, and note that " <>
                      "any dependent objects will also be removed.",
      no_restore: "This object cannot be restored!"
    ],
    status: [
      published: "Published",
      pending: "Pending",
      draft: "Draft",
      deleted: "Deleted"
    ]
  ]

  locale "no", [
    global: [
      back_to_index: "Tilbake til oversikten",
      create: "Opprett",
      configure: "Konfigurér",
      edit: "Endre",
      delete: "Slett"
    ],
    message: [
      confirm_delete: "Du er i ferd med å slette dette objektet. " <>
                      "Vennligst se over og merk at du også sletter " <>
                      "avhengige objekter.",
      no_restore: "Objektet kan ikke gjenopprettes!"
    ],
    status: [
      published: "Publisert",
      pending: "Venter",
      draft: "Utkast",
      deleted: "Slettet"
    ]
  ]
end
