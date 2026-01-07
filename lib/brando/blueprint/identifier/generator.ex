defmodule Brando.Blueprint.Identifier.Generator do
  @moduledoc """
  Generates identifier structs from blueprint entries at runtime.

  This module handles the runtime generation of `Brando.Content.Identifier`
  structs from entry data using parsed Liquex templates.
  """

  alias Brando.Content.Identifier
  alias Brando.Utils
  alias Brando.Villain

  @doc """
  Creates an Identifier struct from an entry using the parsed Liquex template.

  Called by the generated `__identifier__/2` function in blueprints.

  ## Options

  - `:skip_cover` - If `true`, skips cover image extraction (default: `false`)

  ## Examples

      iex> generate(MyApp.Blog.Article, article, parsed_template, [])
      %Brando.Content.Identifier{
        entry_id: 1,
        title: "My Article",
        status: :published,
        ...
      }
  """
  @spec generate(module(), map(), list(), keyword()) :: Identifier.t()
  def generate(module, entry, parsed_identifier, opts \\ []) do
    skip_cover = Keyword.get(opts, :skip_cover, false)
    context = Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render!([], parsed_identifier, context)
    title = Enum.join(result)
    status = Map.get(entry, :status, nil)
    language = normalize_language(Map.get(entry, :language, nil))

    image_assets = get_ordered_image_assets(module)
    first_image_asset = List.first(image_assets)
    cover = if skip_cover, do: nil, else: extract_cover(first_image_asset, entry)
    updated_at = extract_updated_at(entry)
    url = extract_url(entry)

    %Identifier{
      entry_id: entry.id,
      title: title,
      status: status,
      language: language,
      cover: cover,
      schema: module,
      updated_at: updated_at,
      url: url
    }
  end

  @doc """
  Extracts cover image URL from an entry's image asset.

  Handles `nil` values, not-loaded associations (by preloading them),
  and returns the thumb-sized URL.

  ## Examples

      iex> extract_cover(%{name: :cover}, %{cover: %Image{...}})
      "/media/images/thumb/image.jpg"

      iex> extract_cover(nil, entry)
      nil
  """
  @spec extract_cover(map() | nil, map() | nil) :: String.t() | nil
  def extract_cover(nil, _), do: nil
  def extract_cover(_, nil), do: nil

  def extract_cover(%{name: field_name} = field, entry) do
    case Map.get(entry, field_name) do
      nil ->
        nil

      %Ecto.Association.NotLoaded{} ->
        entry = Brando.Repo.preload(entry, field_name)
        extract_cover(field, entry)

      cover ->
        Utils.img_url(cover, :thumb, prefix: Utils.media_url())
    end
  end

  # Normalizes language to an atom, handling nil, binary, and atom inputs
  defp normalize_language(nil), do: nil
  defp normalize_language(language) when is_binary(language), do: String.to_existing_atom(language)
  defp normalize_language(language) when is_atom(language), do: language

  # Gets image assets ordered with meta_image last (preferred cover images first)
  defp get_ordered_image_assets(module) do
    image_assets = Enum.filter(Brando.Blueprint.Assets.__assets__(module), &(&1.type == :image))

    # Move :meta_image to last position if it's first (prefer other images for cover)
    if image_assets != [] and List.first(image_assets).name == :meta_image do
      image_assets
      |> List.delete_at(0)
      |> List.insert_at(-1, List.first(image_assets))
    else
      image_assets
    end
  end

  # Extracts updated_at as UTC datetime
  defp extract_updated_at(entry) do
    if Map.has_key?(entry, :updated_at) do
      Brando.Utils.ensure_utc(entry.updated_at)
    else
      nil
    end
  end

  # Extracts absolute URL if the schema supports it
  defp extract_url(entry) do
    if {:__absolute_url__, 1} in entry.__struct__.__info__(:functions) do
      entry.__struct__.__absolute_url__(entry)
    else
      nil
    end
  end
end
