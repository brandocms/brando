defmodule Brando.SEO.StructuredData do
  @moduledoc """
  Counts the published entries whose JSON-LD Google would flag, site-wide,
  for Content SEO.

  Every blueprint with a `json_ld_schema` and a page of its own is read in
  the content language, one query per schema plus one per association the
  mapping reads, and each entry's graph is built and checked with
  `Brando.JSONLD.Inspector`, as the entry's Meta drawer does. Only the nodes
  that describe the entry count (its entity, its authors and videos, its
  page and breadcrumbs); the site's identity is the same on every page.

  Blocks are not read, so videos in blocks are left out here: a site with
  thousands of entries would otherwise load every block. The drawer shows
  them.

  The result is cached for ten minutes per language; `refresh: true` runs
  it again.
  """

  alias Brando.JSONLD.Graph
  alias Brando.JSONLD.Inspector

  @ttl :timer.minutes(10)

  defmodule Row do
    @moduledoc "An entry with JSON-LD issues."
    @type t :: %__MODULE__{}
    defstruct schema: nil, id: nil, title: nil, url: nil, admin_url: nil, type: nil, errors: 0, warnings: 0, issues: []
  end

  defmodule Result do
    @moduledoc "The site-wide JSON-LD check for one language."
    @type t :: %__MODULE__{}
    defstruct language: nil,
              checked: 0,
              with_errors: 0,
              with_warnings: 0,
              rows: [],
              checked_at: nil,
              duration_ms: 0
  end

  @doc "Blueprints with a `json_ld_schema` and an `absolute_url`."
  @spec schemas() :: [module()]
  def schemas do
    :include_brando
    |> Brando.Blueprint.list_blueprints()
    |> Enum.filter(&checkable?/1)
  end

  @doc """
  The check for `language`, from the cache when it ran in the last ten
  minutes.

  ## Options

    * `:refresh` — run it again
    * `:schemas` — the blueprints to check (default `schemas/0`)
  """
  @spec run(String.t() | atom(), keyword()) :: Result.t()
  def run(language, opts \\ []) do
    language = to_string(language)
    schemas = Keyword.get_lazy(opts, :schemas, &schemas/0)
    key = {:seo_structured_data, language, schemas}

    case !opts[:refresh] && Brando.Cache.get(key) do
      %Result{} = cached ->
        cached

      _ ->
        result = check(language, schemas)
        Brando.Cache.put(key, result, @ttl)
        result
    end
  end

  @doc "Runs the check without the cache."
  @spec check(String.t(), [module()]) :: Result.t()
  def check(language, schemas) do
    started = System.monotonic_time(:millisecond)

    checked = Enum.flat_map(schemas, &check_schema(&1, language))

    rows =
      checked |> Enum.filter(&(&1.errors > 0 or &1.warnings > 0)) |> Enum.sort_by(&{-&1.errors, -&1.warnings, &1.title})

    %Result{
      language: language,
      checked: length(checked),
      with_errors: Enum.count(rows, &(&1.errors > 0)),
      with_warnings: Enum.count(rows, &(&1.errors == 0 and &1.warnings > 0)),
      rows: rows,
      checked_at: DateTime.utc_now(),
      duration_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp checkable?(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__has_absolute_url__, 0) and
      schema.__has_absolute_url__() and Graph.has_json_ld?(schema) and listable?(schema)
  end

  defp listable?(schema) do
    context = schema.__modules__().context
    Code.ensure_loaded?(context) and function_exported?(context, :"list_#{schema.__naming__().plural}", 1)
  end

  defp check_schema(schema, language) do
    sources = Inspector.sources(schema)

    schema
    |> entries(language)
    |> Enum.filter(&Brando.SEO.Audit.has_url?(schema, &1))
    |> Enum.map(&check_entry(schema, &1, language, sources))
  end

  defp entries(schema, language) do
    context = schema.__modules__().context
    plural = schema.__naming__().plural

    args = %{preload: Inspector.preloads(schema, blocks: false)}
    args = if schema.has_trait(Brando.Trait.Status), do: Map.put(args, :status, :published), else: args
    args = if schema.has_trait(Brando.Trait.Translatable), do: Map.put(args, :language, language), else: args

    case apply(context, :"list_#{plural}", [args]) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  defp check_entry(schema, entry, language, sources) do
    inspection = Inspector.build(schema, entry, language: language, sources: sources)
    issues = Inspector.entry_issues(inspection)
    main = Enum.find(inspection.nodes, &(&1.role == :main))

    %Row{
      schema: schema,
      id: entry.id,
      title: title(schema, entry),
      url: inspection.url,
      admin_url: admin_url(schema, entry.id),
      type: main && main.type,
      errors: Enum.count(issues, &(&1.level == :error)),
      warnings: Enum.count(issues, &(&1.level == :warning)),
      issues: issues
    }
  end

  # The entry's form, opened on its Structured data tab. `nil` for a blueprint
  # without an admin form.
  defp admin_url(schema, id) do
    schema.__admin_route__(:update, [id]) <> "#structured-data"
  rescue
    _ -> nil
  end

  defp title(schema, entry) do
    if schema.__has_identifier__(),
      do: entry |> schema.__identifier__(skip_cover: true) |> Map.get(:title),
      else: Map.get(entry, :title)
  rescue
    _ -> Map.get(entry, :title)
  end
end
