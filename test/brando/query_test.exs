defmodule Brando.QueryTest do
  use ExUnit.Case, async: true
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
        query -> from q in query, where: is_nil(q.deleted_at)
      end
    end

    filters Page do
      fn
        {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      end
    end

    query :single, Page do
      fn
        query -> from q in query, where: is_nil(q.deleted_at)
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
        query -> from q in query, where: is_nil(q.deleted_at)
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
      _p1 = Factory.insert(:page, title: "page 1")
      p2a = Factory.insert(:page, title: "page 2")

      {:ok, p2b} = __MODULE__.Context.get_page(%{matches: %{id: p2a.id}, cache: true})
      assert p2b.id == p2a.id

      # force a manual change that does not update cache
      {:ok, p2c} =
        p2b
        |> Page.changeset(%{title: "page 2 updated"}, :system)
        |> Brando.repo().update

      assert p2c.title == "page 2 updated"

      {:ok, p2d} = __MODULE__.Context.get_page(%{matches: %{id: p2a.id}, cache: true})

      refute p2d.title == p2c.title
    end

    test "query :list cached" do
      p1 = Factory.insert(:page, title: "page 1")
      p2 = Factory.insert(:page, title: "page 2")

      {:ok, posts} = __MODULE__.Context.list_pages(%{cache: true})
      assert Enum.map(posts, & &1.title) == [p1.title, p2.title]

      # force a manual change that does not update cache
      {:ok, p2b} =
        p2
        |> Page.changeset(%{title: "page 2 updated"}, :system)
        |> Brando.repo().update

      assert p2b.title == "page 2 updated"

      {:ok, posts} = __MODULE__.Context.list_pages(%{cache: true})
      assert Enum.map(posts, & &1.title) == [p1.title, p2.title]

      {:ok, p2c} = __MODULE__.Context.update_page(p2b.id, %{title: "bleh"}, :system)

      {:ok, posts} = __MODULE__.Context.list_pages(%{cache: true})
      assert Enum.map(posts, & &1.title) == [p1.title, p2c.title]
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
