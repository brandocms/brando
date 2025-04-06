defmodule Brando.Blueprint.Identifier do
  @moduledoc """
  Identifies the entry

  ## Example

      identifier "{{ entry.title }}"

  """

  import Ecto.Query

  alias Brando.Content.Identifier
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.LiquexParser

  defmacro persist_identifier(persist?) do
    quote location: :keep do
      def __persist_identifier__ do
        unquote(persist?)
      end
    end
  end

  defmacro identifier(tpl) when is_binary(tpl) do
    {:ok, parsed_identifier} = Liquex.parse(tpl, LiquexParser)
    fields = extract_fields_from_identifier(tpl)

    quote location: :keep do
      if @data_layer == :embedded do
        raise Brando.Exception.BlueprintError, """
        Identifiers are not supported with embedded data layer

        Set `identifier false` in your blueprint to disable identifiers
        """
      end

      def __identifier_fields__, do: unquote(fields)
      def __has_identifier__, do: true

      @parsed_identifier unquote(parsed_identifier)
      def __identifier__(entry, opts \\ []) do
        Brando.Blueprint.Identifier.handle_identifier(
          __MODULE__,
          entry,
          @parsed_identifier,
          opts
        )
      end
    end
  end

  defmacro identifier(nil) do
    quote location: :keep do
      def __has_identifier__, do: false
    end
  end

  defmacro identifier(false) do
    quote location: :keep do
      def __has_identifier__, do: false
    end
  end

  def handle_identifier(module, entry, parsed_identifier, opts) do
    skip_cover = Keyword.get(opts, :skip_cover, false)
    context = Villain.get_base_context(entry)
    {result, _} = Liquex.Render.render!([], parsed_identifier, context)
    title = Enum.join(result)
    status = Map.get(entry, :status, nil)
    language = Map.get(entry, :language, nil)

    language =
      (is_nil(language) && nil) || (is_binary(language) && String.to_existing_atom(language)) ||
        language

    image_assets = Enum.filter(Brando.Blueprint.Assets.__assets__(module), &(&1.type == :image))

    # if image_assets has :meta_image first, move it last
    image_assets =
      if image_assets != [] and List.first(image_assets).name == :meta_image do
        image_assets
        |> List.delete_at(0)
        |> List.insert_at(-1, List.first(image_assets))
      else
        image_assets
      end

    first_image_asset = List.first(image_assets)
    cover = if skip_cover, do: nil, else: extract_cover(first_image_asset, entry)
    updated_at = (Map.has_key?(entry, :updated_at) && Brando.Utils.ensure_utc(entry.updated_at)) || nil
    url = if {:__absolute_url__, 1} in entry.__struct__.__info__(:functions), do: entry.__struct__.__absolute_url__(entry)

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

  def get_entry_for_identifier(%Identifier{entry_id: entry_id, schema: schema}) do
    if function_exported?(schema, :__info__, 1) do
      context = schema.__modules__().context
      singular = schema.__naming__().singular
      preloads = Brando.Blueprint.preloads_for(schema)
      opts = %{matches: %{id: entry_id}, preload: preloads}
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
  rescue
    UndefinedFunctionError ->
      nil
  end

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
  def sync do
    # first grab all modules that have identifiers
    relevant_modules =
      :include_brando
      |> Brando.Blueprint.list_blueprints()
      |> Enum.filter(
        &(Brando.Content.has_identifier(&1) == {:ok, :has_identifier} &&
            Brando.Content.persist_identifier(&1) == {:ok, :persist_identifier})
      )

    IO.puts("=> Syncing identifiers. Relevant modules: #{inspect(relevant_modules)}")

    # select all identifiers with schema not in `relevant_modules`
    delete_query = from i in Identifier, where: i.schema not in ^relevant_modules
    Brando.Repo.delete_all(delete_query, [])

    IO.puts(
      IO.ANSI.red() <>
        "[-] Removing irrelevant identifiers" <>
        IO.ANSI.reset()
    )

    {:ok, identifiers} = Brando.Content.list_identifiers()

    for identifier <- identifiers do
      case get_entry_for_identifier(identifier) do
        {:error, :module_does_not_exist} ->
          IO.puts(
            IO.ANSI.red() <>
              "[-] Could not find schema #{inspect(identifier.schema)} in application. Deleting identifier" <>
              IO.ANSI.reset()
          )

          Brando.Content.delete_identifier(identifier)

        {:error, _} ->
          IO.puts(
            IO.ANSI.red() <>
              "[-] Could not find entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}. Deleting identifier" <>
              IO.ANSI.reset()
          )

          Brando.Content.delete_identifier(identifier)

        {:ok, %{deleted_at: deleted_at}} when not is_nil(deleted_at) ->
          IO.puts(
            IO.ANSI.red() <>
              "[-] Entry for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)} is marked as deleted. Deleting identifier" <>
              IO.ANSI.reset()
          )

          Brando.Content.delete_identifier(identifier)

        {:ok, entry} ->
          # update the identifier
          IO.puts(
            IO.ANSI.green() <>
              "[+] Updating identifier for identifier #{inspect(identifier.id)} in schema #{inspect(identifier.schema)}" <>
              IO.ANSI.reset()
          )

          Brando.Content.update_identifier(entry.__struct__, entry)
      end
    end

    create_missing_identifiers()
  end

  def create_missing_identifiers do
    relevant_modules =
      :include_brando
      |> Brando.Blueprint.list_blueprints()
      |> Enum.filter(
        &(Brando.Content.has_identifier(&1) == {:ok, :has_identifier} &&
            Brando.Content.persist_identifier(&1) == {:ok, :persist_identifier})
      )

    for module <- relevant_modules do
      identifiers_query =
        from i in Identifier, select: i.entry_id, where: i.schema == ^module

      current_identifiers = Brando.Repo.all(identifiers_query)

      # get all entry ids without identifiers
      preloads = Brando.Blueprint.preloads_for(module)

      entries_query =
        from e in module, where: e.id not in ^current_identifiers, preload: ^preloads

      entries = Brando.Repo.all(entries_query)

      for entry <- entries do
        {:ok, identifier} = Brando.Content.create_identifier(module, entry)

        if identifier do
          IO.puts(
            IO.ANSI.green() <>
              "[+] Creating identifier ##{inspect(identifier.id)} in schema #{inspect(identifier.schema)} for entry_id ##{identifier.entry_id}" <>
              IO.ANSI.reset()
          )
        end
      end
    end
  end
end
