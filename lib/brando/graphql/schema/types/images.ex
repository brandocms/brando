defmodule Brando.Schema.Types.Images do
  use Brando.Web, :absinthe

  input_object :create_image_series_params do
    field :name, :string
    field :credits, :string
    field :image_category_id, :string
  end

  input_object :create_image_category_params do
    field :name, :string
  end

  input_object :update_image_series_params do
    field :name, :string
    field :credits, :string
  end

  input_object :update_image_category_params do
    field :name, :string
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
      resolve assoc(:image_series, fn query, args, _ ->
        query
        |> order_by([is], [asc: fragment("lower(?)", is.name)])
        |> limit([is], ^args.limit)
        |> offset([is], ^args.offset)
      end)
    end
    field :inserted_at, :time
    field :updated_at, :time
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
    field :image_category, :image_category, resolve: assoc(:image_category)
    field :images, list_of(:image) do
      resolve assoc(:images, fn query, _, _ ->
        order_by(query, [i], [asc: i.sequence])
      end)
    end
    field :sequence, :integer
    field :inserted_at, :time
    field :updated_at, :time

    field :page_info, :page_info
  end

  object :image do
    field :id, :id
    field :image, :image_type
    field :creator, :user
    field :image_series_id, :id
    field :image_series, :image_series, resolve: assoc(:image_series)
    field :sequence, :integer
    field :inserted_at, :time
    field :updated_at, :time
  end

  object :image_type do
    field :title, :string
    field :credits, :string
    field :path, :string

    field :url, :string do
      arg :size, :string, default_value: "thumb"
      resolve fn image, args, _ ->
        case Enum.find(image.sizes, &(elem(&1, 0) == args.size)) do
          nil -> {:error, "URL size `#{args.size}` not found :("}
          {_, url} -> {:ok, Brando.Utils.media_url(url)}
        end
      end
    end
    field :sizes, list_of(:image_size) do
      resolve fn image, _args, _ ->
        map = Enum.map(image.sizes, &(%{key: elem(&1, 0), value: elem(&1, 1)}))
        {:ok, map}
      end
    end
    field :optimized, :boolean
    field :width, :integer
    field :height, :integer
  end

  object :image_config do
    field :allowed_mimetypes, list_of(:image_mimetype)
    field :default_size, :string
    field :upload_path, :string
    field :random_filename, :boolean
    field :size_limit, :integer
    field :sizes, list_of(:image_size)
    field :srcset, list_of(:image_srcset)
  end

  object :image_mimetype do
    field :name
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
    @desc "Create image category"
    field :create_image_category, type: :image_category do
      arg :image_category_params, :create_image_category_params

      resolve &Brando.Images.ImageCategoryResolver.create/2
    end

    @desc "Update image category"
    field :update_image_category, type: :image_category do
      arg :image_category_id, :id
      arg :image_category_params, :update_image_category_params

      resolve &Brando.Images.ImageCategoryResolver.update/2
    end

    @desc "Delete image category"
    field :delete_image_category, type: :image_category do
      arg :image_category_id, :id

      resolve &Brando.Images.ImageCategoryResolver.delete/2
    end

    @desc "Create image series"
    field :create_image_series, type: :image_series do
      arg :image_series_params, :create_image_series_params

      resolve &Brando.Images.ImageSeriesResolver.create/2
    end

    @desc "Update image series"
    field :update_image_series, type: :image_series do
      arg :image_series_id, :id
      arg :image_series_params, :update_image_series_params

      resolve &Brando.Images.ImageSeriesResolver.update/2
    end

    @desc "Delete image series"
    field :delete_image_series, type: :image_series do
      arg :image_series_id, :id

      resolve &Brando.Images.ImageSeriesResolver.delete/2
    end
  end
end
