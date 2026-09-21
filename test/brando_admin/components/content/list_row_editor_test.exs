defmodule BrandoAdmin.Components.Content.ListRowEditorTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Content.List.Row
  alias Brando.Pages.Page
  alias Brando.Users.User

  defp user(name), do: %User{id: System.unique_integer([:positive]), name: name, avatar: nil}

  defp render(entry, soft_delete? \\ false) do
    rendered_to_string(Row.creator(%{entry: entry, soft_delete?: soft_delete?, __changed__: %{}}))
  end

  test "shows the creator with inserted_at until someone edits the entry" do
    entry = %Page{
      id: 1,
      creator: user("Evan"),
      updated_by: nil,
      inserted_at: ~N[2024-12-03 10:00:00],
      updated_at: ~N[2026-09-22 14:58:00],
      edited_at: nil
    }

    html = render(entry)

    assert html =~ "Evan"
    assert html =~ ~s(aria-label="Created by")
    assert html =~ "03/12/24"
    refute html =~ "22/09/26"
  end

  test "shows the last editor with edited_at once the entry has been edited" do
    entry = %Page{
      id: 2,
      creator: user("Evan"),
      updated_by: user("Nina"),
      inserted_at: ~N[2024-12-03 10:00:00],
      updated_at: ~N[2026-09-22 14:58:00],
      edited_at: ~U[2026-09-20 09:30:00Z]
    }

    html = render(entry)

    assert html =~ "Nina"
    refute html =~ "Evan"
    assert html =~ ~s(aria-label="Edited by")
    assert html =~ "20/09/26"
    refute html =~ "22/09/26"
  end

  test "renders a dash when nobody is known" do
    html = render(%Page{id: 3, creator: nil, updated_by: nil})
    assert html =~ "—"
  end
end
