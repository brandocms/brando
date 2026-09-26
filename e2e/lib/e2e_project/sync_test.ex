defmodule E2eProject.SyncTest do
  @moduledoc "Context for the synchronized-translation fixture."
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias E2eProject.SyncTest.Article

  query :single, Article, do: fn query -> from(q in query) end

  matches Article do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, Article, do: fn query -> from(q in query) end

  mutation :create, Article
  mutation :update, Article
  mutation :delete, Article

  mutation :duplicate, {Article, []}
end
