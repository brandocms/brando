defmodule Brando.Schema.Types.PageFragment do
  use Brando.Web, :absinthe

  object :page_fragment do
    field :id, :id
    field :title, :string
    field :parent_key, :string
    field :key, :string
    field :language, :string
    field :wrapper, :string
    field :data, :json
    field :html, :string
    field :creator, :user
    field :page_id, :id
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  input_object :page_fragment_params do
    field :title, :string
    field :parent_key, :string
    field :key, :string
    field :language, :string
    field :wrapper, :string
    field :data, :json
    field :page_id, :id
  end

  object :page_fragment_queries do
    @desc "Get all page_fragments"
    field :page_fragments, type: list_of(:page_fragment) do
      resolve &Brando.Pages.PageFragmentResolver.all/2
    end

    @desc "Get page_fragment"
    field :page_fragment, type: :page_fragment do
      arg :page_fragment_id, non_null(:id)
      resolve &Brando.Pages.PageFragmentResolver.find/2
    end
  end

  object :page_fragment_mutations do
    field :create_page_fragment, type: :page_fragment do
      arg :page_fragment_params, non_null(:page_fragment_params)

      resolve &Brando.Pages.PageFragmentResolver.create/2
    end

    field :update_page_fragment, type: :page_fragment do
      arg :page_fragment_id, non_null(:id)
      arg :page_fragment_params, :page_fragment_params

      resolve &Brando.Pages.PageFragmentResolver.update/2
    end

    field :delete_page_fragment, type: :page_fragment do
      arg :page_fragment_id, non_null(:id)

      resolve &Brando.Pages.PageFragmentResolver.delete/2
    end
  end
end
