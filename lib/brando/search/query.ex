defmodule Brando.Search.Query do
  @moduledoc """
  Searches the index (`Brando.Search`).

  `run/3` takes a base query on `Brando.Search.Document` that already holds
  only what the reader may see (the admin passes it through
  `Brando.Authorization.Boundary.identifiers/1`), the text typed, and
  filters. The text never becomes SQL: it is a parameter of
  `websearch_to_tsquery/2` when it uses web search syntax (quotes, `or`, a
  leading `-`), and otherwise its words, letters and digits only, become a
  prefix query (`word:*`), so results come while a word is half typed. A
  single letter is matched as a whole word rather than as a prefix.

  Each document is matched with the query parsed by its own text search
  configuration. Results are ranked: an exact title, then titles starting
  with the text, then by `ts_rank_cd`; then published before pending, draft
  and disabled entries, then the most recently updated.
  """
  import Ecto.Query

  alias Brando.Repo
  alias Brando.Search.Document
  alias Brando.Search.Highlight

  @max_words 8
  # The first part of the body the snippet is taken from
  @headline_bytes 60_000
  @headline_options "StartSel=#{Highlight.start_marker()}, StopSel=#{Highlight.stop_marker()}, " <>
                      "MaxWords=28, MinWords=10, ShortWord=2, MaxFragments=2, FragmentDelimiter=\" … \""

  @type parsed :: {:prefix | :websearch, String.t()} | :empty
  @type result :: %{rows: [map()], total: non_neg_integer(), facets: %{module() => non_neg_integer()}}

  @doc """
  How the text is searched: `{:websearch, text}`, `{:prefix, tsquery}` built
  from its words, or `:empty` when it has nothing to search for.
  """
  @spec parse(String.t() | nil) :: parsed()
  def parse(text) do
    text = String.trim(text || "")

    cond do
      text == "" ->
        :empty

      Regex.match?(~r/"|(^|\s)-[\p{L}\p{N}]|\sor\s/iu, text) ->
        {:websearch, String.slice(text, 0, 200)}

      true ->
        case words(text) do
          [] -> :empty
          words -> {:prefix, Enum.map_join(words, " & ", &prefix/1)}
        end
    end
  end

  # A one-letter prefix would match most of the index, so a single letter is
  # matched as a whole word.
  defp prefix(word), do: if(String.length(word) > 1, do: word <> ":*", else: word)

  # Letters and digits only; one-letter words add little but cost much, so
  # they count only when they are all there is.
  defp words(text) do
    words = ~r/[\p{L}\p{N}]+/u |> Regex.scan(String.downcase(text)) |> List.flatten()
    long = Enum.filter(words, &(String.length(&1) > 1))
    if(long == [], do: words, else: long) |> Enum.uniq() |> Enum.take(@max_words)
  end

  @doc """
  Searches `base` for `text`.

  Options:

    * `:schemas` — only these content types (the type filter)
    * `:language` — only documents in this language
    * `:status` — only entries with this status (an atom)
    * `:sort` — `:relevance` (default) or `:updated`
    * `:limit` and `:offset` — the page

  Returns the page's rows (documents with `:snippet`, a list of
  `Brando.Search.Highlight` segments), the total and the number of matches
  per content type (`:facets`, before the type filter).
  """
  @spec run(Ecto.Queryable.t(), String.t() | nil, keyword()) :: result()
  def run(base, text, opts \\ []) do
    case parse(text) do
      :empty -> %{rows: [], total: 0, facets: %{}}
      parsed -> run_parsed(base, String.trim(text), parsed, opts)
    end
  end

  defp run_parsed(base, text, parsed, opts) do
    matches = base |> where(^matches(parsed)) |> filter(:language, opts[:language]) |> filter(:status, opts[:status])

    facets =
      from(d in matches, group_by: d.schema, select: {d.schema, count(d.id)})
      |> Repo.all()
      |> Map.new()

    matches = filter(matches, :schemas, opts[:schemas])

    total =
      facets
      |> Enum.filter(fn {schema, _} -> in_types?(schema, opts[:schemas]) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    rows =
      if total == 0,
        do: [],
        else: page(matches, text, parsed, opts)

    %{rows: rows, total: total, facets: facets}
  end

  defp in_types?(_schema, nil), do: true
  defp in_types?(schema, schemas), do: schema in schemas

  defp filter(query, _key, nil), do: query
  defp filter(query, :language, language), do: where(query, [d], d.language == ^to_string(language))
  defp filter(query, :status, status), do: where(query, [d], d.status == ^status)
  defp filter(query, :schemas, schemas), do: where(query, [d], d.schema in ^schemas)

  defp page(matches, text, parsed, opts) do
    ids =
      matches
      |> order(text, parsed, Keyword.get(opts, :sort, :relevance))
      |> limit(^Keyword.get(opts, :limit, 20))
      |> offset(^Keyword.get(opts, :offset, 0))
      |> select([d], d.id)
      |> Repo.all()

    documents =
      from(d in Document, where: d.id in ^ids)
      |> select(^%{document: dynamic([d], d), snippet: headline(parsed)})
      |> Repo.all()
      |> Map.new(&{&1.document.id, &1})

    Enum.flat_map(ids, fn id ->
      case documents[id] do
        nil -> []
        %{document: document, snippet: snippet} -> [Map.put(document, :snippet, Highlight.segments(snippet))]
      end
    end)
  end

  defp order(query, _text, _parsed, :updated) do
    order_by(query, [d], desc_nulls_last: d.updated_at, desc: d.id)
  end

  defp order(query, text, parsed, _relevance) do
    title = String.downcase(text)
    prefix = escape_like(title) <> "%"

    title_rank =
      dynamic(
        [d],
        fragment(
          "CASE WHEN lower(?) = ? THEN 0 WHEN lower(?) LIKE ? THEN 1 ELSE 2 END",
          d.title,
          ^title,
          d.title,
          ^prefix
        )
      )

    # published, pending, draft, disabled; entries without a status are live
    status = dynamic([d], fragment("CASE ? WHEN 0 THEN 2 WHEN 2 THEN 1 WHEN 3 THEN 3 ELSE 0 END", d.status))

    order_by(
      query,
      ^[
        asc: title_rank,
        desc: rank(parsed),
        asc: status,
        desc_nulls_last: dynamic([d], d.updated_at),
        desc: dynamic([d], d.id)
      ]
    )
  end

  defp escape_like(text), do: String.replace(text, ["\\", "%", "_"], &("\\" <> &1))

  # Each document against the query in its own configuration. Written out
  # per configuration, so every branch can use the GIN index.
  defp matches({:prefix, q}) do
    dynamic(
      [d],
      (d.config == "norwegian" and fragment("? @@ to_tsquery('norwegian', ?)", d.document, ^q)) or
        (d.config == "english" and fragment("? @@ to_tsquery('english', ?)", d.document, ^q)) or
        (d.config == "simple" and fragment("? @@ to_tsquery('simple', ?)", d.document, ^q))
    )
  end

  defp matches({:websearch, q}) do
    dynamic(
      [d],
      (d.config == "norwegian" and fragment("? @@ websearch_to_tsquery('norwegian', ?)", d.document, ^q)) or
        (d.config == "english" and fragment("? @@ websearch_to_tsquery('english', ?)", d.document, ^q)) or
        (d.config == "simple" and fragment("? @@ websearch_to_tsquery('simple', ?)", d.document, ^q))
    )
  end

  defp rank({:prefix, q}) do
    dynamic(
      [d],
      fragment(
        "ts_rank_cd(?, CASE ? WHEN 'norwegian' THEN to_tsquery('norwegian', ?) WHEN 'english' THEN to_tsquery('english', ?) ELSE to_tsquery('simple', ?) END)",
        d.document,
        d.config,
        ^q,
        ^q,
        ^q
      )
    )
  end

  defp rank({:websearch, q}) do
    dynamic(
      [d],
      fragment(
        "ts_rank_cd(?, CASE ? WHEN 'norwegian' THEN websearch_to_tsquery('norwegian', ?) WHEN 'english' THEN websearch_to_tsquery('english', ?) ELSE websearch_to_tsquery('simple', ?) END)",
        d.document,
        d.config,
        ^q,
        ^q,
        ^q
      )
    )
  end

  # A snippet of the body (or the meta description when there is no body)
  # with the matches between markers; `Brando.Search.Highlight` turns it into
  # escaped text and marks.
  defp headline({:prefix, q}) do
    dynamic(
      [d],
      fragment(
        "ts_headline(?::regconfig, left(coalesce(nullif(?, ''), ?, ''), ?), CASE ? WHEN 'norwegian' THEN to_tsquery('norwegian', ?) WHEN 'english' THEN to_tsquery('english', ?) ELSE to_tsquery('simple', ?) END, ?)",
        d.config,
        d.body,
        d.description,
        ^@headline_bytes,
        d.config,
        ^q,
        ^q,
        ^q,
        ^@headline_options
      )
    )
  end

  defp headline({:websearch, q}) do
    dynamic(
      [d],
      fragment(
        "ts_headline(?::regconfig, left(coalesce(nullif(?, ''), ?, ''), ?), CASE ? WHEN 'norwegian' THEN websearch_to_tsquery('norwegian', ?) WHEN 'english' THEN websearch_to_tsquery('english', ?) ELSE websearch_to_tsquery('simple', ?) END, ?)",
        d.config,
        d.body,
        d.description,
        ^@headline_bytes,
        d.config,
        ^q,
        ^q,
        ^q,
        ^@headline_options
      )
    )
  end
end
