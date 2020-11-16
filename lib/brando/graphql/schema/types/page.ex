defmodule Brando.Schema.Types.Page do
  use Brando.Web, :absinthe

  object :page do
    field :id, :id
    field :key, :string
    field :language, :string
    field :title, :string
    field :slug, :string
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
    field :meta_title, :string
    field :meta_description, :string
    field :meta_image, :image_type
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
    field :publish_at, :time
  end

  input_object :page_params do
    field :parent_id, :id
    field :key, :string
    field :language, :string
    field :title, :string
    field :status, :string
    field :template, :string
    field :is_homepage, :boolean
    field :data, :json
    field :properties, list_of(:page_property_params)
    field :css_classes, :string
    field :meta_title, :string
    field :meta_description, :string
    field :meta_image, :upload_or_image
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

  @desc "Filtering options for page"
  input_object :page_filter do
    field :title, :string
  end

  object :template do
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

  input_object :template_params do
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

  @desc "Filtering options for template"
  input_object :template_filter do
    field :name, :string
    field :namespace, :string
  end

  object :page_queries do
    @desc "Get all pages"
    field :pages, type: list_of(:page) do
      arg :order, :order, default_value: [{:asc, :language}, {:asc, :sequence}, {:asc, :key}]
      arg :limit, :integer, default_value: 25
      arg :offset, :integer, default_value: 0
      arg :filter, :page_filter
      arg :status, :string, default_value: "all"
      resolve &Brando.Pages.PageResolver.all/2
    end

    @desc "Get page"
    field :page, type: :page do
      arg :page_id, non_null(:id)
      resolve &Brando.Pages.PageResolver.find/2
    end

    @desc "Get all templates"
    field :templates, type: list_of(:template) do
      arg :order, :order,
        default_value: [{:asc, :namespace}, {:asc, :sequence}, {:asc, :inserted_at}]

      arg :limit, :integer, default_value: 75
      arg :offset, :integer, default_value: 0
      arg :filter, :template_filter
      resolve &Brando.Pages.PageResolver.all_templates/2
    end

    @desc "Get template"
    field :template, type: :template do
      arg :template_id, non_null(:id)
      resolve &Brando.Pages.PageResolver.find_template/2
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

    field :delete_template, type: :template do
      arg :template_id, non_null(:id)

      resolve &Brando.Pages.PageResolver.delete_template/2
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

    @desc "Duplicate template"
    field :duplicate_template, type: :template do
      arg :template_id, :id

      resolve &Brando.Pages.PageResolver.duplicate_template/2
    end

    field :create_template, type: :template do
      arg :template_params, :template_params

      resolve &Brando.Pages.PageResolver.create_template/2
    end

    field :update_template, type: :template do
      arg :template_id, non_null(:id)
      arg :template_params, :template_params

      resolve &Brando.Pages.PageResolver.update_template/2
    end
  end
end
