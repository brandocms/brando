defmodule BrandoAdmin.Components.Form.Input.MultiSelectPickerTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Phoenix.LiveViewTest

  alias BrandoAdmin.Components.Form.Input.MultiSelect

  defmodule Host do
    use Phoenix.LiveView, layout: false

    def mount(_, _, socket) do
      form = Phoenix.Component.to_form(Ecto.Changeset.change(%Brando.Content.Var{link_identifier_schemas: []}), as: "var")
      {:ok, Phoenix.Component.assign(socket, :form, form)}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={MultiSelect}
        id="schemas"
        field={@form[:link_identifier_schemas]}
        label="Schemas"
        opts={[
          options: [
            %{label: "Om oss", value: "about", status: :published, language: :no},
            %{label: "Contact", value: "contact"},
            %{label: "Projects", value: "projects"}
          ]
        ]}
      />
      """
    end
  end

  defp option(label), do: "#var_link_identifier_schemas-options [role=checkbox][data-label='#{label}']"
  defp chosen(label), do: ".multiselect-chosen-row[data-label='#{label}']"

  setup %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, Host)
    view |> element(".multiselect > .button-edit") |> render_click()
    %{view: view}
  end

  test "options are checkbox rows with their status and language", %{view: view} do
    assert has_element?(view, option("Om oss") <> "[aria-checked=false]")
    assert has_element?(view, option("Om oss") <> " .identifier-check")
    assert has_element?(view, option("Om oss") <> " .identifier-status[data-status=published]")
    assert has_element?(view, option("Om oss") <> " .identifier-details", "NO")
    # Only an option with a status has the dot, and only one with a language the line under it.
    refute has_element?(view, option("Contact") <> " .identifier-status")
    refute has_element?(view, option("Contact") <> " .identifier-details")
    # The plain label, without the dash used under the field.
    assert view |> element(option("Contact")) |> render() =~ ~r/>Contact</
    assert has_element?(view, ".multiselect-chosen .multiselect-empty")
  end

  test "clicking a row toggles it, in the order chosen", %{view: view} do
    view |> element(option("Projects")) |> render_click()
    view |> element(option("Om oss")) |> render_click()

    assert has_element?(view, option("Projects") <> "[aria-checked=true].selected")
    assert has_element?(view, option("Om oss") <> "[aria-checked=true]")
    assert has_element?(view, option("Contact") <> "[aria-checked=false]")

    labels =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find(".multiselect-chosen-row")
      |> Enum.map(&(&1 |> Floki.attribute("data-label") |> hd()))

    assert labels == ["Projects", "Om oss"]
    assert has_element?(view, ".multiselect-chosen .count-badge", "2 selected")

    view |> element(option("Projects")) |> render_click()
    assert has_element?(view, option("Projects") <> "[aria-checked=false]")
    refute has_element?(view, chosen("Projects"))
  end

  test "a selected row's remove button deselects it", %{view: view} do
    view |> element(option("Contact")) |> render_click()
    assert has_element?(view, chosen("Contact"))

    view |> element(chosen("Contact") <> " button[aria-label=Remove]") |> render_click()

    refute has_element?(view, chosen("Contact"))
    assert has_element?(view, option("Contact") <> "[aria-checked=false]")
    assert has_element?(view, ".multiselect-chosen .multiselect-empty")
  end

  test "the filter reads the rows' labels", %{view: view} do
    assert has_element?(
             view,
             "[phx-hook='Brando.SelectFilter'][data-target='.multiselect-option'][data-filter-target='#var_link_identifier_schemas-options']"
           )

    assert has_element?(view, "#var_link_identifier_schemas-options > .multiselect-option[data-label='Projects']")
    assert has_element?(view, "#var_link_identifier_schemas-options > .no-results")
  end
end
