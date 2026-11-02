defmodule Brando.Cache.RefreshAfterCommitTest do
  # The site caches (globals, menus, palettes, identity, SEO) are rebuilt from
  # the database when a mutation saves one of their rows. Inside a caller's
  # transaction that read sees rows that are not committed yet, so the rebuild
  # waits for the commit, and a rollback leaves the cache as it was.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.{Boundary, Migration}
  alias Brando.Cache
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Page

  setup do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css])
    Cache.Globals.set()
    Cache.Navigation.set()
    Cache.Palettes.set()
    %{user: Factory.insert(:random_user)}
  end

  defp global_set(key, user) do
    :global_set
    |> Factory.params_for(key: key, creator_id: user.id)
    |> Brando.Utils.map_from_struct()
  end

  defp menu(key), do: %{status: :published, title: "Menu", key: key, language: "en", items: []}

  defp palette(key),
    do: %{name: key, key: key, namespace: "site", status: :published, colors: [%{name: "Red", key: "red", hex_value: "#ff0000"}]}

  defp palette_keys, do: Enum.map(Cache.Palettes.get(), & &1.key)

  describe "a mutation inside a transaction that rolls back" do
    test "leaves the globals cache without the set", c do
      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} = Brando.Sites.create_global_set(global_set("ghost", c.user), c.user)
                 Repo.rollback(:undone)
               end)

      refute Map.has_key?(Cache.Globals.get("en"), "ghost")
    end

    test "leaves the navigation cache without the menu", c do
      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} = Brando.Navigation.create_menu(menu("ghost"), c.user)
                 Repo.rollback(:undone)
               end)

      refute Cache.Navigation.get("ghost", "en")
    end

    test "leaves the palettes cache without the palette, also when the transaction raises", c do
      assert_raise RuntimeError, "later failure", fn ->
        Repo.transaction(fn ->
          {:ok, _} = Brando.Content.create_palette(palette("ghost"), c.user)
          raise "later failure"
        end)
      end

      refute "ghost" in palette_keys()
      refute Phoenix.HTML.safe_to_string(Cache.Palettes.get_css()) =~ "ghost"
    end

    test "nested in one that rolls back, leaves the cache as it was though the outer one carries on", c do
      assert {:error, :rollback} =
               Repo.transaction(fn ->
                 {:error, :undone} =
                   Repo.transaction(
                     fn ->
                       {:ok, _} = Brando.Content.create_palette(palette("ghost"), c.user)
                       Repo.rollback(:undone)
                     end,
                     mode: :savepoint
                   )

                 :saved
               end)

      refute "ghost" in palette_keys()
    end

    test "sends no module broadcast", c do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:modules")

      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} =
                   Brando.Content.create_module(
                     Factory.params_for(:module, name: %{"en" => "Ghost"}, namespace: %{"en" => "x"}, help_text: %{}),
                     c.user
                   )

                 Repo.rollback(:undone)
               end)

      refute_received {_, [:module, :created]}
    end
  end

  describe "a mutation inside a transaction that commits" do
    test "refreshes each cache once the transaction has committed, not before", c do
      test = self()

      assert {:ok, _} =
               Repo.transaction(fn ->
                 {:ok, _} = Brando.Sites.create_global_set(global_set("kept", c.user), c.user)
                 {:ok, _} = Brando.Navigation.create_menu(menu("kept"), c.user)
                 {:ok, _} = Brando.Content.create_palette(palette("kept"), c.user)

                 send(
                   test,
                   {:inside,
                    Map.has_key?(Cache.Globals.get("en"), "kept"), Cache.Navigation.get("kept", "en"),
                    "kept" in palette_keys()}
                 )
               end)

      assert_received {:inside, false, nil, false}
      assert Map.has_key?(Cache.Globals.get("en"), "kept")
      assert %{key: "kept"} = Cache.Navigation.get("kept", "en")
      assert "kept" in palette_keys()
    end

    test "outside a transaction, refreshes at once", c do
      {:ok, _} = Brando.Content.create_palette(palette("now"), c.user)
      assert "now" in palette_keys()

      {:ok, _} = Brando.Sites.create_global_set(global_set("now", c.user), c.user)
      assert Map.has_key?(Cache.Globals.get("en"), "now")
    end
  end

  describe "with group authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()
      %{owner: owner}
    end

    # A mutation runs in the boundary's own transaction: the refresh waits
    # for it, and for the caller's around it.
    test "a save refreshes the caches after its commit, and one rolled back leaves them", c do
      {:ok, _} = Brando.Sites.create_global_set(global_set("kept", c.owner), c.owner)
      assert Map.has_key?(Cache.Globals.get("en"), "kept")

      {:ok, _} = Brando.Content.create_palette(palette("kept"), c.owner)
      assert "kept" in palette_keys()

      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} = Brando.Navigation.create_menu(menu("ghost"), c.owner)
                 Repo.rollback(:undone)
               end)

      refute Cache.Navigation.get("ghost", "en")
    end
  end

  # The proposal apply in #3435: the palette is saved, then a page whose URI
  # another page has taken since approval fails the unique check, and the
  # whole apply rolls back.
  test "a proposal apply that fails after creating a palette leaves it out of the cache" do
    c = Brando.ProposalFixtures.context()

    ops = [
      %CreateEntry{schema: Brando.Content.Palette, ref: :ghost, fields: Map.delete(palette("ghost"), :status)},
      %CreateEntry{
        schema: Page,
        ref: :later,
        fields: %{title: "Later", uri: "later-taken", language: "en", template: "default.html"}
      }
    ]

    assert {:ok, proposal} = Proposals.propose(ops, c.user)
    assert proposal.problems == []
    assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)

    Factory.insert(:page, uri: "later-taken", language: "en", creator: c.user)

    assert {:error, _} = Proposals.apply(proposal.id, proposal.version, c.user)
    refute Repo.get_by(Brando.Content.Palette, key: "ghost")
    refute "ghost" in palette_keys()
    refute Phoenix.HTML.safe_to_string(Cache.Palettes.get_css()) =~ "ghost"
  end
end
