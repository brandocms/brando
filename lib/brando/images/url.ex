defmodule Brando.Images.URL do
  @moduledoc """
  Resolves image URLs without depending on the database-backed Images context.

  Supports named sizes, `:smallest`, `:largest`, originals, field-specific CDN
  configuration, prefixes, defaults, and cache strings.
  """

  alias Brando.Images.ConfigResolver
  alias Brando.RuntimeConfig

  @doc "Resolves the requested image size to a URL."
  @spec url(map() | nil | String.t(), atom() | String.t(), keyword()) :: String.t()
  def url(image, size, opts \\ [])

  def url(image, _size, opts) when image in [nil, ""] do
    Keyword.get(opts, :default) || cache_string(opts)
  end

  def url(image, "largest", opts), do: url(image, :largest, opts)

  def url(image, :largest, opts) do
    {:ok, config} = ConfigResolver.get(image)

    size =
      config.sizes
      |> Enum.map(fn {key, %{"size" => dimensions}} -> {key, dimension(dimensions)} end)
      |> Enum.max_by(&elem(&1, 1))
      |> elem(0)

    url(image, size, opts)
  end

  def url(image, "smallest", opts), do: url(image, :smallest, opts)

  def url(image, :smallest, opts) do
    {:ok, config} = ConfigResolver.get(image)

    size =
      config.sizes
      |> Map.drop(["thumb", "micro"])
      |> Enum.map(fn {key, %{"size" => dimensions}} -> {key, dimension(dimensions)} end)
      |> Enum.min_by(&elem(&1, 1))
      |> elem(0)

    url(image, size, opts)
  end

  def url(image, "original", opts), do: url(image, :original, opts)

  def url(image, :original, opts) do
    prefix = build_prefix(image, Keyword.get(opts, :prefix))
    (prefix && Path.join([prefix, image.path])) || image.path <> cache_string(opts)
  end

  def url(image, size, opts) do
    size = if is_atom(size), do: Atom.to_string(size), else: size
    size_path = extract_size_path(image, size)
    prefix = build_prefix(image, Keyword.get(opts, :prefix))

    resolved_url = (prefix && Path.join([prefix, size_path])) || size_path
    resolved_url <> cache_string(opts)
  end

  defp dimension(dimensions) do
    dimensions
    |> Integer.parse()
    |> elem(0)
  end

  defp extract_size_path(image, size) do
    if is_map(image.sizes) && Map.has_key?(image.sizes, size) do
      image.sizes[size]
    else
      IO.warn("""
      Wrong size key for img_url function.

      Size `#{size}` does not exist for image struct:

      #{inspect(image, pretty: true)})
      """)

      "non_existing"
    end
  rescue
    KeyError ->
      if Map.has_key?(image["sizes"], size), do: image["sizes"][size]
  end

  defp build_prefix(image, prefix) do
    if Map.get(image, :cdn, false) do
      image
      |> cdn_prefix()
      |> case do
        nil -> prefix
        cdn_prefix -> (prefix && Path.join([cdn_prefix, prefix])) || cdn_prefix
      end
    else
      prefix
    end
  end

  defp cdn_prefix(image) do
    {:ok, image_config} = ConfigResolver.get(image)
    image_cdn = Map.get(image_config, :cdn)
    global_cdn = RuntimeConfig.images(:cdn)

    cond do
      enabled?(image_cdn) -> Map.get(image_cdn, :media_url)
      enabled?(global_cdn) -> Map.get(global_cdn, :media_url)
      true -> nil
    end
  end

  defp enabled?(%{enabled: true}), do: true
  defp enabled?(_config), do: false

  defp cache_string(opts) do
    case Keyword.get(opts, :cache) do
      nil -> ""
      cache when cache in [:timestamp, "timestamp"] -> "?#{DateTime.utc_now() |> DateTime.to_unix()}"
      cache when is_binary(cache) -> "?#{cache}"
      cache -> "?#{cache |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()}"
    end
  end
end
