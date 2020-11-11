defmodule Brando.Schema.Types.Identity do
  @moduledoc """
  GraphQL type spec, mutations and queries for Identity
  """
  use Brando.Web, :absinthe

  object :identity do
    field :id, :id
    field :type, :string
    field :name, :string
    field :alternate_name, :string
    field :email, :string
    field :phone, :string
    field :address, :string
    field :address2, :string
    field :address3, :string
    field :zipcode, :string
    field :city, :string
    field :country, :string
    field :description, :string
    field :title_prefix, :string
    field :title, :string
    field :title_postfix, :string
    field :image, :image_type
    field :logo, :image_type
    field :url, :string
    field :configs, list_of(:config)
    field :links, list_of(:link)
    field :metas, list_of(:meta)
    field :inserted_at, :time
    field :updated_at, :time

    field :default_language, :string do
      resolve fn _, _ ->
        {:ok, Brando.config(:default_language)}
      end
    end

    field :languages, list_of(:language) do
      resolve fn _, _ ->
        languages =
          Enum.map(Brando.config(:languages), fn [value: id, text: name] ->
            %{id: id, name: name}
          end)

        {:ok, languages}
      end
    end

    field :default_admin_language, :string do
      resolve fn _, _ ->
        {:ok, Brando.config(:default_admin_language)}
      end
    end

    field :admin_languages, list_of(:language) do
      resolve fn _, _ ->
        languages =
          Enum.map(Brando.config(:admin_languages), fn [value: id, text: name] ->
            %{id: id, name: name}
          end)

        {:ok, languages}
      end
    end
  end

  object :language do
    field :id, :string
    field :name, :string
  end

  object :link do
    field :id, :id
    field :name, :string
    field :url, :string
  end

  object :meta do
    field :id, :id
    field :key, :string
    field :value, :string
  end

  object :global do
    field :id, :id
    field :label, :string
    field :type, :string
    field :key, :string
    field :data, :json
    field :global_category_id, :id
    field :global_category, :global_category
  end

  object :global_category do
    field :id, :id
    field :label, :string
    field :key, :string
    field :globals, list_of(:global), resolve: dataloader(Brando.Sites)
  end

  object :config do
    field :id, :id
    field :key, :string
    field :value, :string
  end

  object :logged_warning do
    field :msg, :string
  end

  input_object :identity_params do
    field :type, :string
    field :name, :string
    field :alternate_name, :string
    field :email, :string
    field :phone, :string
    field :address, :string
    field :address2, :string
    field :address3, :string
    field :zipcode, :string
    field :city, :string
    field :country, :string
    field :description, :string
    field :title_prefix, :string
    field :title, :string
    field :title_postfix, :string
    field :links, list_of(:link_params)
    field :metas, list_of(:meta_params)
    field :configs, list_of(:config_params)
    field :image, :upload_or_image
    field :logo, :upload_or_image
    field :url, :string
  end

  input_object :global_category_params do
    field :id, :id
    field :label, :string
    field :key, :string
    field :globals, list_of(:global_params)
  end

  input_object :link_params do
    field :id, :id
    field :name, :string
    field :url, :string
  end

  input_object :meta_params do
    field :id, :id
    field :key, :string
    field :value, :string
  end

  input_object :global_params do
    field :id, :id
    field :type, :string
    field :label, :string
    field :key, :string
    field :data, :json
  end

  input_object :config_params do
    field :id, :id
    field :key, :string
    field :value, :string
  end

  object :identity_queries do
    @desc "Get identity"
    field :identity, type: :identity do
      resolve &Brando.Sites.IdentityResolver.get/2
    end

    @desc "Get warnings"
    field :logged_warnings, type: list_of(:logged_warning) do
      resolve &Brando.Sites.LoggedWarningResolver.all/2
    end
  end

  object :identity_mutations do
    field :create_identity, type: :identity do
      arg :identity_params, non_null(:identity_params)
      resolve &Brando.Sites.IdentityResolver.create/2
    end

    field :update_identity, type: :identity do
      arg :identity_params, :identity_params
      resolve &Brando.Sites.IdentityResolver.update/2
    end
  end

  object :global_queries do
    @desc "Get global categories"
    field :global_categories, type: list_of(:global_category) do
      resolve &Brando.Sites.GlobalResolver.all/2
    end
  end

  object :global_mutations do
    field :create_global_category, type: :global_category do
      arg :global_category_params, non_null(:global_category_params)
      resolve &Brando.Sites.GlobalResolver.create/2
    end

    field :update_global_category, type: :global_category do
      arg :category_id, non_null(:id)
      arg :global_category_params, non_null(:global_category_params)
      resolve &Brando.Sites.GlobalResolver.update/2
    end
  end
end
