defmodule Mix.Tasks.Brando.Upgrade.Snapshot do
  use Mix.Task

  alias Brando.Upgrade.Snapshot

  @shortdoc "Captures a site's public pages before and after an upgrade, and diffs them"

  @moduledoc """
  Captures a site's public responses and compares two captures, to find what
  an upgrade changed on the public pages.

      mix brando.upgrade.snapshot urls [--output FILE] [--base-url OLD_SITE_URL]
      mix brando.upgrade.snapshot capture DIR --base-url URL [--urls FILE] [--concurrency N]
      mix brando.upgrade.snapshot diff BEFORE AFTER [--limit N] [--layers LAYERS]

  `urls` prints the default URL set, read from this application's database
  (`Brando.Upgrade.Snapshot.URLs`): `/`, every published page in every
  language, one published entry per language for every other Blueprint with
  an `absolute_url` (the one with the most blocks), a missing path per
  language for the 404 page, `/robots.txt` and `/sitemap.xml`. Edit the list
  freely: one path per line; lines that do not start with `/` or `http` are
  ignored.

  With `--base-url`, the old site's address, `urls` asks the old site for
  each entry URL and leaves out those it answers with 404 (a language whose
  routes are switched off, say), trying the next-heaviest entry of the
  Blueprint instead, and says what it left out. Without it, nothing is
  checked: the database alone can't tell which URLs the old site serves.

  `capture` fetches every URL from `--base-url` and saves each response's
  status, content type, `location` and body under `DIR`. With `--urls` it
  needs nothing but the list and the running site; without it, it reads the
  URL set from the database first, as `urls` does.

  `diff` compares two captures URL by URL and prints each URL that differs,
  one block per layer (see `Brando.Upgrade.Snapshot.Diff`):

    * `status` — the status code, and where a redirect points
    * `text` — the visible text, in order, with images' `alt`
    * `head` — the `<head>`'s meta, link, title and JSON-LD tags as a set
    * `structure` — each element's tag, classes and `data-*` attribute
      names, in order, so a `data-src` that moved to another element shows

  `--limit` sets how many lines each layer shows (default 10), `--layers`
  which layers to compare (`text,structure`). It ends with a count of
  identical and differing URLs.

  ## Before and after an upgrade

  The old site runs old Brando, which has no such task, so capture it from
  the upgraded code:

    1. Keep the old site running from a checkout of the commit before the
       upgrade, on a copy of the database, e.g. on port 4000.
    2. In the upgraded application, once its database is migrated, write the
       URL list:
       `mix brando.upgrade.snapshot urls --output urls.txt --base-url http://localhost:4000`.
       Add the entries you know are heavy or unusual to it.
    3. Capture the old site:
       `mix brando.upgrade.snapshot capture tmp/before --base-url http://localhost:4000 --urls urls.txt`.
    4. Start the upgraded site (e.g. `PORT=4001 mix phx.server`) and capture
       it: `mix brando.upgrade.snapshot capture tmp/after --base-url http://localhost:4001 --urls urls.txt`.
    5. `mix brando.upgrade.snapshot diff tmp/before tmp/after`.

  Capture both sides with the same list, and capture again after each fix to
  diff once more. Entries saved in the admin in between change their pages'
  text; the old site's database copy should be the one the upgraded site was
  migrated from.
  """

  @switches [
    base_url: :string,
    urls: :string,
    output: :string,
    concurrency: :integer,
    limit: :integer,
    layers: :string
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid != [] do
      Mix.raise("Unknown options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end

    case args do
      ["urls"] -> urls(opts)
      ["capture", dir] -> capture(dir, opts)
      ["diff", before_dir, after_dir] -> diff(before_dir, after_dir, opts)
      _ -> Mix.raise("Usage:\n\n" <> usage())
    end
  end

  defp usage do
    """
        mix brando.upgrade.snapshot urls [--output FILE] [--base-url OLD_SITE_URL]
        mix brando.upgrade.snapshot capture DIR --base-url URL [--urls FILE] [--concurrency N]
        mix brando.upgrade.snapshot diff BEFORE AFTER [--limit N] [--layers status,text,head,structure]
    """
  end

  defp urls(opts) do
    paths = database_urls(found_on_old_site(opts[:base_url]))

    case opts[:output] do
      nil ->
        Enum.each(paths, &Mix.shell().info(&1))

      file ->
        File.write!(file, Enum.map(paths, &[&1, "\n"]))
        Mix.shell().info("Wrote #{length(paths)} URLs to #{file}")
    end
  end

  # Logging off, so `urls > urls.txt` holds only the paths. The application
  # starts without its endpoint and with Oban's queues stopped: this runs
  # against a migrated copy of production, maybe beside the old site.
  defp database_urls(found? \\ fn _path -> true end) do
    Application.put_env(:logger, :level, :error)
    Logger.configure(level: :error)
    Mix.Brando.start_quietly()

    {paths, warnings} = Snapshot.URLs.list(found?: found?)
    Enum.each(warnings, &Mix.shell().error("Left out #{&1}"))
    paths
  end

  defp found_on_old_site(nil), do: fn _path -> true end

  defp found_on_old_site(base_url) do
    {:ok, _} = Application.ensure_all_started(:req)

    if is_nil(Snapshot.status("/", base_url)),
      do: Mix.raise("No response from the old site at #{base_url}. Start it, or leave out --base-url.")

    &(Snapshot.status(&1, base_url) != 404)
  end

  defp capture(dir, opts) do
    base_url = opts[:base_url] || Mix.raise("capture needs --base-url, e.g. --base-url http://localhost:4000")

    paths =
      case opts[:urls] do
        nil -> database_urls()
        file -> Snapshot.read_urls(file)
      end

    if paths == [], do: Mix.raise("No URLs to capture")

    {:ok, _} = Application.ensure_all_started(:req)

    pages =
      Snapshot.capture(paths, dir,
        base_url: base_url,
        concurrency: opts[:concurrency] || 4
      )

    Enum.each(pages, fn page -> Mix.shell().info("#{page.status || "---"} #{page.path}") end)
    failed = Enum.count(pages, &is_nil(&1.status))
    failed_text = if failed > 0, do: " (#{failed} without a response)", else: ""
    Mix.shell().info("Captured #{length(pages)} URLs from #{base_url} into #{dir}#{failed_text}")
  end

  defp diff(before_dir, after_dir, opts) do
    before = read!(before_dir)
    after_pages = read!(after_dir)

    results = Snapshot.compare(before, after_pages, layers: layers(opts[:layers]))
    results |> Snapshot.report(limit: opts[:limit] || 10) |> String.trim_trailing() |> Mix.shell().info()
  end

  defp read!(dir) do
    Snapshot.read(dir)
  rescue
    exception in ArgumentError -> Mix.raise(Exception.message(exception))
  end

  defp layers(nil), do: Snapshot.Diff.layers()

  defp layers(names) do
    known = Map.new(Snapshot.Diff.layers(), &{to_string(&1), &1})

    names
    |> String.split(",", trim: true)
    |> Enum.map(fn name ->
      Map.get(known, String.trim(name)) ||
        Mix.raise("Unknown layer #{inspect(name)}; layers are #{Enum.join(Map.keys(known), ", ")}")
    end)
  end
end
