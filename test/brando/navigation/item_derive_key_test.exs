defmodule Brando.Navigation.ItemDeriveKeyTest do
  # A menu item's key follows its link until set, and stays once it is.
  use Brando.ConnCase, async: true

  alias Brando.Navigation.Item

  defp changeset(key, link_params, derived_key \\ nil) do
    user = Brando.Factory.insert(:random_user)

    Item.changeset(
      %Item{},
      %{
        key: key,
        derived_key: derived_key,
        status: :published,
        link: Map.merge(%{type: :link, key: "link", label: "Link", link_type: :url}, link_params)
      },
      user
    )
  end

  test "an unset key is taken from the link's text" do
    for key <- [nil, "", "key"] do
      assert Ecto.Changeset.get_field(changeset(key, %{link_text: "Om oss", value: "/om"}), :key) == "om_oss"
    end
  end

  test "a key that is set stays, whatever the link says" do
    assert Ecto.Changeset.get_field(changeset("contact", %{link_text: "Kontakt oss"}), :key) == "contact"
  end

  test "an entry link without text takes the entry's title, without its [type/language] prefix" do
    identifier =
      Brando.Repo.insert!(%Brando.Content.Identifier{
        title: "[Side/NO] Innsikt",
        schema: Brando.Pages.Page,
        # Not 1: (entry_id, schema) is unique, and an async test's first page
        # is entry 1 too, so the insert would wait out that test's transaction.
        entry_id: 900_000_000 + System.unique_integer([:positive]),
        status: :published
      })

    cs = changeset(nil, %{link_type: :identifier, identifier_id: identifier.id})
    assert Ecto.Changeset.get_field(cs, :key) == "innsikt"
  end

  # The menu form posts the derived key back as the key, so on its own it would
  # read as typed and stop following the link after the first change.
  test "a derived key posted back by the form keeps following the link" do
    first = changeset(nil, %{link_text: "Text"})
    assert Ecto.Changeset.get_field(first, :key) == "text"

    posted_back = %{
      derived_key: Ecto.Changeset.get_field(first, :derived_key),
      link: %{link_text: "Kontakt"}
    }

    assert Ecto.Changeset.get_field(changeset("text", posted_back.link, posted_back.derived_key), :key) == "kontakt"

    # Edited by the editor: it no longer matches what was derived, and stays.
    assert Ecto.Changeset.get_field(changeset("contact", %{link_text: "Kontakt"}, "text"), :key) == "contact"
  end

  test "nothing to go on still gives a valid key" do
    cs = changeset(nil, %{})
    assert Ecto.Changeset.get_field(cs, :key) == "item"
    refute Keyword.has_key?(cs.errors, :key)
  end
end
