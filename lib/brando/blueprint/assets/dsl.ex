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
          map = Brando.Utils.deep_merge(default_config, map)
          struct(Brando.Type.ImageConfig, map)

        kwlist when is_list(kwlist) ->
          kwlist = Brando.Utils.deep_merge(default_config, Enum.into(kwlist, %{}))
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
    opts_map = Map.merge(Enum.into(asset.opts, %{}), %{module: Brando.Images.Gallery})
    default_config = Brando.config(Brando.Images)[:default_config] || %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for gallery asset `#{inspect(asset.name)}`

                assets do
                  asset #{inspect(asset.name)}, :gallery, cfg: [...]
                end
            """

        :default ->
          default_config

        fun when is_function(fun) ->
          fun.()

        map when is_map(map) ->
          map = Brando.Utils.deep_merge(default_config, map)
          struct(Brando.Type.ImageConfig, map)

        kwlist when is_list(kwlist) ->
          kwlist = Brando.Utils.deep_merge(default_config, Enum.into(kwlist, %{}))
          struct(Brando.Type.ImageConfig, kwlist)
      end

    opts_map = Map.put(opts_map, :cfg, cfg)

    {:ok, %{asset | opts: opts_map}}
  end

  def transform(asset) do
    {:ok, %{asset | opts: Enum.into(asset.opts, %{})}}
  end
end
