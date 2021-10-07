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
  import Ecto.Query

  # ++header
  # __header

  # ++code
  # __code
end
