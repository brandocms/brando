defmodule Brando.QueryTest do
  use ExUnit.Case, async: true
  import Ecto.Query

  defmodule Context do
    use Brando.Query

    query :list, Brando.Pages.Page do
      fn
        query -> from q in query, where: is_nil(q.deleted_at)
      end
    end

    filters do
      fn
        {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      end
    end
  end

  test "query :list" do
    assert __MODULE__.Context.module_info(:functions)
           |> Keyword.has_key?(:list_pages)
  end
end
