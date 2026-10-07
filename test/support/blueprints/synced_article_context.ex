defmodule Brando.SyncTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.SyncTest.Article

  query :single, Article, do: fn query -> from(q in query) end

  matches Article do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Article, do: fn query -> from(q in query) end

  # A filter that depends on who asks: the clauses take the filter context
  filters Article do
    fn
      {:mine, "true"}, query, %{current_user: %{id: user_id}} -> from(q in query, where: q.creator_id == ^user_id)
      {:mine, _}, query, _ -> query
      {:kind, "featured_only"}, query, _ -> from(q in query, where: q.featured == true)
      {:title, title}, query, _ -> from(q in query, where: ilike(q.title, ^"%#{title}%"))
      {:featured, "true"}, query, _ -> from(q in query, where: q.featured == true)
      {:featured, _}, query, _ -> query
      {:status_filter, status}, query, _ -> by_listed_status(query, status)
    end
  end

  # The `:filters` listing's select: an empty choice is "All"
  defp by_listed_status(query, status) when status in [nil, ""], do: query
  defp by_listed_status(query, status), do: from(q in query, where: q.status == ^String.to_existing_atom(status))

  mutation :create, Article
  mutation :update, Article
  mutation :delete, Article

  mutation :duplicate, {Article, change_fields: [:title, :slug]}
end
