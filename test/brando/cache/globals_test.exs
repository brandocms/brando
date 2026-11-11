defmodule Brando.Cache.GlobalsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Sites

  setup do
    preserve_cache(:globals)
    ExMachina.Sequence.reset()
    user = Factory.insert(:user)
    {:ok, %{user: user}}
  end

  test "set and get", %{user: user} do
    assert Brando.Cache.Globals.set()
    assert Brando.Cache.Globals.get("en") == %{}

    category_params =
      :global_set
      |> Factory.params_for(creator_id: user.id)
      |> Brando.Utils.map_from_struct()

    {:ok, _category} = Sites.create_global_set(category_params, user)

    assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}

    global_map = Brando.Cache.Globals.get("en")
    assert Map.keys(global_map) === ["system"]

    assert get_in(global_map, [Access.key("system"), Access.key("key-0"), Access.key(:key)]) ===
             "key-0"

    assert get_in(global_map, [Access.key("system"), Access.key("key-1"), Access.key(:key)]) ===
             "key-1"
  end

  describe "link globals" do
    defp link_global_set(identifier, user) do
      {:ok, _} =
        Sites.create_global_set(
          %{
            label: "Footer",
            key: "footer",
            language: "en",
            vars: [
              %{type: :link, key: "contact", label: "Contact", link_type: :identifier, identifier_id: identifier.id}
            ]
          },
          user
        )

      assert Brando.Cache.Globals.update({:ok, :dummy}) === {:ok, :dummy}
    end

    defp cached_link, do: Brando.Cache.Globals.get("en")["footer"]["contact"]

    test "hold the identifier of a link to an entry", %{user: user} do
      page = Factory.insert(:page, uri: "contact", title: "Contact us", language: "en", creator: user)
      {:ok, identifier} = Brando.Content.create_identifier(Brando.Pages.Page, page)
      link_global_set(identifier, user)

      assert Brando.Villain.Filters.link_url(cached_link()) =~ "/contact"
      assert Brando.Villain.Filters.link_text(cached_link()) == "Contact us"
    end

    test "follow the entry when its URL changes", %{user: user} do
      page = Factory.insert(:page, uri: "contact", title: "Contact us", language: "en", creator: user)
      {:ok, identifier} = Brando.Content.create_identifier(Brando.Pages.Page, page)
      link_global_set(identifier, user)

      {:ok, _} = Brando.Pages.update_page(page.id, %{uri: "contact-moved"}, user)

      assert Brando.Villain.Filters.link_url(cached_link()) =~ "/contact-moved"
    end
  end
end
