defmodule Brando.Images.ConfigResolver do
  @moduledoc """
  Resolves an image's stored config target without depending on the Images context.

  Keeping this lookup separate lets rendering and other low-level consumers use
  field-specific sizes and CDN settings without pulling database/query concerns
  into their dependency graph.
  """

  alias Brando.Assets.ConfigTarget
  alias Brando.Blueprint.AssetConfigNormalizer
  alias Brando.RuntimeConfig
  alias Brando.Type.ImageConfig

  @doc "Resolves the image configuration for an image, target string, or default."
  @spec get(map() | String.t() | term()) :: {:ok, ImageConfig.t() | map()}
  def get(%{config_target: nil}), do: {:ok, default_config()}

  def get(%{config_target: config_target} = image) when is_binary(config_target) do
    config = resolve_target(config_target, {:stored, image})
    {:ok, config}
  end

  def get(config_target) when is_binary(config_target) do
    {:ok, resolve_target(config_target, :strict)}
  end

  def get(_image_or_target), do: get(%{config_target: "default"})

  defp resolve_target(config_target, resolution_mode) do
    case String.split(config_target, ":") do
      ["image", schema, "function", function] ->
        ConfigTarget.resolved_function_config!(:image, schema, function)

      ["gallery", schema, "function", function] ->
        ConfigTarget.resolved_function_config!(:gallery, schema, function)
        |> gallery_image_config()

      [type, schema, field_name] when type in ["image", "gallery"] ->
        resolve_field_config(type, schema, field_name, config_target, resolution_mode)

      ["default"] ->
        default_config()
    end
  end

  defp resolve_field_config(type, schema, field_name, config_target, resolution_mode) do
    expected_type = if type == "gallery", do: :gallery, else: :image

    case ConfigTarget.blueprint_asset(schema, field_name) do
      {:ok, %{type: ^expected_type} = asset} ->
        config = asset |> Map.get(:opts, %{}) |> Map.get(:cfg)

        if expected_type == :gallery do
          gallery_image_config(config)
        else
          AssetConfigNormalizer.normalize_resolved_value!(:image, config_target, config)
        end

      :error ->
        handle_invalid_field(
          resolution_mode,
          "invalid config_target field #{inspect(field_name)} for Blueprint #{inspect(schema)}"
        )

      {:ok, %{type: actual_type}} ->
        handle_invalid_field(
          resolution_mode,
          "config_target #{inspect(config_target)} resolves to #{inspect(actual_type)}, " <>
            "expected #{inspect(expected_type)}"
        )
    end
  end

  defp handle_invalid_field(:strict, message), do: raise(ArgumentError, message)

  defp handle_invalid_field({:stored, image}, message) do
    IO.warn("#{message}; using the default image config for #{inspect(image)}")
    default_config()
  end

  defp default_config do
    config = RuntimeConfig.images(:default_config) || ImageConfig.default_config()

    AssetConfigNormalizer.normalize_resolved_value!(:image, "default", config)
  end

  defp gallery_image_config(%{image: image}), do: image
  defp gallery_image_config(config), do: config
end
