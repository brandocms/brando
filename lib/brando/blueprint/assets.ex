defmodule Brando.Blueprint.Assets do
  @moduledoc """
  WIP

  ## Asset types


  ### File

  #### Example

      assets do
        asset :pdf, :file, required: true, cfg: [
          allowed_mimetypes: ["application/pdf"],
          random_filename: false,
          upload_path: Path.join("files", "pdfs"),
          force_filename: "a_single_file.pdf",
          overwrite: true,
          size_limit: 16_000_000
        ]
      end
  """
  alias Ecto.Changeset
  alias Brando.Blueprint

  def build_asset(name, type, opts \\ [])

  def build_asset(name, :image, cfg: :db) do
    %Blueprint.Asset{
      name: name,
      type: :image,
      opts: %{module: Brando.Images.Image, opts: %{cfg: :db}}
    }
  end

  def build_asset(name, :image, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Images.Image})
    default_config = Brando.config(Brando.Images)[:default_config] || %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for image asset `#{inspect(name)}`

                assets do
                  asset #{inspect(name)}, :image, cfg: [...]
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

    %Blueprint.Asset{
      name: name,
      type: :image,
      opts: opts_map
    }
  end

  def build_asset(name, :file, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Files.File})
    default_config = %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for file asset `#{inspect(name)}`

                assets do
                  asset #{inspect(name)}, :file, cfg: [...]
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

    %Blueprint.Asset{
      name: name,
      type: :file,
      opts: opts_map
    }
  end

  def build_asset(name, :video, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Videos.Video})
    default_config = %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for video asset `#{inspect(name)}`

                assets do
                  asset #{inspect(name)}, :video, cfg: [...]
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

    %Blueprint.Asset{
      name: name,
      type: :video,
      opts: opts_map
    }
  end

  def build_asset(name, :gallery, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Images.Gallery})
    default_config = Brando.config(Brando.Images)[:default_config] || %{}

    cfg =
      case Map.get(opts_map, :cfg) do
        nil ->
          raise Brando.Exception.BlueprintError,
            message: """
            Missing :cfg key for gallery asset `#{inspect(name)}`

                assets do
                  asset #{inspect(name)}, :gallery, cfg: [...]
                end
            """

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

    %Blueprint.Asset{
      name: name,
      type: :gallery,
      opts: opts_map
    }
  end

  def build_asset(name, :gallery_images, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Images.GalleryImage})

    %Blueprint.Asset{
      name: name,
      type: :gallery_images,
      opts: opts_map
    }
  end

  def build_asset(name, type, opts) do
    %Blueprint.Asset{name: name, type: type, opts: Enum.into(opts, %{})}
  end

  defmacro assets(do: block) do
    assets(__CALLER__, block)
  end

  defp assets(_caller, block) do
    quote location: :keep do
      Module.put_attribute(__MODULE__, :brando_macro_context, :assets)
      Module.register_attribute(__MODULE__, :assets, accumulate: true)
      unquote(block)
    end
  end

  defmacro asset(name, type, opts \\ []) do
    asset(__CALLER__, name, type, opts)
  end

  defp asset(_caller, name, type, opts) do
    quote location: :keep do
      asset =
        build_asset(
          unquote(name),
          unquote(type),
          unquote(opts)
        )

      Module.put_attribute(__MODULE__, :assets, asset)
    end
  end

  def run_cast_assets(changeset, assets, user) do
    Enum.reduce(assets, changeset, fn rel, cs -> run_cast_asset(rel, cs, user) end)
  end

  ##
  ## image is belongs_to Image
  def run_cast_asset(%{type: :image, name: _name, opts: _opts}, changeset, _user) do
    changeset
  end

  ##
  ## file is belongs_to File
  def run_cast_asset(%{type: :file, name: _name, opts: _opts}, changeset, _user) do
    changeset
  end

  ##
  ## video is belongs_to Video
  def run_cast_asset(%{type: :video, name: _name, opts: _opts}, changeset, _user) do
    changeset
  end

  ##
  ## embeds_many
  def run_cast_asset(
        %{type: :embeds_many, name: name, opts: opts},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        Changeset.put_embed(changeset, name, [])

      _ ->
        Changeset.cast_embed(
          changeset,
          name,
          Blueprint.Utils.to_changeset_opts(:embeds_many, opts)
        )
    end
  end

  def run_cast_asset(
        %{type: :gallery, name: name, opts: opts},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        Changeset.put_assoc(changeset, name, nil)

      _ ->
        Changeset.cast_assoc(
          changeset,
          name,
          Blueprint.Utils.to_changeset_opts(:belongs_to, opts)
        )
    end
  end

  def run_cast_asset(
        %{type: :gallery_images, name: name, opts: opts},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      "" ->
        Changeset.put_assoc(changeset, name, nil)

      _ ->
        Changeset.cast_assoc(changeset, name, Blueprint.Utils.to_changeset_opts(:has_many, opts))
    end
  end

  ##
  ## catch all for non casted assets
  def run_cast_asset(asset, changeset, _user) do
    require Logger
    Logger.error("--> not casted: #{inspect(asset.name, pretty: true)}")
    changeset
  end
end
