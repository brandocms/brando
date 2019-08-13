defmodule Brando.Schema.Types.Link do
  @moduledoc """
  GraphQL type spec, mutations and queries for Link
  """
  use Brando.Web, :absinthe

  object :link do
    field :id, :id
    field :name, :string
    field :url, :string
    field :inserted_at, :time
    field :updated_at, :time
  end

  input_object :link_params do
    field :name, :string
    field :url, :string
  end

  object :link_queries do
    @desc "Get all links"
    field :links, type: list_of(:link) do
      resolve &Brando.Sites.LinkResolver.all/2
    end

    @desc "Get link"
    field :link, type: :link do
      arg :link_id, non_null(:id)
      resolve &Brando.Sites.LinkResolver.get/2
    end
  end

  object :link_mutations do
    field :create_link, type: :link do
      arg :link_params, non_null(:link_params)

      resolve &Brando.Sites.LinkResolver.create/2
    end

    field :update_link, type: :link do
      arg :link_id, non_null(:id)
      arg :link_params, :link_params

      resolve &Brando.Sites.LinkResolver.update/2
    end

    field :delete_link, type: :link do
      arg :link_id, non_null(:id)

      resolve &Brando.Sites.LinkResolver.delete/2
    end
  end
end
