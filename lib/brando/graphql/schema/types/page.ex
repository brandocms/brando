defmodule Brando.Schema.Types.Page do
  use Brando.Web, :absinthe

  import Ecto.Query
  import Brando.Schema.Utils

  input_object :page_params do
    field :parent_id, :id
    field :key, :string
    field :language, :string
    field :title, :string
    field :status, :string
    field :data, :json
    field :css_classes, :string
    field :meta_description, :string
    field :meta_keywords, :string
  end

  object :page do
    field :id, :id
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
    field :data, :json
    field :html, :string
    field :status, :string
    field :css_classes, :string
    field :creator, :user
    field :parent_id, :id
    field :parent, :page, resolve: assoc(:parent)
    field :children, list_of(:page), resolve: assoc(:children)
    field :meta_description, :string
    field :meta_keywords, :string
    field :inserted_at, :time
    field :updated_at, :time
  end

  object :page_queries do
    @desc "Get all pages"
    field :pages, type: list_of(:page) do
      resolve &Brando.Pages.PageResolver.all/2
    end

    @desc "Get page"
    field :page, type: :page do
      arg :page_id, non_null(:id)
      resolve &Brando.Pages.PageResolver.find/2
    end
  end

  object :page_mutations do
    field :create_page, type: :page do
      arg :page_params, :page_params

      resolve &Brando.Pages.PageResolver.create/2
    end

    field :update_page, type: :page do
      arg :page_id, non_null(:id)
      arg :page_params, :page_params

      resolve &Brando.Pages.PageResolver.update/2
    end

    field :delete_page, type: :page do
      arg :page_id, non_null(:id)

      resolve &Brando.Pages.PageResolver.delete/2
    end
  end
end
