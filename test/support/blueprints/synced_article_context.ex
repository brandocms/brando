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
    end
  end

  mutation :create, Article
  mutation :update, Article
  mutation :delete, Article

  mutation :duplicate, {Article, change_fields: [:title, :slug]}
end
