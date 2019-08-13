defmodule Brando.Schema.Types.Organization do
  @moduledoc """
  GraphQL type spec, mutations and queries for Organization
  """
  use Brando.Web, :absinthe

  object :organization do
    field :id, :id
    field :name, :string
    field :alternate_name, :string
    field :email, :string
    field :phone, :string
    field :address, :string
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
    field :links, list_of(:link), resolve: assoc(:links)
    field :inserted_at, :time
    field :updated_at, :time
  end

  input_object :organization_params do
    field :name, :string
    field :alternate_name, :string
    field :email, :string
    field :phone, :string
    field :address, :string
    field :zipcode, :string
    field :city, :string
    field :country, :string
    field :description, :string
    field :title_prefix, :string
    field :title, :string
    field :title_postfix, :string
    field :links, list_of(:link)
    field :image, :upload_or_image
    field :logo, :upload_or_image
    field :url, :string
  end

  object :organization_queries do
    @desc "Get organization"
    field :organization, type: :organization do
      resolve &Brando.Sites.OrganizationResolver.get/2
    end
  end

  object :organization_mutations do
    field :create_organization, type: :organization do
      arg :organization_params, non_null(:organization_params)
      resolve &Brando.Sites.OrganizationResolver.create/2
    end

    field :update_organization, type: :organization do
      arg :organization_params, :organization_params
      resolve &Brando.Sites.OrganizationResolver.update/2
    end

    field :delete_organization, type: :organization do
      resolve &Brando.Sites.OrganizationResolver.delete/2
    end
  end
end
