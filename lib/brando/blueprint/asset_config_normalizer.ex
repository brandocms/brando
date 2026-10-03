defmodule Brando.Blueprint.AssetConfigNormalizer do
  @moduledoc """
  Materializes deferred Blueprint asset configuration at runtime.

  Asset DSL compilation may retain a zero-arity configuration function. This
  module evaluates and normalizes it without making runtime Blueprint metadata
  reads depend on the compile-time Spark DSL extension.
  """

  alias Brando.Blueprint.AssetConfigValidator
  alias Brando.Images.Size
  alias Brando.RuntimeConfig

  @image_config Module.concat(["Brando", "Type", "ImageConfig"])
  @video_config Module.concat(["Brando", "Type", "VideoConfig"])
  @file_config Module.concat(["Brando", "Type", "FileConfig"])
  @image_context Module.concat(["Brando", "Images"])
  @video_context Module.concat(["Brando", "Videos"])
  @file_context Module.concat(["Brando", "Files"])

  @type asset_type :: :file | :gallery | :image | :video

  @doc """
  Evaluates and normalizes a deferred asset config, leaving materialized assets unchanged.
  """
  @spec normalize(struct()) :: struct()
  def normalize(%{opts: %{cfg: config}} = asset) when is_function(config, 0) do
    normalized = normalize_declared_value!(asset.type, asset.name, config.())
    %{asset | opts: Map.put(asset.opts, :cfg, inherit_video_strategy(asset.type, normalized))}
  end

  def normalize(%{type: type, opts: %{cfg: config}} = asset) when type in [:video, :gallery] do
    %{asset | opts: Map.put(asset.opts, :cfg, inherit_video_strategy(type, config))}
  end

  def normalize(asset), do: asset

  @doc """
  Normalizes a value declared by a Blueprint asset.

  Declaration-only sentinels such as `:db` and `:config_target` remain valid
  for their supported asset types.
  """
  @spec normalize_declared_value!(asset_type(), atom() | String.t(), term()) :: term()
  def normalize_declared_value!(type, name, config) do
    normalize_value!(type, name, config, declared_passthrough(type))
  end

  @doc """
  Normalizes a materialized config-target value.

  Config-target functions must resolve to a usable typed config; Blueprint
  declaration sentinels are rejected at this boundary.
  """
  @spec normalize_resolved_value!(asset_type(), atom() | String.t(), term()) :: struct() | map()
  def normalize_resolved_value!(type, name, config) do
    inherit_video_strategy(type, normalize_value!(type, name, config, []))
  end

  # A video config without its own `upload_strategy` follows the site's
  # `default_video_upload_strategy`. Resolved here, on every runtime read,
  # because a Blueprint's literal config is normalized at compile time, before
  # the site's runtime configuration can be trusted.
  defp inherit_video_strategy(:video, %{upload_strategy: nil} = config),
    do: %{config | upload_strategy: RuntimeConfig.default_video_upload_strategy()}

  defp inherit_video_strategy(:gallery, %{video: video} = config),
    do: %{config | video: inherit_video_strategy(:video, video)}

  defp inherit_video_strategy(_type, config), do: config

  defp normalize_value!(type, name, config, passthrough_values) when type in [:file, :image, :video] do
    asset = %{name: name, type: type}

    normalized =
      asset
      |> normalize_config(config_module(type), config, passthrough_values)
      |> normalize_image_sizes(asset)

    AssetConfigValidator.validate!(asset, normalized)
  end

  defp normalize_value!(:gallery, name, config, _passthrough_values) do
    asset = %{name: name, type: :gallery}
    defaults = gallery_default_config()

    normalized =
      cond do
        config == :default -> defaults
        is_struct(config, @image_config) -> normalize_gallery_config(asset, Map.from_struct(config), defaults)
        is_map(config) and not is_struct(config) -> normalize_gallery_config(asset, config, defaults)
        is_list(config) and Keyword.keyword?(config) -> normalize_gallery_config(asset, Map.new(config), defaults)
        true -> invalid_config!(asset, "expected :default, an image config struct, a map, or a keyword list")
      end

    AssetConfigValidator.validate!(asset, %{normalized | image: normalize_image_sizes(normalized.image, asset)})
  end

  defp declared_passthrough(:image), do: [:db]
  defp declared_passthrough(:file), do: [:config_target]
  defp declared_passthrough(_type), do: []

  defp config_module(:image), do: @image_config
  defp config_module(:video), do: @video_config
  defp config_module(:file), do: @file_config

  defp normalize_config(asset, config_module, config, passthrough_values) do
    cond do
      config in passthrough_values ->
        config

      config == :default ->
        default_asset_config(asset.type, config_module)

      is_struct(config, config_module) ->
        config

      is_map(config) and not is_struct(config) ->
        merge_asset_type_config(asset, config_module, config)

      is_list(config) and Keyword.keyword?(config) ->
        merge_asset_type_config(asset, config_module, config)

      true ->
        invalid_config!(asset, "expected :default, a matching config struct, a map, or a keyword list")
    end
  end

  defp merge_asset_type_config(%{type: type} = asset, config_module, overrides) do
    default = default_asset_config(type, config_module)
    default_map = Map.from_struct(default)
    overrides_map = Map.new(overrides)

    merged =
      if type == :image do
        merge_image_config(default_map, overrides_map)
      else
        deep_merge(default_map, overrides_map)
      end

    build_struct!(asset, type, config_module, merged)
  end

  defp default_asset_config(type, config_module) do
    configured =
      case RuntimeConfig.get(asset_context(type)) do
        nil -> nil
        config when is_list(config) -> Keyword.get(config, :default_config)
        config when is_map(config) -> Map.get(config, :default_config)
      end

    default_config = configured || config_module.default_config()
    default_asset = %{name: :default, type: type}

    default_asset
    |> normalize_asset_config(config_module, default_config)
    |> normalize_image_sizes(default_asset)
  end

  # Resolves a size preset and checks each size, leaving them as the
  # string-keyed maps processing reads. Done before a gallery merges its sizes
  # over the defaults, so a preset there behaves like the map it stands for.
  defp normalize_image_sizes(config, asset) do
    if is_struct(config, @image_config) do
      case Size.normalize_sizes(config.sizes) do
        {:ok, sizes} -> %{config | sizes: sizes}
        {:error, message} -> invalid_config!(asset, message)
      end
    else
      config
    end
  end

  defp asset_context(:image), do: @image_context
  defp asset_context(:video), do: @video_context
  defp asset_context(:file), do: @file_context

  defp gallery_default_config do
    %{
      image: default_asset_config(:image, @image_config),
      video: default_asset_config(:video, @video_config)
    }
  end

  defp normalize_gallery_config(asset, %{image: image, video: video} = config, defaults) do
    ensure_gallery_keys!(asset, config)

    %{
      image: merge_config(asset, :image, @image_config, defaults.image, image),
      video: merge_config(asset, :video, @video_config, defaults.video, video)
    }
  end

  # No `:video` key here — the clause above matched every config that has one,
  # so the lookup this used to do could only ever return its default.
  defp normalize_gallery_config(asset, %{image: image} = config, defaults) do
    ensure_gallery_keys!(asset, config)

    %{
      image: merge_config(asset, :image, @image_config, defaults.image, image),
      video: merge_config(asset, :video, @video_config, defaults.video, %{})
    }
  end

  defp normalize_gallery_config(asset, %{video: video} = config, defaults) do
    %{
      image: merge_config(asset, :image, @image_config, defaults.image, Map.delete(config, :video)),
      video: merge_config(asset, :video, @video_config, defaults.video, video)
    }
  end

  defp normalize_gallery_config(asset, config, defaults) do
    %{defaults | image: merge_config(asset, :image, @image_config, defaults.image, config)}
  end

  defp merge_config(asset, type, module, default, overrides) do
    default_map = if is_struct(default), do: Map.from_struct(default), else: Map.new(default)
    override_map = config_map!(asset, type, module, overrides)
    build_struct!(asset, type, module, deep_merge(default_map, override_map))
  end

  defp normalize_asset_config(_asset, module, config) when is_struct(config, module), do: config

  defp normalize_asset_config(asset, module, config) when is_map(config) and not is_struct(config) do
    build_struct!(asset, asset.type, module, config)
  end

  defp normalize_asset_config(asset, module, config) when is_list(config) do
    if Keyword.keyword?(config) do
      build_struct!(asset, asset.type, module, Map.new(config))
    else
      invalid_config!(asset, "configured default must be a map, keyword list, or matching config struct")
    end
  end

  defp normalize_asset_config(asset, _module, _config) do
    invalid_config!(asset, "configured default must be a map, keyword list, or matching config struct")
  end

  defp config_map!(_asset, _type, module, config) when is_struct(config, module), do: Map.from_struct(config)
  defp config_map!(_asset, _type, _module, config) when is_map(config) and not is_struct(config), do: config

  defp config_map!(asset, type, _module, config) when is_list(config) do
    if Keyword.keyword?(config) do
      Map.new(config)
    else
      invalid_config!(asset, "#{type} gallery config must be a map, keyword list, or matching config struct")
    end
  end

  defp config_map!(asset, type, _module, _config) do
    invalid_config!(asset, "#{type} gallery config must be a map, keyword list, or matching config struct")
  end

  defp build_struct!(asset, type, module, values) do
    valid_fields = module.__struct__() |> Map.delete(:__struct__) |> Map.keys()
    unknown_fields = Map.keys(values) -- valid_fields

    if unknown_fields == [] do
      struct(module, values)
    else
      invalid_config!(asset, "unknown #{type} config fields: #{inspect(Enum.sort(unknown_fields))}")
    end
  end

  defp ensure_gallery_keys!(asset, config) do
    case Map.keys(config) -- [:image, :video] do
      [] -> :ok
      unknown -> invalid_config!(asset, "unknown gallery config fields: #{inspect(Enum.sort(unknown))}")
    end
  end

  defp invalid_config!(asset, message) do
    raise Brando.Exception.BlueprintError,
      message: "Invalid :cfg for #{asset.type} asset #{inspect(asset.name)}: #{message}"
  end

  defp merge_image_config(default_config, override) do
    merged = deep_merge(default_config, override)

    cond do
      not Map.has_key?(override, :sizes) -> merged
      Map.has_key?(override, :srcset) -> Map.put(merged, :sizes, override.sizes)
      true -> %{merged | sizes: override.sizes, srcset: inherited_srcset(merged.srcset, override.sizes)}
    end
  end

  # A config that replaces `sizes` but gives no `srcset` inherits the default
  # one, which may name sizes it no longer has. Only a field rendered with its
  # own srcset reads it, and that would get broken URLs, so drop it instead of
  # failing the Blueprint over a srcset it never declared.
  defp inherited_srcset(srcset, sizes) do
    with {:ok, sizes} when is_map(sizes) <- Size.normalize_sizes(sizes),
         {:ok, names} <- AssetConfigValidator.srcset_size_names(srcset),
         false <- Enum.all?(names, &Map.has_key?(sizes, &1)) do
      nil
    else
      _keep -> srcset
    end
  end

  @spec deep_merge(map(), map()) :: map()
  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = left_value, %{} = right_value -> deep_merge(left_value, right_value)
      _key, _left_value, right_value -> right_value
    end)
  end
end
