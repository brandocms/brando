defmodule Brando.Blueprint.Assets.Dsl do
  alias Brando.Blueprint.Assets

  @valid_assets [
    :image,
    :video,
    :file,
    :gallery
  ]

  @asset %Spark.Dsl.Entity{
    name: :asset,
    identifier: :name,
    describe: """
    Declares a asset
    """,
    examples: [
      """
      asset :cover, :image, required: true, cfg: %{}
      """
    ],
    args: [:name, :type, {:optional, :opts}],
    target: Assets.Asset,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Asset name"
      ],
      type: [
        type: {:in, @valid_assets},
        required: true,
        doc: "Asset type"
      ],
      opts: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Asset options"
      ]
    ],
    transform: {__MODULE__, :transform, []}
  }

  @root %Spark.Dsl.Section{
    name: :assets,
    entities: [@asset],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: [Brando.Blueprint.Assets.Transformer]

  alias Brando.RuntimeConfig

  @image_schema Module.concat(["Brando", "Images", "Image"])
  @video_schema Module.concat(["Brando", "Videos", "Video"])
  @file_schema Module.concat(["Brando", "Files", "File"])
  @gallery_schema Module.concat(["Brando", "Galleries", "Gallery"])
  @image_config Module.concat(["Brando", "Type", "ImageConfig"])
  @video_config Module.concat(["Brando", "Type", "VideoConfig"])
  @file_config Module.concat(["Brando", "Type", "FileConfig"])
  @image_context Module.concat(["Brando", "Images"])
  @video_context Module.concat(["Brando", "Videos"])
  @file_context Module.concat(["Brando", "Files"])

  def transform(%{type: :image} = asset) do
    transform_asset(asset, @image_schema, @image_config, [:db])
  end

  def transform(%{type: :video} = asset) do
    transform_asset(asset, @video_schema, @video_config, [])
  end

  def transform(%{type: :file} = asset) do
    transform_asset(asset, @file_schema, @file_config, [:config_target])
  end

  def transform(%{type: :gallery} = asset) do
    opts_map = Map.merge(Enum.into(asset.opts, %{}), %{module: @gallery_schema})
    default_config = gallery_default_config()

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for gallery asset `#{inspect(asset.name)}`

                assets do
                  asset #{inspect(asset.name)}, :gallery, cfg: %{...}
                end
            """

        :default ->
          default_config

        fun when is_function(fun, 0) ->
          fun

        map when is_map(map) ->
          normalize_gallery_config(map, default_config)

        kwlist when is_list(kwlist) ->
          normalize_gallery_config(Enum.into(kwlist, %{}), default_config)
      end

    opts_map = Map.put(opts_map, :cfg, cfg)

    {:ok, %{asset | opts: opts_map}}
  end

  def transform(asset) do
    {:ok, %{asset | opts: Enum.into(asset.opts, %{})}}
  end

  @doc false
  def normalize_runtime_config(asset) do
    config_normalizer = Module.concat(["Brando", "Blueprint", "AssetConfigNormalizer"])
    config_normalizer.normalize(asset)
  end

  defp transform_asset(asset, association_module, config_module, passthrough_values) do
    opts = Map.merge(Map.new(asset.opts), %{module: association_module})
    config = Map.get(opts, :cfg)

    if is_nil(config) do
      raise_missing_config!(asset)
    end

    normalized_config = normalize_config(asset, config_module, config, passthrough_values)
    {:ok, %{asset | opts: Map.put(opts, :cfg, normalized_config)}}
  end

  defp normalize_config(asset, config_module, config, passthrough_values) do
    cond do
      config in passthrough_values ->
        config

      config == :default ->
        default_asset_config(asset.type, config_module)

      is_function(config, 0) ->
        config

      is_struct(config, config_module) ->
        config

      is_map(config) or (is_list(config) and Keyword.keyword?(config)) ->
        merge_asset_type_config(asset.type, config_module, config)

      true ->
        raise Brando.Exception.BlueprintError,
          message:
            "Invalid :cfg for #{asset.type} asset #{inspect(asset.name)}: expected :default, a map, a keyword list, or a zero-arity function"
    end
  end

  defp merge_asset_type_config(type, config_module, overrides) do
    default = default_asset_config(type, config_module)
    default_map = Map.from_struct(default)
    overrides_map = if is_struct(overrides), do: Map.from_struct(overrides), else: Map.new(overrides)

    merged =
      if type == :image do
        merge_asset_config(default_map, overrides_map)
      else
        deep_merge(default_map, overrides_map)
      end

    struct(config_module, merged)
  end

  defp default_asset_config(type, config_module) do
    configured =
      case RuntimeConfig.get(asset_context(type)) do
        nil -> nil
        config when is_list(config) -> Keyword.get(config, :default_config)
        config when is_map(config) -> Map.get(config, :default_config)
      end

    normalize_asset_config(config_module, configured || config_module.default_config())
  end

  defp asset_context(:image), do: @image_context
  defp asset_context(:video), do: @video_context
  defp asset_context(:file), do: @file_context

  defp raise_missing_config!(asset) do
    raise Brando.Exception.BlueprintError,
      message: """
      Missing :cfg key for #{asset.type} asset `#{inspect(asset.name)}`

          assets do
            asset #{inspect(asset.name)}, #{inspect(asset.type)}, cfg: :default
          end
      """
  end

  defp gallery_default_config do
    %{
      image: default_asset_config(:image, @image_config),
      video: default_asset_config(:video, @video_config)
    }
  end

  # A flat gallery cfg is the long-standing image-only syntax. Preserve it,
  # while allowing `%{image: ..., video: ...}` to configure both media types.
  defp normalize_gallery_config(%{image: image, video: video}, defaults) do
    %{
      image: merge_config(@image_config, defaults.image, image),
      video: merge_config(@video_config, defaults.video, video)
    }
  end

  defp normalize_gallery_config(%{image: image} = config, defaults) do
    %{
      image: merge_config(@image_config, defaults.image, image),
      video: merge_config(@video_config, defaults.video, Map.get(config, :video, %{}))
    }
  end

  defp normalize_gallery_config(%{video: video} = config, defaults) do
    image_overrides = Map.delete(config, :video)

    %{
      image: merge_config(@image_config, defaults.image, image_overrides),
      video: merge_config(@video_config, defaults.video, video)
    }
  end

  defp normalize_gallery_config(config, defaults) do
    %{defaults | image: merge_config(@image_config, defaults.image, config)}
  end

  defp merge_config(module, default, overrides) do
    default_map = if is_struct(default), do: Map.from_struct(default), else: Map.new(default)
    override_map = if is_struct(overrides), do: Map.from_struct(overrides), else: Map.new(overrides)

    module
    |> struct(deep_merge(default_map, override_map))
  end

  defp normalize_asset_config(module, config) when is_struct(config, module), do: config
  defp normalize_asset_config(module, config), do: struct(module, config)

  # Deep merges default_config into override, but replaces :sizes wholly
  # if the override provides its own sizes rather than merging individual
  # size entries from the default config.
  defp merge_asset_config(default_config, override) do
    merged = deep_merge(default_config, override)

    if Map.has_key?(override, :sizes) do
      Map.put(merged, :sizes, override.sizes)
    else
      merged
    end
  end

  defp deep_merge(nil, right), do: right
  defp deep_merge(left, nil), do: left

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = left_value, %{} = right_value -> deep_merge(left_value, right_value)
      _key, _left_value, right_value -> right_value
    end)
  end
end
