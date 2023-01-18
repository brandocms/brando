defmodule Brando.Blueprint.Identifier do
  @moduledoc """
  Identifies the entry

  ## Example

      identifier "{{ entry.title }} [{{ entry.language }}]"

  """

  alias Brando.Villain
  alias Brando.Villain.LiquexParser
  alias Brando.Utils

  defmacro identifier(tpl) when is_binary(tpl) do
    {:ok, parsed_identifier} = Liquex.parse(tpl, LiquexParser)

    quote location: :keep do
      @parsed_identifier unquote(parsed_identifier)
      def __identifier__(entry, opts \\ []) do
        skip_cover = Keyword.get(opts, :skip_cover, false)
        context = Villain.get_base_context(entry)
        {result, _} = Liquex.Render.render([], @parsed_identifier, context)
        title = Enum.join(result)

        translated_type =
          Utils.try_path(__MODULE__.__translations__(), [:naming, :singular]) || @singular

        status = Map.get(entry, :status, nil)
        language = Map.get(entry, :language, nil)
        absolute_url = __MODULE__.__absolute_url__(entry)
        admin_url = __MODULE__.__admin_url__(entry)
        cover = if skip_cover, do: nil, else: Brando.Blueprint.Identifier.extract_cover(entry)

        %Brando.Content.Identifier{
          id: entry.id,
          title: title,
          type: String.capitalize(translated_type),
          status: status,
          language: language,
          absolute_url: absolute_url,
          admin_url: admin_url,
          cover: cover,
          schema: __MODULE__,
          updated_at: entry.updated_at
        }
      end
    end
  end

  def list_entry_types do
    blueprints = Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page]
    entry_types = Enum.map(blueprints, &{Brando.Blueprint.get_plural(&1), &1})
    {:ok, entry_types}
  end

  def get_entry_types(wanted_types) do
    wanted_types
    |> Enum.reduce([], fn {wanted_type, list_opts}, acc ->
      [{Brando.Blueprint.get_plural(wanted_type), wanted_type, list_opts} | acc]
    end)
    |> Enum.reverse()
  end

  def list_entries_for(schema, list_opts \\ %{})

  def list_entries_for(schema_binary, list_opts) when is_binary(schema_binary) do
    schema_binary
    |> List.wrap()
    |> Module.concat()
    |> list_entries_for(list_opts)
  end

  def list_entries_for(schema, list_opts) when is_atom(schema) do
    context = schema.__modules__().context
    plural = schema.__naming__().plural

    {:ok, entries} = apply(context, :"list_#{plural}", [list_opts])
    identifiers_for(entries)
  end

  def get_entry_for_identifier(%Brando.Content.Identifier{id: id, schema: schema}) do
    context = schema.__modules__().context
    singular = schema.__naming__().singular
    opts = %{matches: %{id: id}}
    apply(context, :"get_#{singular}", [opts])
  end

  @spec identifiers_for([map]) :: {:ok, list}
  def identifiers_for(entries) do
    {:ok,
     entries
     |> Enum.map(&identifier_for/1)
     |> Enum.sort_by(&{&1.type, &1.language, &1.status, &1.title})}
  end

  @spec identifiers_for([map]) :: list
  def identifiers_for!(entries) do
    entries
    |> Enum.map(&identifier_for/1)
    |> Enum.sort_by(&{&1.type, &1.language, &1.status, &1.title})
  end

  def identifier_for(%{__struct__: schema} = entry) do
    schema.__identifier__(entry)
  end

  def extract_cover(%{cover: nil}) do
    nil
  end

  def extract_cover(%{listing_image: nil}) do
    nil
  end

  def extract_cover(%{cover: %Ecto.Association.NotLoaded{}} = entry) do
    entry = Brando.repo().preload(entry, :cover)
    extract_cover(entry)
  end

  def extract_cover(%{cover: cover}) do
    Utils.img_url(cover, :thumb, prefix: Utils.media_url())
  end

  def extract_cover(%{listing_image: %Ecto.Association.NotLoaded{}} = entry) do
    entry = Brando.repo().preload(entry, :listing_image)
    extract_cover(entry)
  end

  def extract_cover(%{listing_image: listing_image}) do
    Utils.img_url(listing_image, :thumb, prefix: Utils.media_url())
  end

  def extract_cover(_) do
    nil
  end
end
