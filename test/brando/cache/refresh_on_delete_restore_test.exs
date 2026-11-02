defmodule Brando.Cache.RefreshOnDeleteRestoreTest do
  # The site caches (globals, menus, palettes, identity, SEO) are rebuilt from
  # the database by every write that changes their rows: a delete, a restore
  # from the trash, a duplicate, a create, and a status set from a listing,
  # not only a save in the form.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.{Boundary, Migration}
  alias Brando.Cache
  alias Brando.{Factory, Repo}

  setup do
    preserve_cache([:globals, :navigation, :palettes, :palettes_css, :identity, :seo])
    Cache.Globals.set()
    Cache.Navigation.set()
    Cache.Palettes.set()
    Cache.Identity.set()
    Cache.SEO.set()
    %{user: Factory.insert(:random_user, role: :superuser)}
  end

  defp global_set(key, user) do
    :global_set
    |> Factory.params_for(key: key, creator_id: user.id)
    |> Brando.Utils.map_from_struct()
  end

  defp menu(key), do: %{status: :published, title: "Menu", key: key, language: "en", items: []}

  defp palette(key),
    do: %{
      name: key,
      key: key,
      namespace: "site",
      status: :published,
      colors: [%{name: "Red", key: "red", hex_value: "#ff0000"}]
    }

  defp palette_keys, do: Enum.map(Cache.Palettes.get(), & &1.key)
  defp palettes_css, do: Phoenix.HTML.safe_to_string(Cache.Palettes.get_css())

  describe "palettes" do
    test "a deleted palette leaves the cache, and comes back when restored", c do
      {:ok, palette} = Brando.Content.create_palette(palette("trashed"), c.user)
      assert "trashed" in palette_keys()

      {:ok, _} = Brando.Content.delete_palette(palette.id, c.user)
      refute "trashed" in palette_keys()
      refute palettes_css() =~ "trashed"

      trashed = Repo.get!(Brando.Content.Palette, palette.id)
      {:ok, _} = Boundary.restore(c.user, trashed)
      assert "trashed" in palette_keys()
      assert palettes_css() =~ "trashed"
    end

    test "a delete rolled back with the transaction around it leaves the palette in the cache", c do
      {:ok, palette} = Brando.Content.create_palette(palette("kept"), c.user)

      assert {:error, :undone} =
               Repo.transaction(fn ->
                 {:ok, _} = Brando.Content.delete_palette(palette.id, c.user)
                 Repo.rollback(:undone)
               end)

      assert "kept" in palette_keys()
    end

    test "a copy is in the cache", c do
      {:ok, palette} = Brando.Content.create_palette(palette("original"), c.user)
      {:ok, copy} = Brando.Content.duplicate_palette(palette.id, c.user)

      assert copy.key in palette_keys()
      assert palettes_css() =~ copy.key
    end

    test "a status set from the listing is in the cache", c do
      {:ok, palette} = Brando.Content.create_palette(palette("toggled"), c.user)
      {:ok, _} = Brando.Trait.Status.update_status(Brando.Content.Palette, palette.id, "draft", c.user)

      assert %{status: :draft} = Enum.find(Cache.Palettes.get(), &(&1.key == "toggled"))
    end
  end

  describe "global sets" do
    test "a deleted set leaves the cache", c do
      {:ok, set} = Brando.Sites.create_global_set(global_set("gone", c.user), c.user)
      assert Map.has_key?(Cache.Globals.get("en"), "gone")

      {:ok, _} = Brando.Sites.delete_global_set(set.id, c.user)
      refute Map.has_key?(Cache.Globals.get("en"), "gone")
    end
  end

  describe "menus" do
    test "a copy is in the cache, also one made for another language", c do
      {:ok, menu} = Brando.Navigation.create_menu(menu("original"), c.user)

      {:ok, copy} = Brando.Navigation.duplicate_menu(menu.id, c.user)
      assert %{id: id} = Cache.Navigation.get(copy.key, "en")
      assert id == copy.id

      {:ok, translated} =
        Brando.Navigation.duplicate_menu(menu.id, c.user, merge_fields: %{language: :no}, change_fields: [])

      assert %{id: id} = Cache.Navigation.get(translated.key, "no")
      assert id == translated.id
    end

    test "a status set from the listing is in the cache", c do
      {:ok, menu} = Brando.Navigation.create_menu(menu("toggled"), c.user)
      {:ok, _} = Brando.Trait.Status.update_status(Brando.Navigation.Menu, menu.id, "draft", c.user)

      assert %{status: :draft} = Cache.Navigation.get("toggled", "en")
    end
  end

  describe "identity and SEO" do
    # The identity and SEO screens make the record of a language that has
    # none by copying the first one.
    test "a copy for another language is in the cache" do
      {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
      {:ok, _} = Brando.Sites.duplicate_identity(identity.id, :system, merge_fields: %{language: :no})
      assert %{language: :no} = Cache.Identity.get("no")

      {:ok, seo} = Brando.Sites.get_seo(%{matches: %{language: "en"}})
      {:ok, _} = Brando.Sites.duplicate_seo(seo.id, :system, merge_fields: %{language: :no})
      assert %{language: :no} = Cache.SEO.get("no")
    end

    test "a created record is in the cache", c do
      {:ok, _} = Brando.Sites.create_identity(%{name: "Norsk", type: "organization", language: "no"}, c.user)
      assert %{name: "Norsk"} = Cache.Identity.get("no")

      {:ok, _} = Brando.Sites.create_seo(%{fallback_meta_title: "Norsk", language: "no"}, c.user)
      assert %{fallback_meta_title: "Norsk"} = Cache.SEO.get("no")
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

    test "a palette deleted and restored, a copy and a deleted set refresh the caches", c do
      {:ok, palette} = Brando.Content.create_palette(palette("trashed"), c.owner)
      {:ok, _} = Brando.Content.delete_palette(palette.id, c.owner)
      refute "trashed" in palette_keys()

      {:ok, _} = Boundary.restore(c.owner, Repo.get!(Brando.Content.Palette, palette.id))
      assert "trashed" in palette_keys()

      {:ok, copy} = Brando.Content.duplicate_palette(palette.id, c.owner)
      assert copy.key in palette_keys()

      {:ok, set} = Brando.Sites.create_global_set(global_set("gone", c.owner), c.owner)
      {:ok, _} = Brando.Sites.delete_global_set(set.id, c.owner)
      refute Map.has_key?(Cache.Globals.get("en"), "gone")
    end

    # A copy runs in the boundary's own transaction: the refresh waits for it
    test "a menu and an identity copied refresh the caches", c do
      {:ok, menu} = Brando.Navigation.create_menu(menu("original"), c.owner)
      {:ok, copy} = Brando.Navigation.duplicate_menu(menu.id, c.owner)
      assert %{id: id} = Cache.Navigation.get(copy.key, "en")
      assert id == copy.id

      {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
      {:ok, _} = Brando.Sites.duplicate_identity(identity.id, c.owner, merge_fields: %{language: :no})
      assert %{language: :no} = Cache.Identity.get("no")
    end
  end
end
