defmodule Brando.ListingViewsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Authorization.Catalog
  alias Brando.Authorization.Groups
  alias Brando.Authorization.Migration
  alias Brando.Authorization.Scope
  alias Brando.Factory
  alias Brando.ListingViews
  alias Brando.ListingViews.Params
  alias Brando.ListingViews.View
  alias Brando.SyncTest.Article

  @params %{"filter:featured" => "true", "status" => "draft"}

  defp user(role), do: Factory.insert(:random_user, role: role)

  defp view!(user, name, attrs \\ %{}) do
    {:ok, view} =
      ListingViews.create_view(user, Article, :filters, Map.merge(%{"name" => name, "params" => @params}, attrs))

    view
  end

  defp names(views), do: Enum.map(views, & &1.name)

  describe "storage" do
    test "a view keeps its name, parameters and listing" do
      editor = user(:editor)
      view = view!(editor, "  Featured drafts ")

      assert %View{name: "Featured drafts", params: @params, shared: false, listing: "filters"} = view
      assert view.schema == "Elixir.Brando.SyncTest.Article"
      assert view.creator.id == editor.id
    end

    test "a name is required, at most 60 characters, and once per person and listing" do
      editor = user(:editor)

      assert {:error, changeset} = ListingViews.create_view(editor, Article, :filters, %{"name" => " "})
      assert changeset.errors[:name]

      assert {:error, changeset} =
               ListingViews.create_view(editor, Article, :filters, %{"name" => String.duplicate("a", 61)})

      assert changeset.errors[:name]

      view!(editor, "Mine")
      assert {:error, changeset} = ListingViews.create_view(editor, Article, :filters, %{"name" => "Mine"})
      assert changeset.errors[:name]

      # Another listing, or another person, may use the name
      assert {:ok, _} = ListingViews.create_view(editor, Article, :default, %{"name" => "Mine"})
      assert {:ok, _} = ListingViews.create_view(user(:editor), Article, :filters, %{"name" => "Mine"})
    end

    test "parameters are flat strings, as in a URL" do
      assert {:error, changeset} =
               ListingViews.create_view(user(:editor), Article, :filters, %{
                 "name" => "Nested",
                 "params" => %{"order" => %{"asc" => "title"}}
               })

      assert changeset.errors[:params]
    end

    test "a person sees their own views and the shared ones, by name, on that listing only" do
      [me, colleague] = [user(:editor), user(:editor)]
      view!(me, "b mine")
      view!(colleague, "A shared", %{"shared" => true})
      view!(colleague, "Theirs")
      {:ok, _} = ListingViews.create_view(me, Article, :default, %{"name" => "Other listing"})

      assert names(ListingViews.list_views(me, Article, :filters)) == ["A shared", "b mine"]
      assert names(ListingViews.list_views(colleague, Article, "filters")) == ["A shared", "Theirs"]
    end

    test "get_view finds a visible view by id, nothing else" do
      [me, colleague] = [user(:editor), user(:editor)]
      theirs = view!(colleague, "Theirs")
      shared = view!(colleague, "Shared", %{"shared" => true})

      assert {:ok, %View{name: "Shared"}} = ListingViews.get_view(me, Article, :filters, to_string(shared.id))
      assert {:error, :not_found} = ListingViews.get_view(me, Article, :filters, theirs.id)
      assert {:error, :not_found} = ListingViews.get_view(me, Article, :default, shared.id)
      assert {:error, :not_found} = ListingViews.get_view(me, Article, :filters, "1; drop")
    end
  end

  describe "managing views" do
    test "the creator updates, renames, shares and deletes their own view" do
      editor = user(:editor)
      view = view!(editor, "Mine")

      assert {:ok, view} =
               ListingViews.update_view(editor, view, %{"name" => "Renamed", "params" => %{"limit" => "50"}})

      assert %View{name: "Renamed", params: %{"limit" => "50"}} = view
      assert {:ok, %View{shared: true} = view} = ListingViews.update_view(editor, view, %{"shared" => true})
      assert {:ok, _} = ListingViews.delete_view(editor, view)
      assert ListingViews.list_views(editor, Article, :filters) == []
    end

    test "someone else's shared view is managed only by an admin" do
      [owner, editor, admin] = [user(:editor), user(:editor), user(:admin)]
      shared = view!(owner, "Shared", %{"shared" => true})

      refute ListingViews.can_manage?(editor, shared)
      assert {:error, :forbidden} = ListingViews.update_view(editor, shared, %{"name" => "Mine now"})
      assert {:error, :forbidden} = ListingViews.delete_view(editor, shared)

      assert ListingViews.can_manage?(admin, shared)
      assert {:ok, %View{name: "Tidied"} = shared} = ListingViews.update_view(admin, shared, %{"name" => "Tidied"})
      assert {:ok, _} = ListingViews.delete_view(admin, shared)
    end

    test "nobody manages someone else's personal view, an admin neither" do
      owner = user(:editor)
      personal = view!(owner, "Personal")

      for other <- [user(:editor), user(:admin), user(:superuser)] do
        refute ListingViews.can_manage?(other, personal)
        assert {:error, :forbidden} = ListingViews.delete_view(other, personal)
      end
    end
  end

  describe "default views" do
    test "a person opens a listing with the view they picked, theirs or a shared one" do
      [me, colleague] = [user(:editor), user(:editor)]
      mine = view!(me, "Mine")
      shared = view!(colleague, "Shared", %{"shared" => true})

      assert ListingViews.default_view(me, Article, :filters) == nil

      assert {:ok, _} = ListingViews.set_default(me, mine)
      assert %View{name: "Mine"} = ListingViews.default_view(me, Article, :filters)

      # One per person and listing: the next replaces it
      assert {:ok, _} = ListingViews.set_default(me, shared)
      assert %View{name: "Shared"} = ListingViews.default_view(me, Article, :filters)
      assert ListingViews.default_view(colleague, Article, :filters) == nil
      assert ListingViews.default_view(me, Article, :default) == nil

      assert :ok = ListingViews.clear_default(me, Article, :filters)
      assert ListingViews.default_view(me, Article, :filters) == nil
    end

    test "someone else's personal view cannot be a default, and one no longer shared stops being one" do
      [me, colleague] = [user(:editor), user(:editor)]
      theirs = view!(colleague, "Theirs")
      shared = view!(colleague, "Shared", %{"shared" => true})

      assert {:error, :forbidden} = ListingViews.set_default(me, theirs)

      assert {:ok, _} = ListingViews.set_default(me, shared)
      {:ok, _} = ListingViews.update_view(colleague, shared, %{"shared" => false})
      assert ListingViews.default_view(me, Article, :filters) == nil
    end

    test "a deleted view is nobody's default any more" do
      me = user(:editor)
      view = view!(me, "Mine")
      {:ok, _} = ListingViews.set_default(me, view)
      {:ok, _} = ListingViews.delete_view(me, view)

      assert ListingViews.default_view(me, Article, :filters) == nil
    end
  end

  describe "per site environment" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      :ok
    end

    test "a view belongs to the environment it was saved in" do
      editor = user(:editor)

      for prefix <- ["tenant_views-a_production", "tenant_views-b_production"] do
        BrandoIntegration.Repo.query!(~s|CREATE SCHEMA "#{prefix}"|)

        for table <- ~w(listing_views listing_view_defaults),
            do: BrandoIntegration.Repo.query!(~s|CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)|)
      end

      Brando.Tenant.with_prefix("tenant_views-a_production", fn -> view!(editor, "In A", %{"shared" => true}) end)

      Brando.Tenant.with_prefix("tenant_views-b_production", fn ->
        assert ListingViews.list_views(editor, Article, :filters) == []
      end)

      Brando.Tenant.with_prefix("tenant_views-a_production", fn ->
        assert names(ListingViews.list_views(editor, Article, :filters)) == ["In A"]
      end)

      assert ListingViews.list_views(editor, Article, :filters) == []
    end

    test "an environment without the brando_215 tables has no views, and saving one is refused" do
      editor = user(:editor)
      BrandoIntegration.Repo.query!(~s|CREATE SCHEMA "tenant_old_production"|)

      Brando.Tenant.with_prefix("tenant_old_production", fn ->
        assert ListingViews.list_views(editor, Article, :filters) == []
        assert ListingViews.default_view(editor, Article, :filters) == nil
        assert {:error, :unavailable} = ListingViews.create_view(editor, Article, :filters, %{"name" => "Old"})
      end)

      # The transaction carries on
      assert ListingViews.list_views(editor, Article, :filters) == []
    end
  end

  describe "with group authorization" do
    setup do
      owner = user(:superuser)
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      scope = Scope.standalone(owner)

      member = fn keys ->
        person = user(:user)
        {:ok, group} = Groups.create(scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
        {:ok, :ok} = Groups.add_member(scope, group.id, person.id)
        person
      end

      readers = [Catalog.get(:access, :backend).key, Catalog.get(:read, Article).key]
      %{member: member, readers: readers}
    end

    test "views are seen and saved only with read access to the listing", %{member: member, readers: readers} do
      reader = member.(readers)
      outsider = member.([Catalog.get(:access, :backend).key])
      shared = view!(reader, "Shared", %{"shared" => true})

      assert names(ListingViews.list_views(reader, Article, :filters)) == ["Shared"]
      assert ListingViews.list_views(outsider, Article, :filters) == []
      assert {:error, :not_found} = ListingViews.get_view(outsider, Article, :filters, shared.id)
      assert {:error, :forbidden} = ListingViews.create_view(outsider, Article, :filters, %{"name" => "No"})
      assert {:error, :forbidden} = ListingViews.set_default(outsider, shared)
    end

    test "the Shared listing views permission manages other people's shared views", %{member: member, readers: readers} do
      owner = member.(readers)
      reader = member.(readers)
      moderator = member.(readers ++ [Catalog.get(:manage, :listing_views).key])
      shared = view!(owner, "Shared", %{"shared" => true})

      assert Catalog.get(:manage, :listing_views).key == "brando.listing_views.manage"
      refute ListingViews.moderator?(reader)
      assert ListingViews.moderator?(moderator)
      assert {:error, :forbidden} = ListingViews.delete_view(reader, shared)
      assert {:ok, _} = ListingViews.delete_view(moderator, shared)
    end
  end

  describe "parameters" do
    defp listing(name), do: Enum.find(Article.__listings__(), &(&1.name == name))

    test "a view saves the filters, status, sort and page size from the URL, not the page" do
      query = %{
        "filter:title" => "news",
        "filter:featured" => "true",
        "filter:status_filter" => "draft",
        "status" => "published",
        "limit" => "50",
        "page" => "3",
        "view" => "12",
        "q" => "elsewhere"
      }

      assert Params.from_query(query, listing(:filters), Article) == %{
               "filter:title" => "news",
               "filter:featured" => "true",
               "filter:status_filter" => "draft",
               "status" => "published",
               "limit" => "50"
             }
    end

    test "the sort is saved by its key, however the URL gave it" do
      listing = listing(:user_context)
      oldest = Enum.find(listing.sorts, &(&1.key == :oldest))

      assert Params.from_query(%{"order[asc]" => "id"}, listing, Article, oldest) == %{"sort" => "oldest"}
      assert Params.from_query(%{"sort" => "oldest"}, listing, Article, oldest) == %{"sort" => "oldest"}
      # The listing's own order is not a choice to save
      assert Params.from_query(%{}, listing, Article, oldest) == %{}
    end

    test "what the listing no longer has is dropped" do
      stale = %{
        "filter:gone" => "x",
        "filter:featured" => "maybe",
        "filter:status_filter" => "archived",
        "filter:title" => "",
        "status" => "vanished",
        "sort" => "removed",
        "limit" => "lots",
        "order" => "asc title"
      }

      assert Params.sanitize(stale, listing(:filters), Article) == %{}

      assert Params.sanitize(Map.put(stale, "filter:title", "kept"), listing(:filters), Article) == %{
               "filter:title" => "kept"
             }

      assert Params.sanitize(%{"sort" => "oldest", "limit" => "0"}, listing(:user_context), Article) == %{
               "sort" => "oldest",
               "limit" => "0"
             }

      assert Params.sanitize(nil, listing(:filters), Article) == %{}
    end
  end
end
