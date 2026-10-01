defmodule BrandoAdmin.Components.Assets.MediaFieldLinkTest do
  # A video can be added by URL as well as picked or uploaded, which matters
  # most when the field's upload strategy has no provider set up.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Assets.MediaField

  defp render(type, link) do
    %{
      id: "f",
      type: type,
      asset: nil,
      kind: "entry_field",
      presentation: :field,
      browse: %Phoenix.LiveView.JS{},
      link: link,
      __changed__: nil
    }
    |> MediaField.field()
    |> rendered_to_string()
  end

  test "an empty video field offers Add from URL when given a link action" do
    assert render(:video, %Phoenix.LiveView.JS{}) =~ "Add from URL"
    refute render(:video, nil) =~ "Add from URL"
  end

  test "a field whose config doesn't allow external URLs hides it" do
    refute render(:image, %Phoenix.LiveView.JS{}) =~ "Add from URL"
  end
end
