defmodule Brando.SEO.Audit do
  @moduledoc """
  Audits published entries for the basics search engines and social cards
  need: a meta title and description of sensible length, an image, a URL,
  and no copy shared with another entry. Recorded 404s are matched against
  the audited URLs to suggest redirects for moved pages.

  Runs on demand, per content language, over every blueprint that both has
  an `absolute_url` and carries `Brando.Trait.Meta`. Rows come from one
  read per schema that leaves the rendered block HTML out, with the title and
  URL taken from the blueprint's own identifier and `absolute_url` templates.
  Body text, headings and images are measured by the database
  (`Brando.SEO.ContentStats`), so the rendered HTML never leaves it.
  Blueprints may add their own checks through `__seo_checks__/1`.
  """

  alias Brando.SEO.Check
  alias Brando.SEO.Checks
  alias Brando.SEO.ContentStats

  defmodule Row do
    @moduledoc "One audited entry: what the checks look at, plus their verdict."
    @type t :: %__MODULE__{}
    defstruct schema: nil,
              id: nil,
              title: nil,
              url: nil,
              language: nil,
              status: nil,
              cover: nil,
              meta_title: nil,
              meta_description: nil,
              has_meta_image: false,
              edited_at: nil,
              word_count: nil,
              headings: nil,
              image_alts: nil,
              alternates: [],
              traffic: nil,
              checks: [],
              score: nil
  end

  defmodule Result do
    @moduledoc "The audit for one language and a set of schemas."
    @type t :: %__MODULE__{}
    defstruct language: nil,
              schemas: [],
              rows: [],
              score: nil,
              drafts: 0,
              duplicate_titles: [],
              duplicate_descriptions: [],
              missing_descriptions: 0,
              missing_images: 0,
              missing_urls: 0,
              thin_content: 0,
              sitemap?: false,
              redirect_suggestions: []
  end

  @doc "Blueprints the audit can cover: an `absolute_url` and the meta trait."
  @spec schemas() :: [module()]
  def schemas do
    :include_brando
    |> Brando.Blueprint.list_blueprints()
    |> Enum.reject(&(&1 == Brando.Pages.Fragment))
    |> Enum.filter(&auditable?/1)
  end

  @doc """
  Audits `schemas` (default: every auditable blueprint) in `language`.

  ## Options

    * `:schemas` — the blueprints to include
    * `:include_drafts` — audit unpublished entries too (default `false`)
  """
  @spec run(String.t() | atom(), keyword()) :: Result.t()
  def run(language, opts \\ []) do
    language = to_string(language)
    schemas = Keyword.get(opts, :schemas, schemas())
    include_drafts? = Keyword.get(opts, :include_drafts, false)

    {rows, drafts} =
      schemas
      |> Enum.flat_map(&rows_for(&1, language))
      |> Enum.split_with(&(include_drafts? or &1.status == :published))

    sitemap = sitemap_paths()
    ctx = context(rows, language, sitemap)

    rows =
      rows
      |> with_content_stats()
      |> Enum.map(&score_row(&1, ctx))
      |> Enum.sort_by(&{&1.score || 0, String.downcase(&1.title || "")})

    %Result{
      language: language,
      schemas: schemas,
      rows: rows,
      score: aggregate(rows),
      drafts: length(drafts),
      duplicate_titles: duplicates(rows, :meta_title),
      duplicate_descriptions: duplicates(rows, :meta_description),
      missing_descriptions: count_failing(rows, :meta_description_present),
      missing_images: count_failing(rows, :meta_image),
      missing_urls: count_failing(rows, :url_resolves),
      thin_content: count_failing(rows, :thin_content, [:warn, :fail]),
      sitemap?: sitemap != nil,
      redirect_suggestions: Brando.SEO.RedirectSuggestions.suggest(Brando.Sites.FourOhFour.list(), rows, language)
    }
  end

  @doc "Reads the generated sitemap files and returns the set of paths, or `nil` when none exist."
  @spec sitemap_paths() :: MapSet.t() | nil
  def sitemap_paths do
    dir = Path.join(Brando.Tenant.Storage.current_media_root(), "sitemaps")

    files = Path.wildcard(Path.join(dir, "*.xml")) ++ Path.wildcard(Path.join(dir, "*.xml.gz"))

    case files do
      [] ->
        nil

      files ->
        files
        |> Enum.flat_map(&locs/1)
        |> Enum.map(&(URI.parse(&1).path || "/"))
        |> MapSet.new()
    end
  rescue
    _ -> nil
  end

  # `function_exported?/3` is false for a module that has not been loaded yet,
  # which outside the test environment is most of them on first use.
  defp auditable?(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__has_absolute_url__, 0) and
      schema.__has_absolute_url__() and schema.has_trait(Brando.Trait.Meta)
  end

  # One narrow read per schema: every column except the rendered block HTML,
  # plus the preloads the blueprint's own URL and identifier templates need.
  # Rows are built from the entries themselves rather than the identifier
  # table, so content inserted without identifiers (seeds, imports) still
  # shows up and the URL is whatever `absolute_url` says today.
  defp rows_for(schema, language) do
    schema
    |> entries(language)
    |> Enum.map(&row(schema, &1))
  end

  defp entries(schema, language) do
    context = schema.__modules__().context
    plural = schema.__naming__().plural
    fields = schema.__schema__(:fields) |> Enum.reject(&rendered_field?/1)
    preloads = Enum.uniq(schema.__absolute_url_preloads__() ++ identifier_preloads(schema))

    args = %{select: {:struct, fields}, preload: preloads}
    args = if schema.has_trait(Brando.Trait.Translatable), do: Map.put(args, :language, language), else: args

    case apply(context, :"list_#{plural}", [args]) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  defp row(schema, entry) do
    %Row{
      schema: schema,
      id: entry.id,
      title: title(schema, entry),
      url: url(schema, entry),
      language: entry |> Map.get(:language) |> then(&(&1 && to_string(&1))),
      status: Map.get(entry, :status, :published),
      cover: cover(schema, entry),
      meta_title: Map.get(entry, :meta_title),
      meta_description: Map.get(entry, :meta_description),
      has_meta_image: not is_nil(Map.get(entry, :meta_image_id)),
      edited_at: ContentStats.edited_at(entry)
    }
  end

  defp title(schema, entry) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__has_identifier__, 0) and
         schema.__has_identifier__() do
      entry |> schema.__identifier__(skip_cover: true) |> Map.get(:title)
    else
      Map.get(entry, :title) || Map.get(entry, :name) || "##{entry.id}"
    end
  rescue
    _ -> Map.get(entry, :title) || Map.get(entry, :name) || "##{entry.id}"
  end

  defp url(schema, entry) do
    case schema.__absolute_url__(entry) do
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Any image asset other than the meta image counts as a cover for sharing.
  defp cover(schema, entry) do
    schema
    |> Brando.Blueprint.Assets.__assets__()
    |> Enum.filter(&(&1.type == :image and &1.name != :meta_image))
    |> Enum.find_value(fn asset -> Map.get(entry, :"#{asset.name}_id") end)
  end

  defp identifier_preloads(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__identifier_preloads__, 0),
      do: schema.__identifier_preloads__(),
      else: []
  end

  defp rendered_field?(field), do: field |> Atom.to_string() |> String.starts_with?("rendered_")

  defp context(rows, language, sitemap) do
    seo = Brando.Cache.SEO.get(language)

    %{
      fallback_title: Map.get(seo, :fallback_meta_title),
      fallback_description: Map.get(seo, :fallback_meta_description),
      title_counts: counts(rows, :meta_title),
      description_counts: counts(rows, :meta_description),
      sitemap: sitemap,
      thin_content_words: Checks.thin_content_words()
    }
  end

  defp counts(rows, field) do
    rows
    |> Enum.map(&Checks.normalize(Map.get(&1, field)))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp score_row(row, ctx) do
    checks = Checks.run(row, ctx) ++ custom_checks(row)
    %{row | checks: checks, score: Check.score(checks)}
  end

  defp custom_checks(%Row{schema: schema} = row) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__seo_checks__, 1) do
      row |> schema.__seo_checks__() |> Enum.filter(&match?(%Check{}, &1))
    else
      []
    end
  rescue
    _ -> []
  end

  defp aggregate([]), do: nil

  defp aggregate(rows) do
    scores = rows |> Enum.map(& &1.score) |> Enum.reject(&is_nil/1)
    if scores == [], do: nil, else: round(Enum.sum(scores) / length(scores))
  end

  defp duplicates(rows, field) do
    rows
    |> Enum.group_by(&Checks.normalize(Map.get(&1, field)))
    |> Enum.reject(fn {key, group} -> is_nil(key) or length(group) < 2 end)
    |> Enum.map(fn {_key, group} -> {Map.get(hd(group), field), group} end)
    |> Enum.sort_by(fn {_value, group} -> -length(group) end)
  end

  defp count_failing(rows, key, statuses \\ [:fail]) do
    Enum.count(rows, fn row -> Enum.any?(row.checks, &(&1.key == key and &1.status in statuses)) end)
  end

  # Two queries per schema over the audited ids: the entries' own block
  # HTML, and that of their published language versions. Schemas without
  # block fields keep `nil`, which the content checks skip.
  defp with_content_stats(rows) do
    by_schema = Enum.group_by(rows, & &1.schema, & &1.id)

    stats =
      Map.new(by_schema, fn {schema, ids} ->
        {schema, {ContentStats.for_ids(schema, ids), ContentStats.alternates(schema, ids)}}
      end)

    Enum.map(rows, fn row ->
      {own, alternates} = Map.fetch!(stats, row.schema)

      case Map.get(own, row.id) do
        nil ->
          %{row | alternates: Map.get(alternates, row.id, [])}

        %ContentStats{} = content ->
          %{
            row
            | word_count: content.words,
              headings: content.headings,
              image_alts: content.image_alts,
              alternates: Map.get(alternates, row.id, [])
          }
      end
    end)
  end

  defp locs(file) do
    content = File.read!(file)
    content = if String.ends_with?(file, ".gz"), do: :zlib.gunzip(content), else: content

    ~r/<loc>\s*([^<\s]+)\s*<\/loc>/
    |> Regex.scan(content)
    |> Enum.map(fn [_, loc] -> loc end)
  rescue
    _ -> []
  end
end
