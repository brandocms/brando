defmodule BrandoAdmin.Components.Content.ListRowAlternatesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Phoenix.LiveViewTest

  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Content.List.Row

  defmodule Host do
    use Phoenix.LiveView, layout: false

    def mount(_, _, socket) do
      alternates = [
        %Page{id: 2, title: "Engelsk", uri: "engelsk", language: :en, status: :published},
        %Page{id: 3, title: "English", uri: "english", language: :en, status: :published}
      ]

      entry = %Page{id: 1, title: "Norsk", uri: "norsk", language: :no, alternate_entries: alternates}
      {:ok, Phoenix.Component.assign(socket, :entry, entry)}
    end

    def render(assigns) do
      ~H"""
      <Row.alternates entry={@entry} target={nil} />
      """
    end
  end

  # Identifiers for alternates are built in memory, so their `id` is nil.
  # Two alternates used to collide on `:key={identifier.id}` and LiveView raised
  # "found duplicate key nil in comprehension".
  test "renders an entry with two alternates", %{conn: conn} do
    {:ok, _view, html} = live_isolated(conn, Host)

    assert html =~ "Engelsk"
    assert html =~ "English"
  end
end
