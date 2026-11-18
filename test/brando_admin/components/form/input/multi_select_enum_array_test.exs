defmodule BrandoAdmin.Components.Form.Input.MultiSelectEnumArrayTest do
  # An `{:array, Ecto.Enum}` field reads back as atoms, while the options name
  # their values as strings once assigned. A gallery variable's "Allowed media"
  # (`gallery_allowed_types`, `[:image, :video]` by default) is one: each
  # selected atom must match its option, or the field says every choice is
  # unavailable and "Remove invalid" clears them.
  use ExUnit.Case, async: true
  use Brando.ConnCase
  import Phoenix.LiveViewTest

  alias Brando.Content.Var

  defmodule Host do
    use Phoenix.LiveView, layout: false

    alias Brando.Content.Var
    alias BrandoAdmin.Components.Form.Input.MultiSelect
    alias Ecto.Changeset
    alias Phoenix.Component

    def mount(_, %{"types" => types, "options" => options}, socket) do
      changeset = Changeset.change(%Var{type: :gallery, key: "gallery", gallery_allowed_types: types})

      {:ok,
       socket
       |> Component.assign(:options, options)
       |> Component.assign(:form, Component.to_form(changeset, as: "var"))}
    end

    def handle_info(_message, socket), do: {:noreply, socket}

    def render(assigns) do
      ~H"""
      <.live_component
        module={MultiSelect}
        id="allowed-types"
        field={@form[:gallery_allowed_types]}
        label="Allowed media"
        opts={[options: @options]}
      />
      """
    end
  end

  @both [%{label: "Images", value: :image}, %{label: "Videos", value: :video}]

  defp mount_host(conn, types, options) do
    {:ok, view, _html} =
      live_isolated(conn, Host, session: %{"types" => types, "options" => options})

    view
  end

  test "the default selection matches its options", %{conn: conn} do
    view = mount_host(conn, %Var{}.gallery_allowed_types, @both)

    refute has_element?(view, ".invalid-options-warning")
    refute render(view) =~ "Missing option"
    assert has_element?(view, ".selected-label", "Images")
    assert has_element?(view, ".selected-label", "Videos")
  end

  test "a selected value the options no longer offer is still unavailable", %{conn: conn} do
    view = mount_host(conn, [:image, :video], [%{label: "Images", value: :image}])

    assert has_element?(view, ".invalid-options-warning", "video")
    refute has_element?(view, ".invalid-options-warning", "image")

    view |> element(".clear-invalid-button") |> render_click()

    # An array field hands its new value to the form's validate event.
    assert_push_event(view, "b:validate", %{target: "var[gallery_allowed_types][]", values: [:image]})
    refute has_element?(view, ".invalid-options-warning")
  end
end
