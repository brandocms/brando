defmodule <%= app_module %>.Schema.Types.<%= alias %> do
  @moduledoc """
  GraphQL type spec, mutations and queries for <%= alias %>
  """
  use <%= web_module %>, :absinthe<%= if meta do %>
  use Brando.Meta.GraphQL<% end %>

  object :<%= plural %> do
    field :entries, list_of(:<%= singular %>)
    field :pagination_meta, non_null(:pagination_meta)
  end

  object :<%= singular %> do
    field :id, :integer<%= for {_v, k} <- gql_types do %>
    <%= k %><% end %><%= if soft_delete do %>
    field :deleted_at, :time<% end %><%= if creator do %>
    field :creator, :user, resolve: dataloader(Brando.Users)<% end %><%= if meta do %>
    meta_fields()<% end %><%= if publish_at do %>
    field :publish_at, :time<% end %>
    field :inserted_at, :time
    field :updated_at, :time
  end

  input_object :<%= singular %>_params do<%= for {_v, k} <- gql_inputs do %>
    <%= k %><% end %><%= if meta do %>
    meta_params()<% end %>
  end

  @desc "Filtering options for <%= singular %>"
  input_object :<%= singular %>_filter do
    <%= List.first(gql_types) |> elem(1) %>
    # field :featured, :boolean
  end

  @desc "Matching options for <%= singular %>"
  input_object :<%= singular %>_matches do
    field :id, :id
  end

  object :<%= singular %>_queries do
    @desc "Get all <%= plural %>"
    field :<%= plural %>, type: :<%= plural %> do
      arg :order, :order, default_value: [{:asc, <%= if sequenced do %>:sequence<% else %>:<%= main_field %><% end %>}]
      arg :limit, :integer, default_value: 25
      arg :offset, :integer, default_value: 0
      arg :filter, :<%= singular %>_filter
      arg :status, :string

      resolve &<%= app_module %>.<%= domain %>.<%= alias %>Resolver.all/2
    end

    @desc "Get <%= singular %>"
    field :<%= singular %>, type: :<%= singular %> do
      arg :matches, :<%= singular %>_matches
      arg :revision, :id
      arg :status, :string, default_value: "all"

      resolve &<%= app_module %>.<%= domain %>.<%= alias %>Resolver.get/2
    end
  end

  object :<%= singular %>_mutations do
    @desc "Create <%= singular %>"
    field :create_<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_params, non_null(:<%= singular %>_params)

      resolve &<%= app_module %>.<%= domain %>.<%= alias %>Resolver.create/2
    end

    @desc "Update <%= singular %>"
    field :update_<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)
      arg :<%= singular %>_params, :<%= singular %>_params
      arg :revision, :id

      resolve &<%= app_module %>.<%= domain %>.<%= alias %>Resolver.update/2
    end

    @desc "Delete <%= singular %>"
    field :delete_<%= singular %>, type: :<%= singular %> do
      arg :<%= singular %>_id, non_null(:id)

      resolve &<%= app_module %>.<%= domain %>.<%= alias %>Resolver.delete/2
    end
  end
end
