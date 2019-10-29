defmodule <%= application_module %>.Schema do
  @moduledoc """
  Main graphQL schema definition
  """

  use Absinthe.Schema
  use Brando.Schema

  import_types <%= application_module %>.Schema.Types
  import_types Brando.Schema.Types

  query do
    import_brando_queries()

    # ++queries
    # __queries
  end

  mutation do
    import_brando_mutations()

    # ++mutations
    # __mutations
  end

  def middleware(middleware, _field, %{identifier: :mutation}), do:
    middleware ++ [Brando.Schema.Middleware.ChangesetErrors]
  def middleware(middleware, _field, _object), do:
    middleware
end
