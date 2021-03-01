defmodule <%= application_module %>.Schema do
  @moduledoc """
  Main graphQL schema definition
  """

  use Absinthe.Schema
  use Brando.GraphQL.Schema

  import_types <%= application_module %>.Schema.Types
  import_types Brando.GraphQL.Schema.Types

  def context(ctx) do
    # ++dataloaders
    loader =
      Dataloader.new()
      |> import_brando_dataloaders(ctx)
    # __dataloaders

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end

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

  enum :sort_order do
    value :asc
    value :desc
  end

  def middleware(middleware, _field, %{identifier: :mutation}), do:
    middleware ++ [Brando.GraphQL.Schema.Middleware.ChangesetErrors]
  def middleware(middleware, _field, _object), do:
    middleware
end
