defmodule Brando.Navigation.ItemDeriveKeyTest do
  # A menu item's key follows its link until set, and stays once it is.
  use Brando.ConnCase, async: true

  alias Brando.Navigation.Item

  defp changeset(key, link_params) do
    user = Brando.Factory.insert(:random_user)

    Item.changeset(
      %Item{},
      %{
        key: key,
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
        entry_id: 1,
        status: :published
      })

    cs = changeset(nil, %{link_type: :identifier, identifier_id: identifier.id})
    assert Ecto.Changeset.get_field(cs, :key) == "innsikt"
  end

  test "nothing to go on still gives a valid key" do
    cs = changeset(nil, %{})
    assert Ecto.Changeset.get_field(cs, :key) == "item"
    refute Keyword.has_key?(cs.errors, :key)
  end
end
