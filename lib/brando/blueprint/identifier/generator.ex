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
  @spec generate(module(), map(), list() | String.t(), keyword()) :: Identifier.t()
  def generate(module, entry, parsed_identifier, opts \\ [])

  def generate(module, entry, parsed_identifier, opts) when is_list(parsed_identifier) do
    context = Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render!([], parsed_identifier, context)
    generate(module, entry, Enum.join(result), opts)
  end

  def generate(module, entry, title, opts) when is_binary(title) do
    build_identifier(module, entry, String.trim(title), opts)
  end

  defp build_identifier(module, entry, title, opts) do
    skip_cover = Keyword.get(opts, :skip_cover, false)
    status = Map.get(entry, :status, nil)
    language = normalize_language(module, Map.get(entry, :language, nil))

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

  defp normalize_language(_module, nil), do: nil

  defp normalize_language(module, language) do
    case enum_languages(module) do
      [] -> normalize_existing_language(module, language)
      languages -> normalize_enum_language(module, language, languages)
    end
  end

  defp enum_languages(module) do
    if function_exported?(module, :__schema__, 1) and
         match?({:parameterized, {Ecto.Enum, _}}, module.__schema__(:type, :language)) do
      Ecto.Enum.values(module, :language)
    else
      []
    end
  end

  defp normalize_enum_language(module, language, languages) when is_binary(language) or is_atom(language) do
    language_string = to_string(language)

    Enum.find(languages, &(Atom.to_string(&1) == language_string)) ||
      invalid_language!(module, language, languages)
  end

  defp normalize_enum_language(module, language, languages), do: invalid_language!(module, language, languages)

  defp normalize_existing_language(_module, language) when is_atom(language), do: language

  defp normalize_existing_language(module, language) when is_binary(language) do
    String.to_existing_atom(language)
  rescue
    ArgumentError -> invalid_language!(module, language, [])
  end

  defp normalize_existing_language(module, language), do: invalid_language!(module, language, [])

  defp invalid_language!(module, language, []) do
    raise ArgumentError,
          "cannot generate identifier for #{inspect(module)} with invalid language #{inspect(language)}"
  end

  defp invalid_language!(module, language, languages) do
    raise ArgumentError,
          "cannot generate identifier for #{inspect(module)} with language #{inspect(language)}; " <>
            "expected one of #{inspect(languages)}"
  end

  defp get_ordered_image_assets(module) do
    image_assets = Enum.filter(Brando.Blueprint.Assets.__assets__(module), &(&1.type == :image))
    {content_images, meta_images} = Enum.split_with(image_assets, &(&1.name != :meta_image))

    content_images ++ meta_images
  end

  defp extract_updated_at(entry) do
    if Map.has_key?(entry, :updated_at) do
      Utils.ensure_utc(entry.updated_at)
    else
      nil
    end
  end

  defp extract_url(entry) do
    if function_exported?(entry.__struct__, :__absolute_url__, 1) do
      entry.__struct__.__absolute_url__(entry)
    else
      nil
    end
  end
end
