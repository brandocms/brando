defmodule BrandoGraphQL.Schema.Types.Fragment do
  use BrandoAdmin, :absinthe

  object :fragment do
    field :id, :id
    field :title, :string
    field :parent_key, :string
    field :key, :string
    field :language, :string
    field :wrapper, :string
    field :data, :json
    field :html, :string
    field :creator, :user, resolve: dataloader(Brando.Pages)
    field :page_id, :id
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  input_object :fragment_params do
    field :title, :string
    field :parent_key, :string
    field :key, :string
    field :language, :string
    field :wrapper, :string
    field :data, :json
    field :page_id, :id
  end

  @desc "Matching options for fragment"
  input_object :fragment_matches do
    field :id, :id
  end

  object :fragment_queries do
    @desc "Get all fragments"
    field :fragments, type: list_of(:fragment) do
      resolve &Brando.Pages.FragmentResolver.all/2
    end

    @desc "Get fragment"
    field :fragment, type: :fragment do
      arg :matches, :fragment_matches
      arg :revision, :id
      arg :status, :string, default_value: "all"
      resolve &Brando.Pages.FragmentResolver.get/2
    end
  end

  object :fragment_mutations do
    field :create_fragment, type: :fragment do
      arg :fragment_params, non_null(:fragment_params)

      resolve &Brando.Pages.FragmentResolver.create/2
    end

    field :update_fragment, type: :fragment do
      arg :fragment_id, non_null(:id)
      arg :fragment_params, :fragment_params

      resolve &Brando.Pages.FragmentResolver.update/2
    end

    field :delete_fragment, type: :fragment do
      arg :fragment_id, non_null(:id)

      resolve &Brando.Pages.FragmentResolver.delete/2
    end
  end
end
