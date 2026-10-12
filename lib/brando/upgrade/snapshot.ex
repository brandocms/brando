defmodule Brando.Upgrade.Snapshot do
  @moduledoc """
  Snapshots of a site's public responses, for comparing a site before and
  after an upgrade (`mix brando.upgrade.snapshot`).

  A snapshot is a directory holding one file per response body and
  `index.tsv`: a `#base_url` line, then one line per URL: path, status code,
  content type, `location` header and body file, separated by tabs.
  `capture/3` writes one, `read/1` reads it back, and `compare/3` diffs two
  of them URL by URL with `Brando.Upgrade.Snapshot.Diff`.

  `read/1` makes the base URL root-relative in bodies and redirects, so the
  site before and after can run on different ports.

  Capturing only needs the paths and a base URL, so a snapshot of the site
  before the upgrade can be taken from the upgraded code against the old site
  running elsewhere.
  """

  alias Brando.Upgrade.Snapshot.Diff

  @index "index.tsv"

  @type page :: %{
          path: String.t(),
          status: non_neg_integer() | nil,
          content_type: String.t() | nil,
          location: String.t() | nil,
          body: String.t()
        }

  @doc """
  The paths in a URL list: one per line, starting with `/` (or a full
  `http(s)://` URL); blank lines, `#` comments and anything else are skipped,
  so stray output in a redirected `urls` run does no harm.
  """
  @spec read_urls(Path.t()) :: [String.t()]
  def read_urls(file) do
    file
    |> File.read!()
    |> String.split(~r/\R/)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.starts_with?(&1, "/") or String.match?(&1, ~r{^https?://})))
    |> Enum.uniq()
  end

  @doc """
  Fetches `paths` from `:base_url` and writes the snapshot to `dir`, which
  is created, or emptied of an earlier snapshot. Redirects are recorded, not
  followed. Returns the pages without their bodies, in the order given.

  ## Options

    * `:base_url` — required, e.g. `http://localhost:4000`
    * `:concurrency` — requests at a time (default 4)
    * `:req_options` — passed on to `Req.request/1` (tests use `plug:`)
  """
  @spec capture([String.t()], Path.t(), keyword()) :: [page()]
  def capture(paths, dir, opts) do
    base_url = opts |> Keyword.fetch!(:base_url) |> String.trim_trailing("/")
    req_options = Keyword.get(opts, :req_options, [])

    File.mkdir_p!(dir)
    clear(dir)

    pages =
      paths
      |> Task.async_stream(&fetch(&1, base_url, req_options),
        max_concurrency: Keyword.get(opts, :concurrency, 4),
        timeout: :infinity,
        ordered: true
      )
      |> Enum.map(fn {:ok, page} -> page end)

    {pages, _names} =
      Enum.map_reduce(pages, MapSet.new(), fn page, names ->
        file = file_name(page.path, names)
        File.write!(Path.join(dir, file), page.body)
        {Map.put(page, :file, file), MapSet.put(names, file)}
      end)

    File.write!(Path.join(dir, @index), ["#base_url\t", base_url, "\n" | Enum.map(pages, &index_line/1)])
    Enum.map(pages, &Map.delete(&1, :body))
  end

  defp clear(dir) do
    case File.read(Path.join(dir, @index)) do
      {:ok, index} ->
        index |> parse_index() |> Enum.each(&File.rm(Path.join(dir, &1.file)))
        File.rm(Path.join(dir, @index))

      {:error, _} ->
        :ok
    end
  end

  defp fetch(path, base_url, req_options) do
    url = if String.starts_with?(path, "/"), do: base_url <> encode(path), else: path

    options =
      Keyword.merge(
        [url: url, redirect: false, retry: false, decode_body: false, receive_timeout: 60_000],
        req_options
      )

    case Req.request(options) do
      {:ok, response} ->
        %{
          path: path,
          status: response.status,
          content_type: header(response, "content-type"),
          location: header(response, "location"),
          body: IO.iodata_to_binary(response.body)
        }

      {:error, exception} ->
        %{path: path, status: nil, content_type: nil, location: nil, body: Exception.message(exception)}
    end
  end

  # A list may hold paths as the browser shows them (`/no/kjøpsvilkår`) or
  # already encoded; decoding first keeps `%` from being encoded twice.
  defp encode(path), do: path |> URI.decode() |> URI.encode()

  defp header(response, name) do
    case Req.Response.get_header(response, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  # `/no/meny` is `no__meny.html`; a name already taken gets a number.
  defp file_name(path, taken) do
    base =
      path
      |> String.replace(~r{^https?://}, "")
      |> String.trim("/")
      |> String.replace("/", "__")
      |> String.replace(~r/[^\p{L}\p{N}._-]+/u, "_")
      |> String.slice(0, 120)
      |> case do
        "" -> "ROOT"
        name -> name
      end

    [base <> ".html" | Enum.map(2..10_000, &"#{base}-#{&1}.html")]
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp index_line(page) do
    [page.path, to_string(page.status), page.content_type || "", page.location || "", page.file]
    |> Enum.map_join("\t", &String.replace(&1, ~r/[\t\r\n]/, " "))
    |> Kernel.<>("\n")
  end

  @doc """
  Reads the snapshot in `dir`: its pages, in the order captured, with the
  base URL they were captured from removed from bodies and redirects.
  """
  @spec read(Path.t()) :: [page()]
  def read(dir) do
    index = Path.join(dir, @index)

    if !File.exists?(index) do
      raise ArgumentError,
            "#{dir} holds no snapshot (no #{@index}); capture one with `mix brando.upgrade.snapshot capture`"
    end

    index = File.read!(index)
    base_url = base_url(index)

    index
    |> parse_index()
    |> Enum.map(fn entry ->
      body =
        case File.read(Path.join(dir, entry.file)) do
          {:ok, body} -> body
          {:error, _} -> ""
        end

      %{entry | location: relative(entry.location, base_url)}
      |> Map.delete(:file)
      |> Map.put(:body, relative(body, base_url))
    end)
  end

  defp base_url(index) do
    case Regex.run(~r/^#base_url\t(.+)$/m, index) do
      [_, base_url] -> base_url
      nil -> nil
    end
  end

  defp relative(nil, _base_url), do: nil
  defp relative(text, nil), do: text

  defp relative(text, base_url) do
    case text do
      ^base_url -> "/"
      text -> String.replace(text, base_url <> "/", "/")
    end
  end

  defp parse_index(index) do
    index
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      [path, status, content_type, location, file] = String.split(line, "\t")

      %{
        path: path,
        status: if(status == "", do: nil, else: String.to_integer(status)),
        content_type: blank_to_nil(content_type),
        location: blank_to_nil(location),
        file: file
      }
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc """
  Compares two snapshots URL by URL, in the order of `before`, then the URLs
  only `after` has: `{path, layers}`, where `layers` is `[]` for an identical
  response, a list of `Brando.Upgrade.Snapshot.Diff.compare/3` layers, or
  `:only_before` / `:only_after`.
  """
  @spec compare([page()], [page()], keyword()) :: [{String.t(), list() | :only_before | :only_after}]
  def compare(before, after_pages, opts \\ []) do
    after_by_path = Map.new(after_pages, &{&1.path, &1})
    before_paths = MapSet.new(before, & &1.path)

    compared =
      Enum.map(before, fn page ->
        case Map.fetch(after_by_path, page.path) do
          {:ok, other} -> {page.path, Diff.compare(page, other, opts)}
          :error -> {page.path, :only_before}
        end
      end)

    only_after =
      for page <- after_pages, not MapSet.member?(before_paths, page.path), do: {page.path, :only_after}

    compared ++ only_after
  end

  @doc """
  The report `mix brando.upgrade.snapshot diff` prints: each URL that differs
  with its layers, at most `:limit` lines each (default 10), then a summary.
  Head changes that every URL with a head change shares (a dropped font
  query string, a new meta tag in the layout) are listed once, first, and
  left out of each URL.
  """
  @spec report([{String.t(), term()}], keyword()) :: String.t()
  def report(results, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    {shared, results_shown} = hoist_shared_head(results)

    shared_section =
      if shared == [],
        do: [],
        else: [
          [
            "Every URL with a head change (#{shared_count(results)}) has these:\n",
            layer_report(%{layer: :head, summary: head_summary(shared), lines: shared}, limit)
          ]
        ]

    sections =
      results_shown
      |> Enum.reject(fn {_path, layers} -> layers == [] end)
      |> Enum.map(fn
        {path, :only_before} -> "#{path}\n  only in the first snapshot\n"
        {path, :only_after} -> "#{path}\n  only in the second snapshot\n"
        {path, layers} -> [path, "\n", Enum.map(layers, &layer_report(&1, limit))]
      end)

    sections = shared_section ++ sections

    IO.iodata_to_binary([Enum.intersperse(sections, "\n"), if(sections == [], do: "", else: "\n"), summary(results)])
  end

  defp head_layers(results) do
    for {_path, layers} <- results, is_list(layers), %{layer: :head} = head <- layers, do: head
  end

  defp shared_count(results), do: results |> head_layers() |> length()

  defp hoist_shared_head(results) do
    shared =
      case head_layers(results) do
        [_, _ | _] = heads -> heads |> Enum.map(&MapSet.new(&1.lines)) |> Enum.reduce(&MapSet.intersection/2)
        _ -> MapSet.new()
      end

    if MapSet.size(shared) == 0 do
      {[], results}
    else
      {Enum.sort_by(shared, &head_line_order/1), Enum.map(results, &drop_shared_head(&1, shared))}
    end
  end

  # Removed lines before added ones, as in a layer.
  defp head_line_order("- " <> line), do: {0, line}
  defp head_line_order(line), do: {1, line}

  defp drop_shared_head({path, layers}, shared) when is_list(layers) do
    layers =
      Enum.flat_map(layers, fn
        %{layer: :head, lines: lines} = head ->
          case Enum.reject(lines, &MapSet.member?(shared, &1)) do
            [] -> []
            rest -> [%{head | lines: rest, summary: head_summary(rest)}]
          end

        layer ->
          [layer]
      end)

    # Shared head lines were a difference, so the URL still differs.
    {path, if(layers == [], do: [%{layer: :head, summary: "only the shared head changes", lines: []}], else: layers)}
  end

  defp drop_shared_head(result, _shared), do: result

  defp head_summary(lines) do
    removed = Enum.count(lines, &String.starts_with?(&1, "- "))
    "-#{removed} +#{length(lines) - removed}"
  end

  defp layer_report(%{layer: layer, summary: summary, lines: lines}, limit) do
    shown = Enum.take(lines, limit)
    more = length(lines) - length(shown)

    [
      "  ",
      String.pad_trailing(to_string(layer), 10),
      summary,
      "\n",
      Enum.map(shown, &["    ", truncate(&1), "\n"]),
      if(more > 0, do: "    … #{more} more\n", else: "")
    ]
  end

  defp truncate(line) do
    if String.length(line) > 200, do: String.slice(line, 0, 199) <> "…", else: line
  end

  defp summary(results) do
    total = length(results)
    same = Enum.count(results, fn {_path, layers} -> layers == [] end)
    only = Enum.count(results, fn {_path, layers} -> layers in [:only_before, :only_after] end)

    counts =
      for layer <- Diff.layers(),
          count =
            Enum.count(results, fn {_path, layers} -> is_list(layers) and Enum.any?(layers, &(&1.layer == layer)) end),
          count > 0,
          do: "#{layer} #{count}"

    differ = total - same - only
    detail = if counts == [], do: "", else: " (#{Enum.join(counts, ", ")})"
    only_text = if only > 0, do: ", #{only} in one snapshot only", else: ""

    "#{total} URLs: #{same} identical, #{differ} differ#{detail}#{only_text}\n"
  end
end
