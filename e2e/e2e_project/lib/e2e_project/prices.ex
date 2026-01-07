defmodule E2eProject.Prices do
  @moduledoc """
  Context for Prices
  """

  @type id :: integer | binary
  @type params :: map
  @type user :: Brando.Users.User.t()
  @type price_category :: E2eProject.Prices.PriceCategory.t()

  use Brando.Query
  import Ecto.Query

  alias E2eProject.Prices.PriceCategory

  #
  # PriceCategory

  mutation :create, PriceCategory
  mutation :update, PriceCategory
  mutation :delete, PriceCategory

  query :list, PriceCategory do
    fn query -> from t in query end
  end

  filters PriceCategory do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")
    end
  end

  query :single, PriceCategory, do: fn query -> from t in query end

  matches PriceCategory do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end
end
