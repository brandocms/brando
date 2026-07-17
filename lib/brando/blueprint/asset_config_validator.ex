defmodule Brando.Blueprint.AssetConfigValidator do
  @moduledoc false

  alias Brando.Assets.CompletedCallback
  alias Brando.Exception.BlueprintError

  @boolean_fields [
    :allow_external_urls,
    :allow_uploads,
    :overwrite,
    :random_filename,
    :slugify_filename
  ]
  @image_formats [:avif, :gif, :jpg, :original, :png, :webp]
  @video_strategies [:bunny, :cloudflare, :local, :mux, :s3]

  @doc false
  @spec validate!(struct(), term()) :: term()
  def validate!(_asset, config) when config in [:config_target, :db], do: config
  def validate!(_asset, config) when is_function(config, 0), do: config

  def validate!(%{type: :gallery} = asset, %{image: image_config, video: video_config} = config) do
    validate_config!(asset, :image, image_config)
    validate_config!(asset, :video, video_config)
    config
  end

  def validate!(%{type: type} = asset, config) when type in [:file, :image, :video] and is_map(config) do
    validate_config!(asset, type, config)
    config
  end

  defp validate_config!(asset, type, config) do
    validate_non_empty_string!(asset, type, config, :upload_path)
    validate_positive_integer!(asset, type, config, :size_limit)
    validate_mimetypes!(asset, type, config)
    Enum.each(@boolean_fields, &validate_boolean!(asset, type, config, &1))
    validate_force_filename!(asset, type, config)
    validate_completed_callback!(asset, type, config)
    validate_type_specific!(asset, type, config)
  end

  defp validate_type_specific!(asset, :image, config) do
    validate_non_empty_map!(asset, :image, config, :sizes)
    validate_formats!(asset, config)

    case Map.get(config, :srcset) do
      value when is_nil(value) or is_map(value) or is_list(value) -> :ok
      value -> invalid!(asset, :image, :srcset, "expected nil, a map, or a legacy list, got: #{inspect(value)}")
    end
  end

  defp validate_type_specific!(asset, :file, config) do
    case Map.get(config, :content_disposition) do
      value when value in [nil, :attachment, :inline] ->
        :ok

      value ->
        invalid!(asset, :file, :content_disposition, "expected nil, :attachment, or :inline, got: #{inspect(value)}")
    end
  end

  defp validate_type_specific!(asset, :video, config) do
    case Map.get(config, :upload_strategy) do
      strategy when strategy in @video_strategies ->
        :ok

      strategy ->
        invalid!(
          asset,
          :video,
          :upload_strategy,
          "expected one of #{inspect(@video_strategies)}, got: #{inspect(strategy)}"
        )
    end

    validate_map!(asset, :video, config, :meta)
  end

  defp validate_non_empty_string!(asset, type, config, field) do
    case Map.get(config, field) do
      value when is_binary(value) and value != "" -> :ok
      value -> invalid!(asset, type, field, "expected a non-empty string, got: #{inspect(value)}")
    end
  end

  defp validate_positive_integer!(asset, type, config, field) do
    case Map.get(config, field) do
      value when is_integer(value) and value > 0 -> :ok
      value -> invalid!(asset, type, field, "expected a positive integer, got: #{inspect(value)}")
    end
  end

  defp validate_mimetypes!(asset, type, config) do
    case Map.get(config, :allowed_mimetypes) do
      values when is_list(values) and values != [] ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          :ok
        else
          invalid!(asset, type, :allowed_mimetypes, "expected a non-empty list of MIME type strings")
        end

      value ->
        invalid!(
          asset,
          type,
          :allowed_mimetypes,
          "expected a non-empty list of MIME type strings, got: #{inspect(value)}"
        )
    end
  end

  defp validate_boolean!(asset, type, config, field) do
    if Map.has_key?(config, field) do
      case Map.fetch!(config, field) do
        value when is_boolean(value) -> :ok
        value -> invalid!(asset, type, field, "expected a boolean, got: #{inspect(value)}")
      end
    end
  end

  defp validate_force_filename!(asset, type, config) do
    if Map.has_key?(config, :force_filename) do
      case Map.fetch!(config, :force_filename) do
        value when is_nil(value) or (is_binary(value) and value != "") -> :ok
        value -> invalid!(asset, type, :force_filename, "expected nil or a non-empty string, got: #{inspect(value)}")
      end
    end
  end

  defp validate_completed_callback!(asset, type, config) do
    case CompletedCallback.validate(Map.get(config, :completed_callback)) do
      :ok -> :ok
      {:error, message} -> invalid!(asset, type, :completed_callback, message)
    end
  end

  defp validate_map!(asset, type, config, field) do
    case Map.get(config, field) do
      value when is_map(value) -> :ok
      value -> invalid!(asset, type, field, "expected a map, got: #{inspect(value)}")
    end
  end

  defp validate_non_empty_map!(asset, type, config, field) do
    case Map.get(config, field) do
      value when is_map(value) and map_size(value) > 0 -> :ok
      value -> invalid!(asset, type, field, "expected a non-empty map, got: #{inspect(value)}")
    end
  end

  defp validate_formats!(asset, config) do
    case Map.get(config, :formats) do
      formats when is_list(formats) and formats != [] ->
        case Enum.find(formats, &(&1 not in @image_formats)) do
          nil -> :ok
          format -> invalid!(asset, :image, :formats, "contains unsupported format #{inspect(format)}")
        end

      value ->
        invalid!(asset, :image, :formats, "expected a non-empty list, got: #{inspect(value)}")
    end
  end

  defp invalid!(asset, media_type, field, message) do
    raise BlueprintError,
      message:
        "Invalid #{media_type} config for #{asset.type} asset #{inspect(asset.name)}: " <>
          "#{inspect(field)} #{message}"
  end
end
