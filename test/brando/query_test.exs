defmodule Brando.QueryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  import Ecto.Query
  alias Brando.Factory

  defmodule Context do
    use Brando.Query

    mutation :create, Brando.Pages.Page
    mutation :update, Brando.Pages.Page
    mutation :delete, Brando.Pages.Page

    query :list, Brando.Pages.Page do
      fn
        query -> from q in query, where: is_nil(q.deleted_at)
      end
    end

    filters Brando.Pages.Page do
      fn
        {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      end
    end

    query :single, Brando.Pages.Page do
      fn
        query -> from q in query, where: is_nil(q.deleted_at)
      end
    end

    matches Brando.Pages.Page do
      fn
        {:id, id}, query -> from q in query, where: q.id == ^id
      end
    end
  end

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

    {:ok, [page]} = __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}, select: [:title]})
    assert page == %{title: "page 2"}

    {:ok, [page]} =
      __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}, select: {:map, [:title]}})

    assert page == %{title: "page 2"}

    {:ok, [page]} =
      __MODULE__.Context.list_pages(%{filter: %{title: "page 2"}, select: {:struct, [:title]}})

    assert page.__struct__ == Brando.Pages.Page
    assert page.title == "page 2"
    assert page.slug == nil
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

  test "mutation :create" do
    usr = Factory.insert(:random_user)

    assert __MODULE__.Context.module_info(:functions)
           |> Keyword.has_key?(:create_page)

    pp1 = Factory.params_for(:page)

    {:ok, p1a} = __MODULE__.Context.create_page(pp1, usr)
    {:ok, p1b} = __MODULE__.Context.get_page(%{matches: %{id: p1a.id}})

    assert p1b.id == p1a.id
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
