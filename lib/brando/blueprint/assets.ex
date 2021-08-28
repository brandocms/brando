defmodule Brando.Blueprint.Assets do
  @moduledoc """
  WIP
  """
  import Ecto.Changeset
  import Brando.Blueprint.Utils
  alias Brando.Blueprint.Asset

  def build_asset(name, type, opts \\ [])

  def build_asset(name, :image, cfg: :db) do
    %Asset{
      name: name,
      type: :image,
      opts: %{module: Brando.Images.Image, opts: %{db: true}}
    }
  end

  def build_asset(name, :image, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Images.Image})
    cfg = Map.get(opts_map, :cfg)

    if !cfg do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing :cfg key for image asset `#{inspect(name)}`

            assets do
              asset #{inspect(name)}, :image, cfg: [...]
            end
        """
    end

    cfg_struct = struct(Brando.Type.ImageConfig, cfg)

    opts_map = Map.put(opts_map, :cfg, cfg_struct)

    %Asset{
      name: name,
      type: :image,
      opts: opts_map
    }
  end

  def build_asset(name, :file, opts) do
    %Asset{
      name: name,
      type: :file,
      opts: Map.merge(Enum.into(opts, %{}), %{module: Brando.Files.File})
    }
  end

  def build_asset(name, :video, opts) do
    %Asset{
      name: name,
      type: :video,
      opts: Map.merge(Enum.into(opts, %{}), %{module: Brando.Videos.Video})
    }
  end

  def build_asset(name, :gallery, opts) do
    opts_map = Map.merge(Enum.into(opts, %{}), %{module: Brando.Images.Image})
    cfg = Map.get(opts_map, :cfg)

    if !cfg do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing :cfg key for gallery asset `#{inspect(name)}`

            assets do
              asset #{inspect(name)}, :gallery, cfg: [...]
            end
        """
    end

    cfg_struct = struct(Brando.Type.ImageConfig, cfg)

    opts_map = Map.put(opts_map, :cfg, cfg_struct)

    %Asset{
      name: name,
      type: :gallery,
      opts: opts_map
    }
  end

  def build_asset(name, type, opts) do
    %Asset{name: name, type: type, opts: Enum.into(opts, %{})}
  end

  defmacro assets(do: block) do
    assets(__CALLER__, block)
  end

  defp assets(_caller, block) do
    quote location: :keep do
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
  ## embeds_one
  def run_cast_asset(
        %{type: type, name: name, opts: opts},
        changeset,
        _user
      )
      when type in [:image, :file, :video] do
    # A hack to remove an embeds_one, specifically an image
    case Map.get(changeset.params, to_string(name)) do
      "" -> put_embed(changeset, name, nil)
      _ -> cast_embed(changeset, name, to_changeset_opts(:embeds_one, opts))
    end
  end

  ##
  ## embeds_many
  def run_cast_asset(
        %{type: :embeds_many, name: name, opts: opts},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      "" -> put_embed(changeset, name, [])
      _ -> cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
    end
  end

  def run_cast_asset(
        %{type: :gallery, name: name, opts: opts},
        changeset,
        _user
      ) do
    case Map.get(changeset.params, to_string(name)) do
      nil -> changeset
      "" -> put_embed(changeset, name, [])
      _ -> cast_embed(changeset, name, to_changeset_opts(:embeds_many, opts))
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
