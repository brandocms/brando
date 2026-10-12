defmodule Brando.Upgrade.Snapshot.URLs do
  @moduledoc """
  The URL set `mix brando.upgrade.snapshot` captures by default, read from
  the running application's database:

    * `/`
    * every published page, in every language
    * for every other Blueprint with an `absolute_url`, one published entry
      per language: the one with the most blocks, since a heavy entry shows
      more of what an upgrade changed than the first one made
    * a path that does not exist, per language and without one, for the 404
      page
    * `/robots.txt` and `/sitemap.xml`

  Given a way to ask the old site (`:found?`), entry URLs it answers with 404
  are left out, and for each other Blueprint the next-heaviest entry is tried
  instead: comparing two 404 pages tells nothing about the entry.

  Paths are relative to the site's root, sorted and without duplicates.
  A Blueprint whose entries cannot be listed is left out, with a warning
  returned beside the paths.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  alias Brando.Pages.Page
  alias Brando.SEO.Audit

  @missing "brando-upgrade-snapshot-missing"
  # Entries of a Blueprint tried, heaviest first, for one whose URL works.
  @candidates 10

  @doc """
  `{paths, warnings}`: the URL set and a line for each Blueprint, or URL,
  left out.

  ## Options

    * `:found?` — called with an entry's path; `false` when the old site
      answers it with 404. Every path counts as found by default.
  """
  @spec list(keyword()) :: {[String.t()], [String.t()]}
  def list(opts \\ []) do
    languages = languages()
    found? = Keyword.get(opts, :found?, fn _path -> true end)

    {entry_paths, warnings} =
      blueprints()
      |> Enum.map(&blueprint_paths(&1, languages, found?))
      |> Enum.reduce({[], []}, fn
        {:ok, paths, left_out}, {all, warnings} -> {all ++ paths, warnings ++ left_out}
        {:error, warning}, {all, warnings} -> {all, warnings ++ [warning]}
      end)

    missing = ["/#{@missing}" | Enum.map(languages, &"/#{&1}/#{@missing}")]
    paths = ["/", "/robots.txt", "/sitemap.xml"] ++ missing ++ entry_paths

    {paths |> Enum.uniq() |> Enum.sort(), warnings}
  end

  @doc """
  Up to `limit` (`nil` for all) published entries of `schema` matching
  `args` (`:language`), the ones with the most blocks first (top-level
  blocks, every block field), then by id. Loaded with what the schema's
  `absolute_url` needs.
  """
  @spec heaviest(module(), map(), pos_integer() | nil) :: [struct()]
  def heaviest(schema, args, limit) do
    counts = block_counts(schema)
    ids = schema |> published_ids(args) |> Enum.sort_by(&{-Map.get(counts, &1, 0), &1})
    ids = if limit, do: Enum.take(ids, limit), else: ids

    entries = Brando.Repo.all(from(e in schema, where: e.id in ^ids))
    by_id = Map.new(entries, &{&1.id, &1})

    ids
    |> Enum.map(&by_id[&1])
    |> Brando.Repo.preload(schema.__absolute_url_preloads__())
  end

  defp languages do
    (Brando.config(:languages) || [])
    |> Enum.map(&to_string(&1[:value]))
    |> Enum.reject(&(&1 == ""))
  end

  # `function_exported?/3` is false for a module not loaded yet.
  defp blueprints do
    :include_brando
    |> Brando.Blueprint.list_blueprints()
    |> Enum.uniq()
    |> Enum.reject(&(&1 == Brando.Pages.Fragment))
    |> Enum.filter(fn schema ->
      Code.ensure_loaded?(schema) and function_exported?(schema, :__has_absolute_url__, 0) and
        schema.__has_absolute_url__()
    end)
  end

  # Every published page; one entry of anything else, per language when it
  # is translated.
  defp blueprint_paths(Page, _languages, found?) do
    {found, missing} = Page |> heaviest(%{}, nil) |> paths(Page) |> Enum.split_with(found?)
    {:ok, found, Enum.map(missing, &"404 on the old site: #{&1}")}
  end

  defp blueprint_paths(schema, languages, found?) do
    args = if schema.has_trait(Brando.Trait.Translatable), do: Enum.map(languages, &%{language: &1}), else: [%{}]

    {paths, left_out} =
      Enum.reduce(args, {[], []}, fn args, {paths, left_out} ->
        candidates = schema |> heaviest(args, @candidates) |> paths(schema)

        case {Enum.find(candidates, found?), candidates} do
          {nil, []} ->
            {paths, left_out}

          {nil, [first | _]} ->
            warning = "404 on the old site: #{first}, and every other #{inspect(schema)} entry tried#{language(args)}"
            {paths, left_out ++ [warning]}

          {path, _candidates} ->
            {paths ++ [path], left_out}
        end
      end)

    {:ok, paths, left_out}
  rescue
    exception -> {:error, "#{inspect(schema)}: #{Exception.message(exception)}"}
  end

  defp language(%{language: language}), do: " (#{language})"
  defp language(_args), do: ""

  defp published_ids(schema, args) do
    fields = schema.__schema__(:fields)
    query = from(e in schema, select: e.id)
    query = if :status in fields, do: where(query, [e], e.status == ^:published), else: query
    query = if :deleted_at in fields, do: where(query, [e], is_nil(e.deleted_at)), else: query

    query =
      case args do
        %{language: language} when is_binary(language) -> where(query, [e], e.language == ^language)
        _ -> query
      end

    Brando.Repo.all(query)
  end

  # Top-level blocks per entry, summed over the schema's block fields.
  defp block_counts(schema) do
    if function_exported?(schema, :__blocks_fields__, 0) do
      schema.__blocks_fields__()
      |> Enum.flat_map(fn %{name: name} ->
        join_schema = Module.concat([schema, name |> to_string() |> Macro.camelize()])
        Brando.Repo.all(from(j in join_schema, group_by: j.entry_id, select: {j.entry_id, count()}))
      end)
      |> Enum.reduce(%{}, fn {id, count}, acc -> Map.update(acc, id, count, &(&1 + count)) end)
    else
      %{}
    end
  end

  defp paths(entries, schema) do
    for entry <- entries,
        Audit.has_url?(schema, entry),
        path = absolute_url(schema, entry),
        do: path
  end

  defp absolute_url(schema, entry) do
    case schema.__absolute_url__(entry) do
      "/" <> _ = path -> path
      "http" <> _ = url -> URI.parse(url).path || "/"
      _ -> nil
    end
  end
end
