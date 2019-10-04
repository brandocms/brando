defmodule <%= base %>.<%= domain %> do
  @moduledoc """
  Context for <%= human %>
  """

  # ++types
  @type id :: Integer.t() | String.t()
  @type params :: Map.t()
  @type user :: Brando.Users.User.t()
  # __types

  alias <%= base %>.Repo
  import Ecto.Query

  # ++header
  # __header

  # ++code
  # __code
end
