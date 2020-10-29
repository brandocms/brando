defmodule Brando.Schema.Types.SEO do
  @moduledoc """
  GraphQL type spec, mutations and queries for Identity
  """
  use Brando.Web, :absinthe

  object :seo do
    field :id, :id
    field :fallback_meta_description, :string
    field :fallback_meta_title, :string
    field :fallback_meta_image, :image_type
    field :base_url, :string
    field :robots, :string
    field :redirects, list_of(:redirect)
    field :inserted_at, :time
    field :updated_at, :time
  end

  object :redirect do
    field :id, :id
    field :from, :string
    field :to, :string
    field :code, :string
  end

  input_object :seo_params do
    field :fallback_meta_description, :string
    field :fallback_meta_title, :string
    field :fallback_meta_image, :upload_or_image
    field :base_url, :string
    field :robots, :string
    field :redirects, list_of(:redirect_params)
  end

  input_object :redirect_params do
    field :id, :id
    field :from, :string
    field :to, :string
    field :code, :string
  end

  object :seo_queries do
    @desc "Get seo"
    field :seo, type: :seo do
      resolve &Brando.Sites.SEOResolver.get/2
    end
  end

  object :seo_mutations do
    field :create_seo, type: :seo do
      arg :seo_params, non_null(:seo_params)
      resolve &Brando.Sites.SEOResolver.create/2
    end

    field :update_seo, type: :seo do
      arg :seo_params, :seo_params
      resolve &Brando.Sites.SEOResolver.update/2
    end
  end
end
