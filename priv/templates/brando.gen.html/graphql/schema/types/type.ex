defmodule <%= base %>.Schema.Types.<%= alias %> do
  @moduledoc """
  GraphQL type spec, mutations and queries for <%= alias %>
  """
  use <%= base %>Web, :absinthe

  import Ecto.Query
  import Brando.Schema.Utils

  alias <%= base %>.Repo

  object :<%= singular %> do
    field :id, :id<%= for {v, k} <- gql_types do %>
    <%= k %><% end %>
    field :inserted_at, :time
    field :updated_at, :time
  end

  input_object :<%= singular %>_params do<%= for {v, k} <- gql_inputs do %>
    <%= k %><% end %>
  end

  object :<%= singular %>_queries do
    @desc "Get all <%= plural %>"
    field :<%= plural %>, type: list_of(:<%= singular %>) do
      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.all/2
    end

    @desc "Get <%= singular %>"
    field :<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)
      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.find/2
    end
  end

  object :<%= singular %>_mutations do
    field :create_<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_params, non_null(:<%= singular %>_params)

      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.create/2
    end

    field :update_<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)
      arg :<%= singular %>_params, :<%= singular %>_params

      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.update/2
    end

    field :delete_<%= singular %>, type :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)

      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.delete/2
    end
  end
end
