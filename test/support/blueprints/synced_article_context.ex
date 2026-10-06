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
    end
  end

  mutation :create, Article
  mutation :update, Article
  mutation :delete, Article

  mutation :duplicate, {Article, change_fields: [:title, :slug]}
end

defmodule Brando.SyncTest.ArticleListing do
  @moduledoc false
  # The `:user_context` listing's callbacks
  use Phoenix.Component

  import Ecto.Query

  def put_viewer(entries, user), do: Enum.map(entries, &Map.put(&1, :viewer, user.name))

  def row(assigns) do
    ~H"""
    <div class="user-context-row" data-viewer={@entry.viewer} data-user={@current_user.name}>{@entry.title}</div>
    """
  end

  def longest_title_first(query), do: from(q in query, order_by: [desc: fragment("length(?)", q.title), asc: q.id])

  def never(_user), do: false
  def named?(user), do: is_binary(user.name)
end
