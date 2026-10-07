defmodule Brando.QueryTest do
  # async: false because cache tests share global :query cache state
  use ExUnit.Case, async: false
  use Brando.ConnCase
  import Ecto.Query
  alias Brando.Factory
  alias Brando.Pages.Page

  defmodule Context do
    use Brando.Query

    mutation :create, Page
    mutation :update, Page
    mutation :delete, Page

    query :list, Page do
      fn
        query -> from(q in query)
      end
    end

    filters Page do
      fn
        {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      end
    end

    query :single, Page do
      fn
        query -> from(q in query)
      end
    end

    matches Page do
      fn
        {:id, id}, query -> from q in query, where: q.id == ^id
      end
    end
  end

  defmodule Context2 do
    use Brando.Query

    query :single, Page do
      fn
        query -> from(q in query)
      end
    end

    matches Page do
      fn
        {:id, id}, query -> from q in query, where: q.id == ^id
      end
    end

    mutation :create, Page do
      fn entry ->
        {:ok, entry, :create}
      end
    end

    mutation :update, Page do
      fn entry ->
        {:ok, entry, :update}
      end
    end

    mutation :delete, Page do
      fn entry ->
        {:ok, entry, :delete}
      end
    end
  end

  describe "queries" do
    test "query :list" do
      assert __MODULE__.Context.module_info(:functions)
             |> Keyword.has_key?(:list_pages)

      _p1 = Factory.insert(:page, title: "page 1")
      _p2 = Factory.insert(:page, title: "page 2")
      _p3 = Factory.insert(:page, title: "page 3")

      {:ok, pages} = __MODULE__.Context.list_pages()

      assert Enum.count(pages) == 3

      {:ok, pages} = __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}})
      assert Enum.count(pages) == 1

      {:ok, [page]} =
        __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}, select: [:title]})

      assert page == %{title: "page 2"}

      {:ok, [page]} =
        __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}, select: {:map, [:title]}})

      assert page == %{title: "page 2"}

      {:ok, [page]} =
        __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}, select: {:struct, [:title]}})

      assert page.__struct__ == Page
      assert page.title == "page 2"
    end

    test "query :single" do
      assert __MODULE__.Context.module_info(:functions)
             |> Keyword.has_key?(:get_page)

      _p1 = Factory.insert(:page, title: "page 1")
      p2a = Factory.insert(:page, title: "page 2")

      {:ok, p2b} = __MODULE__.Context.get_page(%{matches: %{id: p2a.id}})
      assert p2b.id == p2a.id

      assert __MODULE__.Context.module_info(:functions)
             |> Keyword.has_key?(:get_page!)

      p2c = __MODULE__.Context.get_page!(%{matches: %{id: p2a.id}})
      assert p2c.id == p2a.id

      assert_raise Ecto.NoResultsError, fn ->
        _a = __MODULE__.Context.get_page!(%{matches: %{id: 2_934_857_239_485_723_948}})
      end
    end

    test "query :single cached" do
      Cachex.clear(:query)
      _p1 = Factory.insert(:page, title: "page 1")
      p2a = Factory.insert(:page, title: "page 2")

      {:ok, p2b} = __MODULE__.Context.get_page(%{matches: %{id: p2a.id}, cache: true})
      assert p2b.id == p2a.id

      # force a manual change that does not update cache
      {:ok, p2c} =
        p2b
        |> Page.changeset(%{title: "page 2 updated"}, :system)
        |> Brando.Repo.update()

      assert p2c.title == "page 2 updated"

      {:ok, p2d} = __MODULE__.Context.get_page(%{matches: %{id: p2a.id}, cache: true})

      refute p2d.title == p2c.title

      {:ok, p2e} =
        __MODULE__.Context.update_page(p2d.id, %{title: "page 2 busting cache"}, :system)

      {:ok, p2f} = __MODULE__.Context.get_page(%{matches: %{id: p2e.id}, cache: true})

      assert p2f.title == "page 2 busting cache"
    end

    test "query :list cached" do
      Cachex.clear(:query)
      p1 = Factory.insert(:page, title: "page 1")
      p2 = Factory.insert(:page, title: "page 2")

      {:ok, posts} = __MODULE__.Context.list_pages(%{cache: true})
      sorted_posts = Enum.sort(posts, &(&1.id <= &2.id))
      assert Enum.map(sorted_posts, & &1.title) == [p1.title, p2.title]

      # force a manual change that does not update cache
      {:ok, p2b} =
        p2
        |> Page.changeset(%{title: "page 2 updated"}, :system)
        |> Brando.Repo.update()

      assert p2b.title == "page 2 updated"

      {:ok, posts} = __MODULE__.Context.list_pages(%{cache: true})
      sorted_posts = Enum.sort(posts, &(&1.id <= &2.id))
      assert Enum.map(sorted_posts, & &1.title) == [p1.title, p2.title]

      {:ok, p2c} = __MODULE__.Context.update_page(p2b.id, %{title: "bleh"}, :system)
      {:ok, posts} = __MODULE__.Context.list_pages(%{cache: true})

      # ensure posts are in the same order as [p1.id, p2c.id]
      sorted_posts = Enum.sort(posts, &(&1.id <= &2.id))
      assert Enum.map(sorted_posts, & &1.title) == [p1.title, p2c.title]

      Cachex.clear(:query)
    end

    test "query :single revision" do
      usr = Factory.insert(:random_user)

      {:ok, p1} = Brando.Pages.create_page(Factory.params_for(:page, title: "Title 1"), usr)
      {:ok, _p1a} = Brando.Pages.update_page(p1.id, %{title: "Title 2"}, usr)
      {:ok, _p1b} = Brando.Pages.update_page(p1.id, %{title: "Title 3"}, usr)

      {:ok, p2} = Brando.Pages.get_page(%{matches: %{id: p1.id}, revision: 0})
      assert p2.title == "Title 1"
      {:ok, p2} = Brando.Pages.get_page(%{matches: %{id: p1.id}})
      assert p2.title == "Title 3"

      {:ok, p2} = Brando.Pages.get_page(%{matches: %{id: p1.id}, revision: 1})
      assert p2.title == "Title 2"
      {:ok, p2} = Brando.Pages.get_page(%{matches: %{id: p1.id}, revision: 2})
      assert p2.title == "Title 3"
    end
  end

  describe "status counts" do
    test "count every status in one grouped query, apart from the list's own status" do
      for status <- [:published, :published, :draft, :disabled],
          do: Factory.insert(:page, title: "Counted #{status}", status: status)

      Factory.insert(:page, title: "Counted trashed", status: :published, deleted_at: DateTime.utc_now(:second))
      Factory.insert(:page, title: "Other draft", status: :draft)

      ref = make_ref()
      parent = self()
      handler = "status-counts-#{inspect(ref)}"

      :telemetry.attach(
        handler,
        Brando.repo().config()[:telemetry_prefix] ++ [:query],
        fn _, _, meta, _ -> send(parent, {ref, meta.query}) end,
        nil
      )

      {:ok, %{entries: entries, status_counts: counts}} =
        __MODULE__.Context.list_pages(%{
          paginate: true,
          limit: 25,
          status: :draft,
          filter: %{title: "Counted"},
          status_counts: true
        })

      :telemetry.detach(handler)

      assert Enum.map(entries, & &1.title) == ["Counted draft"]
      # Pending has none and is still there; the trashed page counts as deleted only
      assert counts == %{published: 2, draft: 1, pending: 0, disabled: 1, deleted: 1}

      queries = collect_queries(ref)
      assert queries |> Enum.filter(&(&1 =~ "GROUP BY")) |> length() == 1
      assert length(queries) == 3
    end

    test "counts follow the language and are absent unless asked for" do
      Factory.insert(:page, title: "Lang en", language: :en, status: :pending)
      Factory.insert(:page, title: "Lang no", language: :no, status: :pending)

      {:ok, %{status_counts: counts}} =
        __MODULE__.Context.list_pages(%{
          paginate: true,
          limit: 25,
          language: "no",
          filter: %{title: "Lang"},
          status_counts: true
        })

      assert counts.pending == 1

      {:ok, page} = __MODULE__.Context.list_pages(%{paginate: true, limit: 25, filter: %{title: "Lang"}})
      refute Map.has_key?(page, :status_counts)
    end

    test "counts only what the admin may read" do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      owner = Factory.insert(:random_user, role: :superuser)
      user = Factory.insert(:random_user, role: :user)
      {:ok, _} = Brando.Authorization.Migration.run()
      Factory.insert(:page, title: "Scoped page", status: :draft)

      counts = fn ->
        Brando.Authorization.Boundary.with_scope(Brando.Authorization.Scope.standalone(user), fn ->
          {:ok, %{status_counts: counts}} =
            __MODULE__.Context.list_pages(%{paginate: true, limit: 25, filter: %{title: "Scoped"}, status_counts: true})

          counts
        end)
      end

      assert counts.() == %{published: 0, draft: 0, pending: 0, disabled: 0, deleted: 0}

      scope = Brando.Authorization.Scope.standalone(owner)

      {:ok, group} =
        Brando.Authorization.Groups.create(scope, %{name: "Readers"}, ~w(brando.admin.access brando.pages.read))

      {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, user.id)

      assert counts.().draft == 1
    end
  end

  defp collect_queries(ref) do
    receive do
      {^ref, query} -> [query | collect_queries(ref)]
    after
      0 -> []
    end
  end

  describe "mutations" do
    test "mutation :create" do
      usr = Factory.insert(:random_user)

      assert __MODULE__.Context.module_info(:functions)
             |> Keyword.has_key?(:create_page)

      pp1 = Factory.params_for(:page)

      {:ok, p1a} = __MODULE__.Context.create_page(pp1, usr)
      {:ok, p1b} = __MODULE__.Context.get_page(%{matches: %{id: p1a.id}})

      assert p1b.id == p1a.id
    end

    test "mutation :create with do block" do
      usr = Factory.insert(:random_user)

      assert __MODULE__.Context2.module_info(:functions)
             |> Keyword.has_key?(:create_page)

      pp1 = Factory.params_for(:page)

      assert {:ok, _, :create} = __MODULE__.Context2.create_page(pp1, usr)
    end

    test "mutation :update with do block" do
      usr = Factory.insert(:random_user)

      assert __MODULE__.Context2.module_info(:functions)
             |> Keyword.has_key?(:create_page)

      pp1 = Factory.params_for(:page)

      {:ok, page, :create} = __MODULE__.Context2.create_page(pp1, usr)
      assert {:ok, _, :update} = __MODULE__.Context2.update_page(page.id, %{uri: "blehzzz"}, usr)
    end

    test "mutation :delete with do block" do
      usr = Factory.insert(:random_user)

      assert __MODULE__.Context2.module_info(:functions)
             |> Keyword.has_key?(:create_page)

      pp1 = Factory.params_for(:page)

      {:ok, page, :create} = __MODULE__.Context2.create_page(pp1, usr)
      assert {:ok, _, :delete} = __MODULE__.Context2.delete_page(page.id)
    end

    test "mutation :update and :delete" do
      usr = Factory.insert(:random_user)

      assert __MODULE__.Context.module_info(:functions)
             |> Keyword.has_key?(:update_page)

      pp1 = Factory.params_for(:page)

      {:ok, p1a} = __MODULE__.Context.create_page(pp1, usr)
      {:ok, p2a} = __MODULE__.Context.update_page(p1a.id, %{title: "new title"}, usr)

      assert p2a.title == "new title"

      {:ok, p3a} = __MODULE__.Context.delete_page(p1a.id)

      assert_raise Ecto.NoResultsError, fn ->
        _a = __MODULE__.Context.get_page!(%{matches: %{id: p3a.id}})
      end
    end
  end
end
