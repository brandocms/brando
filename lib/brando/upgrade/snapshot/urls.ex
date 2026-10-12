defmodule Brando.Upgrade.Snapshot.URLs do
  @moduledoc """
  The URL set `mix brando.upgrade.snapshot` captures by default, read from
  the running application's database:

    * `/`
    * every published page, in every language
    * for every other Blueprint with an `absolute_url`, one published entry
      per language
    * a path that does not exist, per language and without one, for the 404
      page
    * `/robots.txt` and `/sitemap.xml`

  Paths are relative to the site's root, sorted and without duplicates.
  A Blueprint whose entries cannot be listed is left out, with a warning
  returned beside the paths.
  """

  alias Brando.Pages.Page
  alias Brando.SEO.Audit

  @missing "brando-upgrade-snapshot-missing"

  @doc """
  `{paths, warnings}`: the URL set and a line for each Blueprint left out.
  """
  @spec list() :: {[String.t()], [String.t()]}
  def list do
    languages = languages()

    {entry_paths, warnings} =
      blueprints()
      |> Enum.map(&blueprint_paths(&1, languages))
      |> Enum.reduce({[], []}, fn
        {:ok, paths}, {all, warnings} -> {all ++ paths, warnings}
        {:error, warning}, {all, warnings} -> {all, warnings ++ [warning]}
      end)

    missing = ["/#{@missing}" | Enum.map(languages, &"/#{&1}/#{@missing}")]
    paths = ["/", "/robots.txt", "/sitemap.xml"] ++ missing ++ entry_paths

    {paths |> Enum.uniq() |> Enum.sort(), warnings}
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

  defp blueprint_paths(schema, languages) do
    context = schema.__modules__().context
    list = :"list_#{schema.__naming__().plural}"

    if Code.ensure_loaded?(context) and function_exported?(context, list, 1) do
      {:ok, entry_paths(schema, &list_entries(context, list, schema, &1), languages)}
    else
      {:error, "#{inspect(schema)}: no #{inspect(context)}.#{list}/1 to read its entries; add its URLs by hand"}
    end
  rescue
    exception -> {:error, "#{inspect(schema)}: #{Exception.message(exception)}"}
  end

  # Every published page; one entry of anything else, per language when it
  # is translated.
  defp entry_paths(Page, list, _languages), do: %{} |> list.() |> paths(Page)

  defp entry_paths(schema, list, languages) do
    if schema.has_trait(Brando.Trait.Translatable),
      do: Enum.flat_map(languages, &(%{language: &1, limit: 5} |> list.() |> paths(schema) |> Enum.take(1))),
      else: %{limit: 5} |> list.() |> paths(schema) |> Enum.take(1)
  end

  defp list_entries(context, list, schema, args) do
    args =
      args
      |> Map.put(:preload, schema.__absolute_url_preloads__())
      |> Map.put(:order, "asc id")

    args = if :status in schema.__schema__(:fields), do: Map.put(args, :status, :published), else: args

    case apply(context, list, [args]) do
      {:ok, entries} -> entries
      _ -> []
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
