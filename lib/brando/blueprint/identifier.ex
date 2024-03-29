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
    fields = extract_fields_from_identifier(tpl)

    quote location: :keep do
      def __identifier_fields__ do
        unquote(fields)
      end

      def __has_identifier__ do
        true
      end

      @parsed_identifier unquote(parsed_identifier)
      def __identifier__(entry, opts \\ []) do
        skip_cover = Keyword.get(opts, :skip_cover, false)
        context = Villain.get_base_context(entry)
        {result, _} = Liquex.Render.render!([], @parsed_identifier, context)
        title = Enum.join(result)

        translated_type =
          Utils.try_path(__MODULE__.__translations__(), [:naming, :singular]) || @singular

        status = Map.get(entry, :status, nil)
        language = Map.get(entry, :language, nil)

        language =
          (is_nil(language) && nil) || (is_binary(language) && String.to_existing_atom(language)) ||
            language

        first_image_asset = Enum.find(__MODULE__.__assets__(), &(&1.type == :image))

        cover =
          if skip_cover,
            do: nil,
            else: Brando.Blueprint.Identifier.extract_cover(first_image_asset, entry)

        updated_at =
          (Map.has_key?(entry, :updated_at) && Brando.Utils.ensure_utc(entry.updated_at)) || nil

        %Brando.Content.Identifier{
          entry_id: entry.id,
          title: title,
          status: status,
          language: language,
          cover: cover,
          schema: __MODULE__,
          updated_at: updated_at
        }
      end
    end
  end

  defmacro identifier(nil) do
    quote location: :keep do
      def __has_identifier__ do
        false
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
    Brando.Content.list_identifiers(schema, list_opts)
  end

  def get_entry_for_identifier(%Brando.Content.Identifier{entry_id: entry_id, schema: schema}) do
    if function_exported?(schema, :__info__, 1) do
      context = schema.__modules__().context
      singular = schema.__naming__().singular
      opts = %{matches: %{id: entry_id}}
      apply(context, :"get_#{singular}", [opts])
    else
      {:error, :module_does_not_exist}
    end
  end

  @spec identifiers_for([map]) :: {:ok, list}
  def identifiers_for(entries) do
    {:ok, Enum.map(entries, &identifier_for/1)}
  end

  @spec identifiers_for([map]) :: list
  def identifiers_for!(entries) do
    Enum.map(entries, &identifier_for/1)
  end

  def identifier_for(%{__struct__: schema} = entry) do
    schema.__identifier__(entry)
  end

  def extract_cover(nil, _), do: nil
  def extract_cover(_, nil), do: nil

  def extract_cover(%{name: field_name} = field, entry) do
    case Map.get(entry, field_name) do
      nil ->
        nil

      %Ecto.Association.NotLoaded{} ->
        entry = Brando.repo().preload(entry, field_name)
        extract_cover(field, entry)

      cover ->
        Utils.img_url(cover, :thumb, prefix: Utils.media_url())
    end
  end

  @doc """
  Attempt to extract necessary fields from identifier template
  """
  def extract_fields_from_identifier(tpl) do
    regex = ~r/.*?(entry[.a-zA-Z0-9_]+).*?/

    matches =
      regex
      |> Regex.scan(tpl, capture: :all_but_first)
      |> Enum.map(&String.split(List.first(&1), "."))
      |> Enum.filter(&(Enum.count(&1) > 1))

    matches
    |> Enum.map(fn
      [_, rel, f] -> [{String.to_existing_atom(rel), String.to_existing_atom(f)}]
      [_, f] -> String.to_existing_atom(f)
    end)
    |> Enum.reject(&is_nil(&1))
    |> Enum.uniq()
  end

  @doc """
  Cleans up the identifiers table by removing identifiers that are no longer valid and
  updating existing identifiers
  """
  def clean_up do
    {:ok, identifiers} = Brando.Content.list_identifiers()

    for identifier <- identifiers do
      case get_entry_for_identifier(identifier) do
        {:error, :module_does_not_exist} ->
          require Logger

          Logger.error("""
          !! Could not find schema #{inspect(identifier.schema)} in application. Deleting identifier
          """)

          Brando.Content.delete_identifier(identifier)

        {:error, _} ->
          require Logger

          Logger.error("""
          !! Could not find entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}. Deleting identifier
          """)

          Brando.Content.delete_identifier(identifier)

        {:ok, entry} ->
          # update the identifier
          require Logger

          Logger.error("""
          $$ Updating identifier for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}
          """)

          Brando.Content.update_identifier(entry.__struct__, entry)
      end
    end
  end
end
