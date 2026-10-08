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

  The result counts the entries checked per content type (`per_schema`).
  `unchecked/0` lists the blueprints with a mapping that are left out, and
  why.

  The result is cached for ten minutes per language; `refresh: true` runs
  it again. A cached result from before `per_schema` existed is run again.
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
              per_schema: [],
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
    |> Enum.uniq()
    |> Enum.filter(&checkable?/1)
  end

  @typedoc """
  Why a blueprint with a JSON-LD mapping is not checked: it has no page of
  its own (`absolute_url`), its context module is not loaded, or the context
  has no `list_<plural>/1`.
  """
  @type skip_reason :: :no_page | :context_not_loaded | :no_list_function

  @doc "Blueprints with a `json_ld_schema` that are not checked, each with why."
  @spec unchecked() :: [{module(), skip_reason()}]
  def unchecked do
    :include_brando
    |> Brando.Blueprint.list_blueprints()
    |> Enum.uniq()
    |> Enum.filter(&Graph.has_json_ld?/1)
    |> Enum.flat_map(fn schema ->
      case skip_reason(schema) do
        nil -> []
        reason -> [{schema, reason}]
      end
    end)
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
      %Result{} = cached when is_map_key(cached, :per_schema) ->
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

    checked = Enum.map(schemas, &{&1, check_schema(&1, language)})
    per_schema = Enum.map(checked, fn {schema, rows} -> {schema, length(rows)} end)
    checked = Enum.flat_map(checked, &elem(&1, 1))

    rows =
      checked |> Enum.filter(&(&1.errors > 0 or &1.warnings > 0)) |> Enum.sort_by(&{-&1.errors, -&1.warnings, &1.title})

    %Result{
      language: language,
      checked: length(checked),
      per_schema: per_schema,
      with_errors: Enum.count(rows, &(&1.errors > 0)),
      with_warnings: Enum.count(rows, &(&1.errors == 0 and &1.warnings > 0)),
      rows: rows,
      checked_at: DateTime.utc_now(),
      duration_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp checkable?(schema), do: Graph.has_json_ld?(schema) and is_nil(skip_reason(schema))

  defp skip_reason(schema) do
    context = schema.__modules__().context

    cond do
      not (function_exported?(schema, :__has_absolute_url__, 0) and schema.__has_absolute_url__()) -> :no_page
      not Code.ensure_loaded?(context) -> :context_not_loaded
      not function_exported?(context, list_function(schema), 1) -> :no_list_function
      true -> nil
    end
  end

  @doc "The context function a blueprint's entries are read with, `list_<plural>`."
  @spec list_function(module()) :: atom()
  def list_function(schema), do: :"list_#{schema.__naming__().plural}"

  # Entries are read without relations, then loaded a page at a time with
  # everything their mapping may read (`Inspector.preloads/2`): one query per
  # relation per page, whatever the number of entries, and only a page of
  # them fully loaded at once.
  @page_size 250

  defp check_schema(schema, language) do
    sources = Inspector.sources(schema)
    preloads = Inspector.preloads(schema, blocks: false)

    schema
    |> entries(language)
    |> Enum.chunk_every(@page_size)
    |> Enum.flat_map(fn page ->
      case preload(page, preloads) do
        {:ok, page} ->
          page
          |> Enum.filter(&has_url?(schema, &1))
          |> Enum.map(&check_entry(schema, &1, language, sources))

        {:error, reason} ->
          Enum.map(page, &failed_row(schema, &1, reason))
      end
    end)
  end

  defp preload(page, preloads) do
    {:ok, Brando.Repo.preload(page, preloads)}
  rescue
    exception -> {:error, exception |> Exception.message() |> String.split("\n", trim: true) |> List.first("")}
  end

  defp entries(schema, language) do
    context = schema.__modules__().context

    args = %{}
    args = if schema.has_trait(Brando.Trait.Status), do: Map.put(args, :status, :published), else: args
    args = if schema.has_trait(Brando.Trait.Translatable), do: Map.put(args, :language, language), else: args

    case apply(context, list_function(schema), [args]) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  # An entry whose graph can't be built (the site's mapping raises for it) is
  # that entry's error, with a link to it; the rest of the site is still
  # checked.
  defp check_entry(schema, entry, language, sources) do
    case Inspector.safe_build(schema, entry, language: language, sources: sources) do
      {:ok, inspection} -> entry_row(schema, entry, inspection)
      {:error, {:build_failed, reason}} -> failed_row(schema, entry, reason)
    end
  end

  defp failed_row(schema, entry, reason) do
    %Row{
      schema: schema,
      id: entry.id,
      title: title(schema, entry),
      url: safe_path(schema, entry),
      admin_url: admin_url(schema, entry.id),
      errors: 1,
      issues: [%{level: :error, kind: :build_failed, property: nil, reason: reason}]
    }
  end

  defp entry_row(schema, entry, inspection) do
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

  # An entry whose URL can't be worked out is checked, and fails there with
  # the reason, rather than taking the check down here.
  defp has_url?(schema, entry) do
    Brando.SEO.Audit.has_url?(schema, entry)
  rescue
    _ -> true
  end

  defp safe_path(schema, entry) do
    Graph.path(schema, entry)
  rescue
    _ -> nil
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
