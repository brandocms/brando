defmodule BrandoAdmin.Components.Content.ListRowActionsTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Content.List.Row

  setup do
    previous = Gettext.get_locale(Brando.Gettext)
    Gettext.put_locale(Brando.Gettext, "no")
    on_exit(fn -> Gettext.put_locale(Brando.Gettext, previous) end)
  end

  # A custom action's confirmation is translated in the schema's domain, as
  # its label is
  test "translates a custom action's label and confirmation" do
    listing = %{
      name: :default,
      default_actions: false,
      actions: [%{event: "about", label: "About Page", confirm: "About the organization"}]
    }

    html =
      rendered_to_string(
        Row.entry_menu(%{
          schema: Page,
          content_language: "no",
          entry: %Page{id: 1, language: :no},
          listing: listing,
          current_user: nil,
          __changed__: %{}
        })
      )

    assert html =~ "Om-side"
    assert html =~ ~s(phx-confirm-click-message="Om organisasjonen")
  end
end
