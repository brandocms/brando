defmodule Brando.GraphQL.Schema.Types.Navigation do
  use Brando.Web, :absinthe

  object :menu do
    field :id, :id
    field :key, :string
    field :language, :string
    field :title, :string
    field :status, :string
    field :template, :string
    field :creator, :user, resolve: dataloader(Brando.Navigation)
    field :items, list_of(:menu_item)
    field :inserted_at, :time
    field :updated_at, :time
  end

  input_object :menu_params do
    field :key, :string
    field :language, :string
    field :title, :string
    field :status, :string
    field :template, :string
    field :items, list_of(:menu_item_params)
  end

  object :menu_item do
    field :id, :id
    field :key, :string
    field :title, :string
    field :status, :string
    field :url, :string
    field :open_in_new_window, :boolean
    field :items, list_of(:menu_item)
  end

  input_object :menu_item_params do
    field :id, :string
    field :key, :string
    field :title, :string
    field :status, :string
    field :url, :string
    field :items, list_of(:menu_item_params)
    field :open_in_new_window, :boolean
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
      resolve &Brando.Navigation.NavigationResolver.all_menus/2
    end

    @desc "Get menu"
    field :menu, type: :menu do
      arg :menu_id, non_null(:id)
      resolve &Brando.Navigation.NavigationResolver.find_menu/2
    end
  end

  object :navigation_mutations do
    field :create_menu, type: :menu do
      arg :menu_params, :menu_params

      resolve &Brando.Navigation.NavigationResolver.create_menu/2
    end

    field :update_menu, type: :menu do
      arg :menu_id, non_null(:id)
      arg :menu_params, :menu_params

      resolve &Brando.Navigation.NavigationResolver.update_menu/2
    end

    field :delete_menu, type: :menu do
      arg :menu_id, non_null(:id)

      resolve &Brando.Navigation.NavigationResolver.delete_menu/2
    end

    @desc "Duplicate menu"
    field :duplicate_menu, type: :menu do
      arg :menu_id, :id

      resolve &Brando.Navigation.NavigationResolver.duplicate_menu/2
    end
  end
end
