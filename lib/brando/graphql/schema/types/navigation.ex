defmodule Brando.Schema.Types.Navigation do
  use Brando.Web, :absinthe

  object :menu do
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
    field :creator, :user, resolve: dataloader(Brando.Pages)
    field :parent_id, :id
    field :parent, :menu, resolve: dataloader(Brando.Pages)
    field :children, list_of(:menu), resolve: dataloader(Brando.Pages)
    field :fragments, list_of(:menu_fragment), resolve: dataloader(Brando.Pages)
    field :meta_description, :string
    field :meta_image, :image_type
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  input_object :menu_params do
    field :parent_id, :id
    field :key, :string
    field :language, :string
    field :title, :string
    field :status, :string
    field :template, :string
    field :data, :json
    field :css_classes, :string
    field :meta_description, :string
    field :meta_image, :upload_or_image
  end

  @desc "Filtering options for menu"
  input_object :menu_filter do
    field :title, :string
  end

  object :navigation_queries do
    @desc "Get all menus"
    field :menus, type: list_of(:menu) do
      arg :order, :order, default_value: [{:asc, :language}, {:asc, :sequence}, {:asc, :key}]
      arg :limit, :integer, default_value: 25
      arg :offset, :integer, default_value: 0
      arg :filter, :menu_filter
      arg :status, :string, default_value: "all"
      resolve &Brando.Pages.PageResolver.all/2
    end

    @desc "Get menu"
    field :menu, type: :menu do
      arg :menu_id, non_null(:id)
      resolve &Brando.Pages.PageResolver.find/2
    end
  end

  object :navigation_mutations do
    field :create_menu, type: :menu do
      arg :menu_params, :menu_params

      resolve &Brando.Pages.PageResolver.create/2
    end

    field :update_menu, type: :menu do
      arg :menu_id, non_null(:id)
      arg :menu_params, :menu_params

      resolve &Brando.Pages.PageResolver.update/2
    end

    field :delete_menu, type: :menu do
      arg :menu_id, non_null(:id)

      resolve &Brando.Pages.PageResolver.delete/2
    end

    @desc "Duplicate menu"
    field :duplicate_menu, type: :menu do
      arg :menu_id, :id

      resolve &Brando.Pages.PageResolver.duplicate/2
    end

    @desc "Duplicate section"
    field :duplicate_section, type: :menu_fragment do
      arg :section_id, :id

      resolve &Brando.Pages.PageResolver.duplicate_section/2
    end
  end
end
