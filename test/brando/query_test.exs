defmodule Brando.QueryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  import Ecto.Query
  alias Brando.Factory

  defmodule Context do
    use Brando.Query

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
end
