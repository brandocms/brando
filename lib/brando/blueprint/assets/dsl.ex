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

  def transform(%{type: :image, opts: [cfg: :db]} = asset) do
    {:ok, %{asset | opts: %{cfg: :db}}}
  end

  def transform(%{type: :image} = asset) do
    opts_map = Map.merge(Enum.into(asset.opts, %{}), %{module: Brando.Images.Image})
    default_config = Brando.config(Brando.Images)[:default_config] || %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for image asset `#{inspect(asset.name)}`

                assets do
                  asset #{inspect(asset.name)}, :image, cfg: [...]
                end
            """

        :default ->
          default_config

        fun when is_function(fun) ->
          fun.()

        map when is_map(map) ->
          map = merge_asset_config(default_config, map)
          struct(Brando.Type.ImageConfig, map)

        kwlist when is_list(kwlist) ->
          kwlist = merge_asset_config(default_config, Enum.into(kwlist, %{}))
          struct(Brando.Type.ImageConfig, kwlist)
      end

    opts_map = Map.put(opts_map, :cfg, cfg)

    {:ok, %{asset | opts: opts_map}}
  end

  def transform(%{type: :video} = asset) do
    opts_map = Map.merge(Enum.into(asset.opts, %{}), %{module: Brando.Videos.Video})
    default_config = %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for video asset `#{inspect(asset.name)}`

                assets do
                  asset #{inspect(asset.name)}, :video, cfg: [...]
                end
            """

        :default ->
          default_config

        fun when is_function(fun) ->
          fun.()

        map when is_map(map) ->
          map = Brando.Utils.deep_merge(default_config, map)
          struct(Brando.Type.VideoConfig, map)

        kwlist when is_list(kwlist) ->
          kwlist = Brando.Utils.deep_merge(default_config, Enum.into(kwlist, %{}))
          struct(Brando.Type.VideoConfig, kwlist)
      end

    opts_map = Map.put(opts_map, :cfg, cfg)

    {:ok, %{asset | opts: opts_map}}
  end

  def transform(%{type: :file} = asset) do
    opts_map = Map.merge(Enum.into(asset.opts, %{}), %{module: Brando.Files.File})
    default_config = %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for file asset `#{inspect(asset.name)}`

                assets do
                  asset #{inspect(asset.name)}, :file, cfg: [...]
                end
            """

        :default ->
          default_config

        :config_target ->
          :config_target

        fun when is_function(fun) ->
          fun.()

        map when is_map(map) ->
          map = Brando.Utils.deep_merge(default_config, map)
          struct(Brando.Type.FileConfig, map)

        kwlist when is_list(kwlist) ->
          kwlist = Brando.Utils.deep_merge(default_config, Enum.into(kwlist, %{}))
          struct(Brando.Type.FileConfig, kwlist)
      end

    opts_map = Map.put(opts_map, :cfg, cfg)

    {:ok, %{asset | opts: opts_map}}
  end

  def transform(%{type: :gallery} = asset) do
    opts_map = Map.merge(Enum.into(asset.opts, %{}), %{module: Brando.Galleries.Gallery})
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

        fun when is_function(fun) ->
          normalize_gallery_config(fun.(), default_config)

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

  defp gallery_default_config do
    %{
      image:
        normalize_asset_config(
          Brando.Type.ImageConfig,
          Brando.config(Brando.Images)[:default_config] || Brando.Type.ImageConfig.default_config()
        ),
      video:
        normalize_asset_config(
          Brando.Type.VideoConfig,
          Brando.config(Brando.Videos)[:default_config] || Brando.Type.VideoConfig.default_config()
        )
    }
  end

  # A flat gallery cfg is the long-standing image-only syntax. Preserve it,
  # while allowing `%{image: ..., video: ...}` to configure both media types.
  defp normalize_gallery_config(%{image: image, video: video}, defaults) do
    %{
      image: merge_config(Brando.Type.ImageConfig, defaults.image, image),
      video: merge_config(Brando.Type.VideoConfig, defaults.video, video)
    }
  end

  defp normalize_gallery_config(%{image: image} = config, defaults) do
    %{
      image: merge_config(Brando.Type.ImageConfig, defaults.image, image),
      video: merge_config(Brando.Type.VideoConfig, defaults.video, Map.get(config, :video, %{}))
    }
  end

  defp normalize_gallery_config(%{video: video} = config, defaults) do
    image_overrides = Map.delete(config, :video)

    %{
      image: merge_config(Brando.Type.ImageConfig, defaults.image, image_overrides),
      video: merge_config(Brando.Type.VideoConfig, defaults.video, video)
    }
  end

  defp normalize_gallery_config(config, defaults) do
    %{defaults | image: merge_config(Brando.Type.ImageConfig, defaults.image, config)}
  end

  defp merge_config(module, default, overrides) do
    default_map = if is_struct(default), do: Map.from_struct(default), else: Map.new(default)
    override_map = if is_struct(overrides), do: Map.from_struct(overrides), else: Map.new(overrides)

    module
    |> struct(Brando.Utils.deep_merge(default_map, override_map))
  end

  defp normalize_asset_config(module, config) when is_struct(config, module), do: config
  defp normalize_asset_config(module, config), do: struct(module, config)

  # Deep merges default_config into override, but replaces :sizes wholly
  # if the override provides its own sizes rather than merging individual
  # size entries from the default config.
  defp merge_asset_config(default_config, override) do
    merged = Brando.Utils.deep_merge(default_config, override)

    if Map.has_key?(override, :sizes) do
      Map.put(merged, :sizes, override.sizes)
    else
      merged
    end
  end
end
