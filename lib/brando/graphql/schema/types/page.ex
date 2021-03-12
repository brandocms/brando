defmodule Brando.GraphQL.Schema.Types.Page do
  use Brando.Web, :absinthe
  use Brando.Meta.GraphQL

  object :pages do
    field :entries, list_of(:page)
    field :pagination_meta, non_null(:pagination_meta)
  end

  object :page do
    field :id, :id
    field :uri, :string
    field :language, :string
    field :title, :string
    field :data, :json
    field :html, :string
    field :status, :string
    field :template, :string
    field :css_classes, :string
    field :is_homepage, :boolean
    field :creator, :user, resolve: dataloader(Brando.Pages)
    field :parent_id, :id
    field :parent, :page, resolve: dataloader(Brando.Pages)
    field :children, list_of(:page), resolve: dataloader(Brando.Pages)
    field :fragments, list_of(:page_fragment), resolve: dataloader(Brando.Pages)
    field :properties, list_of(:page_property), resolve: dataloader(Brando.Pages)
    meta_fields()
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
    field :publish_at, :time
  end

  input_object :page_params do
    field :parent_id, :id
    field :uri, :string
    field :language, :string
    field :title, :string
    field :status, :string
    field :template, :string
    field :is_homepage, :boolean
    field :data, :json
    field :properties, list_of(:page_property_params)
    field :css_classes, :string
    meta_params()
    field :publish_at, :time
  end

  object :page_property do
    field :id, :id
    field :label, :string
    field :type, :string
    field :key, :string
    field :data, :json
  end

  input_object :page_property_params do
    field :id, :id
    field :label, :string
    field :type, :string
    field :key, :string
    field :data, :json
  end

  object :module do
    field :id, :id
    field :name, :string
    field :namespace, :string
    field :help_text, :string
    field :class, :string
    field :code, :string
    field :refs, :json
    field :vars, :json
    field :svg, :string
    field :multi, :boolean
    field :wrapper, :string
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  input_object :module_params do
    field :name, :string
    field :namespace, :string
    field :help_text, :string
    field :class, :string
    field :code, :string
    field :refs, :json
    field :vars, :json
    field :svg, :string
    field :multi, :boolean
    field :wrapper, :string
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  @desc "Filtering options for page"
  input_object :page_filter do
    field :title, :string
    field :uri, :string
    field :parents, :boolean
  end

  @desc "Matching options for page"
  input_object :page_matches do
    field :id, :id
  end

  @desc "Filtering options for module"
  input_object :module_filter do
    field :name, :string
    field :namespace, :string
  end

  object :page_queries do
    @desc "Get all pages"
    field :pages, type: :pages do
      arg :order, :order, default_value: [{:asc, :language}, {:asc, :sequence}, {:asc, :uri}]
      arg :limit, :integer, default_value: 25
      arg :offset, :integer, default_value: 0
      arg :filter, :page_filter
      arg :status, :string, default_value: "all"
      resolve &Brando.Pages.PageResolver.all/2
    end

    @desc "Get page"
    field :page, type: :page do
      arg :matches, :page_matches
      arg :revision, :id
      arg :status, :string, default_value: "all"
      resolve &Brando.Pages.PageResolver.get/2
    end

    @desc "Get all modules"
    field :modules, type: list_of(:module) do
      arg :order, :order,
        default_value: [{:asc, :namespace}, {:asc, :sequence}, {:asc, :inserted_at}]

      arg :limit, :integer, default_value: 75
      arg :offset, :integer, default_value: 0
      arg :filter, :module_filter
      resolve &Brando.Pages.PageResolver.all_modules/2
    end

    @desc "Get module"
    field :module, type: :module do
      arg :module_id, non_null(:id)
      resolve &Brando.Pages.PageResolver.get_module/2
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
      arg :revision, :id

      resolve &Brando.Pages.PageResolver.update/2
    end

    field :delete_page, type: :page do
      arg :page_id, non_null(:id)

      resolve &Brando.Pages.PageResolver.delete/2
    end

    field :delete_module, type: :module do
      arg :module_id, non_null(:id)

      resolve &Brando.Pages.PageResolver.delete_module/2
    end

    @desc "Duplicate page"
    field :duplicate_page, type: :page do
      arg :page_id, :id

      resolve &Brando.Pages.PageResolver.duplicate/2
    end

    @desc "Duplicate section"
    field :duplicate_section, type: :page_fragment do
      arg :section_id, :id

      resolve &Brando.Pages.PageResolver.duplicate_section/2
    end

    @desc "Duplicate module"
    field :duplicate_module, type: :module do
      arg :module_id, :id

      resolve &Brando.Pages.PageResolver.duplicate_module/2
    end

    field :create_module, type: :module do
      arg :module_params, :module_params

      resolve &Brando.Pages.PageResolver.create_module/2
    end

    field :update_module, type: :module do
      arg :module_id, non_null(:id)
      arg :module_params, :module_params

      resolve &Brando.Pages.PageResolver.update_module/2
    end
  end
end
