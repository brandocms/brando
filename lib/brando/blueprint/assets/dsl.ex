defmodule Brando.Blueprint.Assets.Dsl do
  alias Brando.Blueprint.{AssetConfigNormalizer, Assets}

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

  @image_schema Module.concat(["Brando", "Images", "Image"])
  @video_schema Module.concat(["Brando", "Videos", "Video"])
  @file_schema Module.concat(["Brando", "Files", "File"])
  @gallery_schema Module.concat(["Brando", "Galleries", "Gallery"])

  def transform(%{type: type} = asset) when type in @valid_assets do
    opts = Map.merge(Map.new(asset.opts), %{module: association_module(type)})
    config = Map.get(opts, :cfg)

    if is_nil(config) do
      raise_missing_config!(asset)
    end

    normalized_config =
      if is_function(config, 0) do
        config
      else
        AssetConfigNormalizer.normalize_declared_value!(type, asset.name, config)
      end

    {:ok, %{asset | opts: Map.put(opts, :cfg, normalized_config)}}
  end

  def transform(asset) do
    {:ok, %{asset | opts: Enum.into(asset.opts, %{})}}
  end

  @doc false
  def normalize_runtime_config(asset) do
    config_normalizer = Module.concat(["Brando", "Blueprint", "AssetConfigNormalizer"])
    config_normalizer.normalize(asset)
  end

  defp association_module(:image), do: @image_schema
  defp association_module(:video), do: @video_schema
  defp association_module(:file), do: @file_schema
  defp association_module(:gallery), do: @gallery_schema

  defp raise_missing_config!(asset) do
    raise Brando.Exception.BlueprintError,
      message: """
      Missing :cfg key for #{asset.type} asset `#{inspect(asset.name)}`

          assets do
            asset #{inspect(asset.name)}, #{inspect(asset.type)}, cfg: :default
          end
      """
  end
end
