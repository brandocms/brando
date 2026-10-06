defmodule Mix.Tasks.Brando.Translations.CheckEditsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Revisions
  alias Mix.Tasks.Brando.Translations.CheckEdits

  test "collects each changed text between consecutive revisions" do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user, title: "Velkomen", language: :no)

    {:ok, _} = Revisions.create_revision(page, user)
    {:ok, _} = Revisions.create_revision(%{page | title: "Velkommen"}, user)
    {:ok, _} = Revisions.create_revision(%{page | title: "Velkommen"}, user)

    edits = [language: "no"] |> CheckEdits.edits() |> Enum.filter(&(&1.entry_id == page.id))

    assert [%{path: "title", before: "Velkomen", after: "Velkommen", from: 0, to: 1, language: "no"}] = edits
    assert [] = [language: "en"] |> CheckEdits.edits() |> Enum.filter(&(&1.entry_id == page.id))
  end
end
