defmodule Brando.Images.ConfigResolver do
  @moduledoc """
  Resolves an image's stored config target without depending on the Images context.

  Keeping this lookup separate lets rendering and other low-level consumers use
  field-specific sizes and CDN settings without pulling database/query concerns
  into their dependency graph.
  """

  alias Brando.Assets.ConfigTarget
  alias Brando.Blueprint.Assets
  alias Brando.RuntimeConfig
  alias Brando.Type.ImageConfig

  @doc "Resolves the image configuration for an image, target string, or default."
  @spec get(map() | String.t() | term()) :: {:ok, ImageConfig.t() | map()}
  def get(%{config_target: nil}), do: {:ok, default_config()}

  def get(%{config_target: config_target} = image) when is_binary(config_target) do
    config = resolve_target(config_target, image)
    {:ok, config}
  end

  def get(config_target) when is_binary(config_target), do: get(%{config_target: config_target})
  def get(_image_or_target), do: get(%{config_target: "default"})

  defp resolve_target(config_target, image) do
    case String.split(config_target, ":") do
      ["image", schema, "function", function] ->
        ConfigTarget.config_function!(schema, function)

      ["gallery", schema, "function", function] ->
        schema
        |> ConfigTarget.config_function!(function)
        |> gallery_image_config()

      [type, schema, field_name] when type in ["image", "gallery"] ->
        resolve_field_config(type, schema, field_name, config_target, image)

      ["default"] ->
        default_config()
    end
  end

  defp resolve_field_config(type, schema, field_name, config_target, image) do
    case ConfigTarget.schema_module(schema) do
      {:ok, schema_module} ->
        config =
          schema_module
          |> Assets.__asset_opts__(ConfigTarget.field_atom!(schema, field_name))
          |> Map.get(:cfg)

        if type == "gallery", do: gallery_image_config(config), else: config

      :error ->
        IO.warn("""

        Missing schema module #{inspect(schema)} for config_target #{inspect(config_target)}

        #{inspect(image, pretty: true)}

        """)

        ImageConfig.default_config()
    end
  end

  defp default_config do
    case RuntimeConfig.images(:default_config) do
      %ImageConfig{} = config -> config
      nil -> ImageConfig.default_config()
      config -> struct(ImageConfig, config)
    end
  end

  defp gallery_image_config(%{image: image}), do: image
  defp gallery_image_config(config), do: config
end
