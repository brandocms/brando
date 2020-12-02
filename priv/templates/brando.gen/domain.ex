defmodule <%= app_module %>.<%= domain %> do
  @moduledoc """
  Context for <%= human %>
  """

  # ++types
  @type id :: integer | binary
  @type params :: map
  @type user :: Brando.Users.User.t()
  # __types

  use Brando.Query
  alias <%= app_module %>.Repo
  import Ecto.Query

  # ++header
  # __header

  # ++code
  @doc """
  Dataloader initializer
  """
  def data() do
    Dataloader.Ecto.new(
      Brando.repo(),
      query: &dataloader_query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def dataloader_query(queryable, _), do: queryable

  # __code
end
