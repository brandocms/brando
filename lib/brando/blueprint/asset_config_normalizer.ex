defmodule Brando.Blueprint.AssetConfigNormalizer do
  @moduledoc """
  Materializes deferred Blueprint asset configuration at runtime.

  Asset DSL compilation may retain a zero-arity configuration function. This
  module evaluates and normalizes it without making runtime Blueprint metadata
  reads depend on the compile-time Spark DSL extension.
  """

  alias Brando.Blueprint.AssetConfigValidator
  alias Brando.RuntimeConfig

  @image_config Module.concat(["Brando", "Type", "ImageConfig"])
  @video_config Module.concat(["Brando", "Type", "VideoConfig"])
  @file_config Module.concat(["Brando", "Type", "FileConfig"])
  @image_context Module.concat(["Brando", "Images"])
  @video_context Module.concat(["Brando", "Videos"])
  @file_context Module.concat(["Brando", "Files"])

  @doc """
  Evaluates and normalizes a deferred asset config, leaving materialized assets unchanged.
  """
  @spec normalize(struct()) :: struct()
  def normalize(%{opts: %{cfg: config}} = asset) when is_function(config, 0) do
    normalized =
      case asset.type do
        :image -> normalize_config(asset, @image_config, config.(), [:db])
        :video -> normalize_config(asset, @video_config, config.(), [])
        :file -> normalize_config(asset, @file_config, config.(), [:config_target])
        :gallery -> normalize_gallery_config(config.(), gallery_default_config())
      end

    normalized = AssetConfigValidator.validate!(asset, normalized)
    %{asset | opts: Map.put(asset.opts, :cfg, normalized)}
  end

  def normalize(asset), do: asset

  defp normalize_config(asset, config_module, config, passthrough_values) do
    cond do
      config in passthrough_values ->
        config

      config == :default ->
        default_asset_config(asset.type, config_module)

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
        merge_image_config(default_map, overrides_map)
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

    default_config = configured || config_module.default_config()
    normalize_asset_config(config_module, default_config)
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
    %{
      image: merge_config(@image_config, defaults.image, Map.delete(config, :video)),
      video: merge_config(@video_config, defaults.video, video)
    }
  end

  defp normalize_gallery_config(config, defaults) do
    %{defaults | image: merge_config(@image_config, defaults.image, config)}
  end

  defp merge_config(module, default, overrides) do
    default_map = if is_struct(default), do: Map.from_struct(default), else: Map.new(default)
    override_map = if is_struct(overrides), do: Map.from_struct(overrides), else: Map.new(overrides)
    struct(module, deep_merge(default_map, override_map))
  end

  defp normalize_asset_config(module, config) when is_struct(config, module), do: config
  defp normalize_asset_config(module, config), do: struct(module, config)

  defp merge_image_config(default_config, override) do
    merged = deep_merge(default_config, override)

    if Map.has_key?(override, :sizes) do
      Map.put(merged, :sizes, override.sizes)
    else
      merged
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
