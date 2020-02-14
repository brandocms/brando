defmodule <%= base %>.Schema.Types.<%= alias %> do
  @moduledoc """
  GraphQL type spec, mutations and queries for <%= alias %>
  """
  use <%= base %>Web, :absinthe

  object :<%= singular %> do
    field :id, :id<%= for {_v, k} <- gql_types do %>
    <%= k %><% end %><%= if soft_delete do %>
    field :deleted_at, :time<% end %><%= if creator do %>
    field :creator, :user, resolve: dataloader(Brando.Users)<% end %>
    field :inserted_at, :time
    field :updated_at, :time
  end

  input_object :<%= singular %>_params do<%= for {_v, k} <- gql_inputs do %>
    <%= k %><% end %>
  end

  @desc "Filtering options for <%= singular %>"
  input_object :<%= singular %>_filter do
    <%= List.first(gql_types) |> elem(1) %>
    # field :featured, :boolean
  end

  @desc "Ordering options for <%= singular %>"
  input_object :<%= singular %>_order do
    field :dir, :sort_order
    field :by, :string
  end

  object :<%= singular %>_queries do
    @desc "Get all <%= plural %>"
    field :<%= plural %>, type: list_of(:<%= singular %>) do
      arg :order, :<%= singular %>_order, default_value: {:asc, :sequence}
      arg :limit, :integer, default_value: 25
      arg :offset, :integer, default_value: 0
      arg :filter, :<%= singular %>_filter
      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.all/2
    end

    @desc "Get <%= singular %>"
    field :<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)
      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.get/2
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

    field :delete_<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)

      resolve &<%= base %>.<%= domain %>.<%= alias %>Resolver.delete/2
    end
  end
end
