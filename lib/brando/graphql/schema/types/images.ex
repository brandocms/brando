defmodule Brando.Schema.Types.Images do
  use Brando.Web, :absinthe

  input_object :image_series_params do
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :cfg, :string
    field :image_category_id, :string
  end

  input_object :image_series_upload do
    field :id, :id
    field :name, :string
    field :slug, :string
    field :image_category_id, :id
    field :images, list_of(non_null(:image_upload))
  end

  input_object :image_upload do
    field :image, :upload
    field :sequence, :integer
  end

  input_object :image_category_params do
    field :name, :string
    field :slug, :string
    field :cfg, :string
  end

  input_object :image_config_params do
    field :allowed_mimetypes, list_of(:string)
    field :default_size, :string
    field :upload_path, :string
    field :random_filename, :boolean
    field :size_limit, :integer
    field :sizes, :json
    field :srcset, list_of(:image_srcset_params)
  end

  input_object :image_meta_params do
    field :title, :string
    field :credits, :string
    field :alt, :string
    field :focal, :focal_params
  end

  input_object :image_type_params do
    field :title, :string
    field :credits, :string
    field :alt, :string
    field :path, :string
    field :focal, :json
  end

  input_object :focal_params do
    field :x, :integer
    field :y, :integer
  end

  input_object :image_srcset_params do
    field :key, :string
    field :value, :string
  end

  object :image_category do
    field :id, :id
    field :name, :string
    field :slug, :string
    field :cfg, :image_config
    field :creator, :user

    field :image_series_count, :integer do
      resolve fn cat, _, _ ->
        {:ok, Brando.Images.image_series_count(cat.id)}
      end
    end

    field :image_series, list_of(:image_series) do
      arg :limit, :integer, default_value: 10
      arg :offset, :integer, default_value: 0
      resolve dataloader(Brando.Images, :image_series)
    end

    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  object :page_info do
    field :has_next_page, :boolean
  end

  object :image_series do
    field :id, :id
    field :name, :string
    field :slug, :string
    field :credits, :string
    field :cfg, :image_config
    field :creator, :user
    field :image_category_id, :id
    field :image_category, :image_category, resolve: dataloader(Brando.Images)
    field :images, list_of(:image), resolve: dataloader(Brando.Images)
    field :sequence, :integer
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time

    field :page_info, :page_info
  end

  object :image do
    field :id, :id
    field :image, :image_type
    field :creator, :user
    field :image_series_id, :id
    field :image_series, :image_series, resolve: dataloader(Brando.Images)
    field :sequence, :integer
    field :inserted_at, :time
    field :updated_at, :time
    field :deleted_at, :time
  end

  object :image_type do
    field :title, :string
    field :credits, :string
    field :alt, :string
    field :path, :string
    field :focal, :json

    field :url, :string do
      arg :size, :string, default_value: "thumb"

      resolve fn image, args, _ ->
        case Enum.find(image.sizes, &(elem(&1, 0) == args.size)) do
          nil ->
            (args.size == "original" &&
               {:ok, Brando.Utils.media_url(image.path)}) ||
              {:ok, ""}

          {_, url} ->
            {:ok, Brando.Utils.media_url(url)}
        end
      end
    end

    field :sizes, :json do
      resolve fn image, _, _ ->
        sizes = for {k, v} <- image.sizes, into: %{}, do: {k, Brando.Utils.media_url(v)}
        {:ok, sizes}
      end
    end

    field :width, :integer
    field :height, :integer
  end

  object :image_config do
    field :allowed_mimetypes, list_of(:string)
    field :default_size, :string
    field :upload_path, :string
    field :random_filename, :boolean
    field :size_limit, :integer
    field :sizes, :json
    field :srcset, list_of(:image_srcset)
  end

  object :image_mimetype do
    field :name, :string
  end

  object :image_size do
    field :key, :string
    field :value, :string
  end

  object :image_srcset do
    field :key, :string
    field :value, :string
  end

  object :image_queries do
    @desc "Get image categories"
    field :image_categories, type: list_of(:image_category) do
      resolve &Brando.Images.ImageCategoryResolver.all/2
    end

    @desc "Get image category"
    field :image_category, type: :image_category do
      arg :category_id, non_null(:id)
      resolve &Brando.Images.ImageCategoryResolver.find/2
    end

    @desc "Get image series"
    field :image_series, type: :image_series do
      arg :series_id, non_null(:id)
      resolve &Brando.Images.ImageSeriesResolver.find/2
    end
  end

  object :image_mutations do
    @desc "Upload images to image series"
    field :create_image, type: :image do
      arg :image_series_id, :id
      arg :image_upload_params, :image_upload

      resolve &Brando.Images.ImageResolver.create/2
    end

    @desc "Edit image data"
    field :update_image_meta, type: :image do
      arg :image_id, :id
      arg :image_meta_params, :image_meta_params

      resolve &Brando.Images.ImageResolver.update_meta/2
    end

    @desc "Delete multiple images"
    field :delete_images, type: :integer do
      arg :image_ids, list_of(:id)

      resolve &Brando.Images.ImageResolver.delete_images/2
    end

    @desc "Create image category"
    field :create_image_category, type: :image_category do
      arg :image_category_params, :image_category_params

      resolve &Brando.Images.ImageCategoryResolver.create/2
    end

    @desc "Update image category"
    field :update_image_category, type: :image_category do
      arg :image_category_id, :id
      arg :image_category_params, :image_category_params

      resolve &Brando.Images.ImageCategoryResolver.update/2
    end

    @desc "Delete image category"
    field :delete_image_category, type: :image_category do
      arg :image_category_id, :id

      resolve &Brando.Images.ImageCategoryResolver.delete/2
    end

    @desc "Duplicate image category"
    field :duplicate_image_category, type: :image_category do
      arg :image_category_id, :id

      resolve &Brando.Images.ImageCategoryResolver.duplicate/2
    end

    @desc "Create image series"
    field :create_image_series, type: :image_series do
      arg :image_series_params, :image_series_params

      resolve &Brando.Images.ImageSeriesResolver.create/2
    end

    @desc "Update image series"
    field :update_image_series, type: :image_series do
      arg :image_series_id, :id
      arg :image_series_params, :image_series_params

      resolve &Brando.Images.ImageSeriesResolver.update/2
    end

    @desc "Delete image series"
    field :delete_image_series, type: :image_series do
      arg :image_series_id, :id

      resolve &Brando.Images.ImageSeriesResolver.delete/2
    end
  end
end
