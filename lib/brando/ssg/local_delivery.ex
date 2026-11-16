defmodule Brando.SSG.LocalDelivery do
  @moduledoc """
  Serves a static site's published build from the installation itself, the
  deploy strategy `:local` (`Brando.Sites.DeployConfig`).

  `Brando.Plug.SiteAssets` calls it first, in the endpoint before the router.
  It answers a request that `Brando.Plug.Tenant` would resolve to the live
  environment of an active `:static` site whose strategy is `:local` and
  which has a published build (`Brando.Sites.Site`'s `:published_build`, set
  by a deploy or rollback; `serving?/1`), read from `Brando.Tenant.Cache`:
  in `:multi` the live environment's domain, in `:single` every host but
  another environment's domain and a redirect host. Every other request costs
  those cache reads and passes on untouched.

  On such a host, a `GET` or `HEAD`:

    * for a path the build has a file for answers that file: `/about` and
      `/about/` answer `about/index.html`, `/` the root's `index.html`; a
      page asked for with `Accept: text/markdown` (`Brando.Plug.Markdown.prefers_markdown?/1`)
      answers the build's Markdown file for it (`about.md`, `index.md`) when
      it has one, and both answers then carry `Vary: Accept`;
    * for a path its redirect list (`_redirects.json`) answers, a redirect or
      `410 Gone`, as `Brando.SSG.RedirectList` describes: the first entry that
      matches the decoded path wins, a rule applies only to a request in its
      language, and a file of the build wins over an entry that is not exact;
    * for any other path answers the build's `404.html` with status 404, or a
      plain 404 when the build has none. A page the environment has but the
      build does not is never reached.

  Other methods (a form's `POST`), a request carrying a build's valid signed
  context (`Brando.SSG.Context.signed?/1`), the paths `dynamic_paths/1`
  lists, and the IndexNow key file while IndexNow is on (`Brando.Plug.IndexNow`
  answers it here) keep reaching Phoenix.

  HTML and the other files are sent with an `ETag` and
  `Cache-Control: no-cache`; the files the build's Vite manifest lists, and a
  non-HTML request with a `vsn` query as `Plug.Static` reads it, with a
  year's immutable caching.

  Pages (HTML, the 404 page included) are sent with the headers
  `Phoenix.Controller.put_secure_browser_headers/2` sets by default, as the
  router's browser pipeline would set them, and then the application's own,
  such as its Content-Security-Policy:

      config :brando, Brando.SSG.LocalDelivery,
        headers: %{"content-security-policy" => "default-src 'self'"}

  Other files are sent with `Access-Control-Allow-Origin: *`, as
  `Brando.Plug.SiteAssets` sends its own.

  A request answered here never reaches `Plug.Telemetry` or the request log.
  Each one emits `[:brando, :ssg, :local_delivery, :stop]` instead, with the
  measurement `:duration` (native time units) and the metadata `:site_key`,
  `:path` (the request path) and `:status`. A request that passes on to
  Phoenix emits nothing here. A gzipped file (the sitemap) is sent as the application's
  sitemap controller sends it. `_redirects.json` itself is not served.

  The build's file list and compiled redirects are read once per published
  version and kept in `:persistent_term`; the registry cache's refresh drops
  them when the site serves another version or none (`forget_except/1`).
  Files are listed without following symbolic links, so nothing outside the
  build's directory is ever sent.
  """

  @behaviour Plug

  import Plug.Conn,
    only: [get_req_header: 2, halt: 1, put_resp_header: 3, send_file: 3, send_resp: 3]

  alias Brando.Assets.SiteAssets
  alias Brando.Plug.IndexNow
  alias Brando.Plug.SiteAssets, as: SiteAssetsPlug
  alias Brando.Sites.Redirect.ValidSource
  alias Brando.Sites.Redirects
  alias Brando.Sites.Site
  alias Brando.SSG.BuildPath
  alias Brando.SSG.Builds
  alias Brando.SSG.Context
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Frontend

  require Logger

  @methods ~w(GET HEAD)
  @sites_key {__MODULE__, :sites}
  @redirect_list "_redirects.json"
  @not_found "404.html"
  @immutable "public, max-age=31536000, immutable"
  @revalidate "no-cache"

  # What a generated endpoint answers after `Brando.Plug.SiteAssets`, and what
  # Brando's router macros mount outside the page catch-all, on a host
  # serving its build. Kept reaching Phoenix, by path prefix:
  #
  #   /__brando          the forms' CSRF token (static forms post, which passes anyway) and the icon stylesheet
  #   /__p__             a shared preview: unpublished content behind its key, for people without an account
  #   /__ssg_preview__   a build's preview before it is published, behind its token
  #   /__livepreview     the admin's live preview and its client files (`Brando.Plug.LivePreview`)
  #   /health            `Brando.Plug.Health`, which a blue/green deploy polls from the server before switching
  #   the media path     `Brando.Plug.Media`: the build's copy of media is not listed (`skipped_dirs/0`)
  #   the admin, /mcp, /.well-known/oauth-protected-resource, /.well-known/oauth-authorization-server
  #                      the admin and MCP with its OAuth metadata, only where the admin answers
  #   :dynamic_paths     the application's own
  #
  # Left to the build:
  #
  #   /robots.txt, /sitemaps/*   the build writes both for the content it holds
  #   `….md` and `Accept: text/markdown` (`Brando.Plug.Markdown`)
  #                              the build's Markdown files; the plug renders entries, published or not
  #   the lockdown page          an application route; the browser pipeline that locks never runs for a
  #                              built page, so nothing redirects there (`:dynamic_paths` if pages link it)
  #   `Plug.Static`'s `only:`    files, decided per file (`Brando.Plug.SiteAssets.static_file?/1`), not by path
  #   /phoenix/live_reload, /tidewave   development only
  #   the IndexNow key file      decided here, while IndexNow is on (`Brando.Plug.IndexNow`)
  #
  # The sandbox and the webhook plugs (GitHub Markdown, Mux, Bunny, Cloudflare
  # Stream) take POSTs, which always pass; the sockets answer before any plug.
  @dynamic_paths ["/__brando", "/__p__", "/__ssg_preview__", "/__livepreview", "/health"]
  # Only where the admin answers (`BrandoAdmin.AdminHost.serves_admin?/1`)
  @admin_paths ["/mcp", "/.well-known/oauth-protected-resource", "/.well-known/oauth-authorization-server"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, _opts) when method in @methods do
    case served_site(conn.host) do
      nil -> conn
      site -> serve(conn, site)
    end
  end

  def call(conn, _opts), do: conn

  # The site whose build answers `host`: what `Brando.Plug.Tenant` resolves
  # the host to, with the same lookups and normalisation, when that is the
  # live environment of a site serving a published build. In `:single` every
  # host no environment names resolves to the live environment, the
  # endpoint's own and a bare IP included. A redirect host redirects first.
  defp served_site(host) do
    with true <- Brando.Tenant.enabled?(),
         nil <- Cache.get_redirect(host),
         {site, %{live: true}} <- Frontend.resolve(host),
         true <- serving?(site) do
      site
    else
      _not_served -> nil
    end
  end

  @doc """
  Whether `site` is served from its published build: an active `:static`
  site with the deploy strategy `:local` (`Brando.Sites.Site.local_delivery?/1`)
  and a published build.
  """
  @spec serving?(Site.t()) :: boolean()
  def serving?(%Site{status: :active, published_build: version} = site) when is_binary(version),
    do: Site.local_delivery?(site)

  def serving?(%Site{}), do: false

  @doc """
  The path prefixes that keep reaching Phoenix on a host serving its build:
  Brando's own (shared and build previews, live preview, the forms' and
  icons' `/__brando`, `/health` for `Brando.Plug.Health`), the media path, the admin's and MCP's paths where the
  admin answers on the host, and an application's own:

      config :brando, Brando.SSG.LocalDelivery, dynamic_paths: ["/api", "/coming-soon"]

  The endpoint's sockets answer before any plug, so they need no entry.
  """
  @spec dynamic_paths(Plug.Conn.t()) :: [String.t()]
  def dynamic_paths(conn) do
    admin = if BrandoAdmin.AdminHost.serves_admin?(conn), do: [admin_path() | @admin_paths], else: []
    own = Application.get_env(:brando, __MODULE__, [])[:dynamic_paths] || []
    [media_path() | @dynamic_paths] ++ admin ++ own
  end

  defp serve(conn, site) do
    cond do
      dynamic_path?(conn) -> conn
      Context.signed?(conn) -> conn
      true -> conn |> IndexNow.call([]) |> answer_unless_halted(site)
    end
  end

  # The IndexNow key file (`/<key>.txt`) is the application's while IndexNow
  # is on, as submissions name it there
  defp answer_unless_halted(%Plug.Conn{halted: true} = conn, _site), do: conn

  defp answer_unless_halted(conn, site) do
    started = System.monotonic_time()

    case answer(conn, site) do
      %Plug.Conn{halted: true} = answered ->
        :telemetry.execute(
          [:brando, :ssg, :local_delivery, :stop],
          %{duration: System.monotonic_time() - started},
          %{site_key: site.key, path: answered.request_path, status: answered.status}
        )

        answered

      passed ->
        passed
    end
  end

  defp dynamic_path?(%Plug.Conn{path_info: path_info} = conn) do
    Enum.any?(dynamic_paths(conn), fn prefix ->
      segments = String.split(prefix, "/", trim: true)
      segments != [] and List.starts_with?(path_info, segments)
    end)
  end

  # A file the build lacks is left to the asset pipeline when it has one:
  # files, not content, so nothing unpublished answers
  defp answer(conn, site) do
    case published(site) do
      {:ok, build} -> answer_from(conn, site, build, requested_file(conn, build))
      :error -> conn |> send_unavailable() |> halt()
    end
  end

  defp answer_from(conn, site, build, file) do
    case redirect(conn, site, build) do
      {true, status, target} -> conn |> send_redirect(status, target) |> halt()
      {false, _status, _target} when is_binary(file) -> conn |> send_build_file(build, file) |> halt()
      {false, status, target} -> conn |> send_redirect(status, target) |> halt()
      nil when is_binary(file) -> conn |> send_build_file(build, file) |> halt()
      nil -> answer_missing(conn, build)
    end
  end

  defp answer_missing(conn, build) do
    if SiteAssetsPlug.static_file?(conn),
      do: conn,
      else: conn |> send_not_found(build) |> halt()
  end

  defp send_unavailable(conn) do
    conn
    |> put_resp_header("cache-control", @revalidate)
    |> put_resp_header("retry-after", "60")
    |> send_resp(503, "Service unavailable")
  end

  defp requested_file(conn, build) do
    with {:ok, relative} <- BuildPath.relative_encoded(conn.path_info),
         true <- Map.has_key?(build.files, relative) do
      relative
    else
      _missing -> nil
    end
  end

  # -- Redirects ----------------------------------------------------------------

  # The first entry that matches the decoded path, in the request's language:
  # read with the languages the build was made with, the site's current ones
  # for a list that predates them, as `Brando.I18n.parse_path/2` reads it
  defp redirect(conn, site, build) do
    case decode(conn.path_info) do
      {:ok, segments} ->
        path = "/" <> Enum.join(segments, "/")
        language = path_language(segments, build.languages || site_languages(site))
        Enum.find_value(build.redirects, &match_entry(&1, path, language))

      :error ->
        nil
    end
  end

  defp path_language([first | _rest], {codes, default}), do: if(first in codes, do: first, else: default)
  defp path_language([], {_codes, default}), do: default

  defp site_languages(site), do: {Brando.Languages.codes(site), to_string(Brando.Languages.default_language(site))}

  defp match_entry(%{language: entry_language} = entry, path, language) when entry_language in [nil, language] do
    case Redirects.target(path, entry.pattern, entry.target) do
      nil -> nil
      target -> {entry.exact, entry.status, target}
    end
  end

  defp match_entry(_entry, _path, _language), do: nil

  defp decode(segments) do
    {:ok, Enum.map(segments, &URI.decode/1)}
  rescue
    ArgumentError -> :error
  end

  defp send_redirect(conn, 410, _target) do
    conn
    |> put_resp_header("cache-control", @revalidate)
    |> put_resp_header("content-type", "text/plain; charset=utf-8")
    |> send_resp(410, "Gone")
  end

  defp send_redirect(conn, status, target) do
    conn
    |> put_resp_header("location", target)
    |> put_resp_header("cache-control", @revalidate)
    |> send_resp(status, "")
  end

  # -- Files ----------------------------------------------------------------------

  # A page with a Markdown file in the build answers `Accept: text/markdown`
  # with it, as `Brando.Plug.Markdown` answers for the application
  defp send_build_file(conn, build, relative) do
    case markdown_file(build, relative) do
      nil ->
        send_file_of(conn, build, relative)

      markdown ->
        conn = put_resp_header(conn, "vary", "Accept")
        send_file_of(conn, build, if(prefers_markdown?(conn), do: markdown, else: relative))
    end
  end

  # `about/index.html` has `about.md`, the root's `index.html` `index.md`
  defp markdown_file(build, relative) do
    markdown =
      case relative do
        "index.html" -> "index.md"
        _page -> if Path.basename(relative) == "index.html", do: Path.dirname(relative) <> ".md"
      end

    if markdown && Map.has_key?(build.files, markdown), do: markdown
  end

  defp prefers_markdown?(conn) do
    case get_req_header(conn, "accept") do
      [accept | _] -> Brando.Plug.Markdown.prefers_markdown?(accept)
      [] -> false
    end
  end

  defp send_file_of(conn, build, relative) do
    etag = Map.fetch!(build.files, relative)
    conn = put_file_headers(conn, relative)

    if immutable?(conn, build, relative) do
      conn
      |> put_resp_header("cache-control", @immutable)
      |> send_file_as(200, build, relative)
    else
      conn = conn |> put_resp_header("cache-control", @revalidate) |> put_resp_header("etag", etag)

      if etag in get_req_header(conn, "if-none-match"),
        do: send_resp(conn, 304, ""),
        else: send_file_as(conn, 200, build, relative)
    end
  end

  # A page gets the headers the router's browser pipeline would set, which
  # never runs for it: `Phoenix.Controller.put_secure_browser_headers/2`'s
  # defaults, then the application's own (`:headers`). Other files get the
  # header `Brando.Plug.SiteAssets` sends its files with: sandboxed live and
  # shared previews load them from an opaque origin.
  defp put_file_headers(conn, relative) do
    if html?(relative),
      do: Phoenix.Controller.put_secure_browser_headers(conn, page_headers()),
      else: put_resp_header(conn, "access-control-allow-origin", "*")
  end

  defp page_headers do
    case Application.get_env(:brando, __MODULE__, [])[:headers] do
      headers when is_map(headers) and map_size(headers) > 0 -> headers
      _none -> []
    end
  end

  defp html?(relative), do: Path.extname(relative) == ".html"

  defp send_not_found(conn, build) do
    conn = put_resp_header(conn, "cache-control", @revalidate)

    if Map.has_key?(build.files, @not_found),
      do: conn |> put_file_headers(@not_found) |> send_file_as(404, build, @not_found),
      else: conn |> put_resp_header("content-type", "text/plain; charset=utf-8") |> send_resp(404, "Not found")
  end

  # The sitemap is stored gzipped and sent as `BrandoWeb.SitemapController`
  # sends it, a download
  defp send_file_as(conn, status, build, relative) do
    conn =
      conn
      |> put_resp_header("content-type", content_type(relative))
      |> put_resp_header("x-content-type-options", "nosniff")

    conn =
      if Path.extname(relative) == ".gz",
        do:
          put_resp_header(conn, "content-disposition", ~s[attachment; filename="#{URI.encode(Path.basename(relative))}"]),
        else: conn

    send_build_path(conn, status, build, relative)
  end

  # A file gone since the build was listed: memory forgets the build, so the
  # next request looks for its directory again (`published/1`)
  defp send_build_path(conn, status, build, relative) do
    send_file(conn, status, Path.join(build.root, relative))
  rescue
    File.Error ->
      :persistent_term.erase({__MODULE__, build.site_id})
      send_unavailable(conn)
  end

  defp content_type(relative) do
    case MIME.from_path(relative) do
      "text/" <> _subtype = type -> type <> "; charset=utf-8"
      "application/json" = type -> type <> "; charset=utf-8"
      type -> type
    end
  end

  # Content-addressed files the build's Vite manifest lists, or a request
  # versioned with `?vsn=`, as `Plug.Static` reads one; never HTML, which
  # the next deploy changes under the same URL
  defp immutable?(conn, build, relative),
    do: not html?(relative) and (versioned?(conn) or MapSet.member?(build.immutable, relative))

  defp versioned?(%Plug.Conn{query_string: "vsn=" <> _}), do: true
  defp versioned?(_conn), do: false

  # -- The published build in memory ----------------------------------------------

  defp published(site), do: in_memory_or(site, fn -> load(site) end)

  # One load of a build at a time on this node, other sites' and versions'
  # loads beside it; a request that waited finds it loaded, or missing
  defp load(%Site{id: site_id, published_build: version} = site) do
    :global.trans(
      {{__MODULE__, :load, site_id, version}, self()},
      fn -> in_memory_or(site, fn -> read_build(site) end) end,
      [node()],
      :infinity
    )
  end

  defp in_memory_or(%Site{id: site_id, published_build: version} = site, read) do
    case :persistent_term.get({__MODULE__, site_id}, nil) do
      %{version: ^version} = build -> {:ok, build}
      _other -> if missing?(site), do: :error, else: read.()
    end
  end

  # A directory found missing is looked for again after a few seconds, not
  # on every request
  @missing_for :timer.seconds(5)

  defp missing?(%Site{id: site_id, published_build: version}),
    do: match?({:ok, true}, Cachex.get(:cache, {__MODULE__, :missing, site_id, version}))

  defp remember_missing(%Site{id: site_id, published_build: version}),
    do: Cachex.put(:cache, {__MODULE__, :missing, site_id, version}, true, expire: @missing_for)

  defp read_build(%Site{id: site_id, published_build: version} = site) do
    root = Path.join(Builds.build_root(site), version)

    if Regex.match?(~r/\Av[0-9]+\z/, version) and BuildPath.managed?(root, site) and dir?(root) do
      redirect_list = read_json(root, @redirect_list)
      files = root |> list_files(skipped_dirs()) |> Map.new(fn {relative, stat} -> {relative, etag(version, stat)} end)
      manifest = read_json(root, "manifest.json")

      build = %{
        site_id: site_id,
        version: version,
        root: root,
        files: Map.delete(files, @redirect_list),
        immutable: immutable_files(manifest, files),
        redirects: read_redirects(redirect_list),
        languages: redirect_languages(redirect_list)
      }

      :persistent_term.put({__MODULE__, site_id}, build)
      :persistent_term.put(@sites_key, MapSet.put(:persistent_term.get(@sites_key, MapSet.new()), site_id))
      {:ok, build}
    else
      remember_missing(site)
      Logger.error("Site #{site.key} has no published build to serve at #{root}: is sites/ shared by every node?")
      :error
    end
  end

  defp dir?(root), do: match?({:ok, %{type: :directory}}, File.lstat(root))

  @doc """
  Drops what memory holds of a published build for every site but the
  `{site_id, version}` pairs given: the builds the registry serves now.
  Called whenever `Brando.Tenant.Cache` warms or clears.
  """
  @spec forget_except([{pos_integer(), String.t()}]) :: :ok
  def forget_except(served) do
    served = MapSet.new(served)
    tracked = :persistent_term.get(@sites_key, MapSet.new())
    {kept, dropped} = Enum.split_with(tracked, &served?(&1, served))

    if dropped != [] do
      Enum.each(dropped, &:persistent_term.erase({__MODULE__, &1}))
      if kept == [], do: :persistent_term.erase(@sites_key), else: :persistent_term.put(@sites_key, MapSet.new(kept))
    end

    :ok
  end

  defp served?(site_id, served) do
    case :persistent_term.get({__MODULE__, site_id}, nil) do
      %{version: version} -> MapSet.member?(served, {site_id, version})
      nil -> false
    end
  end

  # Regular files only: a symbolic link, to a file or a directory, is no file
  # of the build. Media keeps reaching Phoenix, so its copy is not listed.
  defp list_files(root, skipped_dirs) do
    root
    |> walk("", skipped_dirs)
    |> Map.new()
  end

  defp walk(root, relative, skipped_dirs) do
    case File.ls(Path.join(root, relative)) do
      {:ok, names} -> Enum.flat_map(names, &walk_entry(root, relative, &1, skipped_dirs))
      {:error, _reason} -> []
    end
  end

  defp walk_entry(root, relative, name, skipped_dirs) do
    child = if relative == "", do: name, else: Path.join(relative, name)

    case File.lstat(Path.join(root, child), time: :posix) do
      {:ok, %{type: :directory}} -> if relative == "" and name in skipped_dirs, do: [], else: walk(root, child, [])
      {:ok, %{type: :regular, size: size, mtime: mtime}} -> [{child, {size, mtime}}]
      _symlink_or_other -> []
    end
  end

  # The version too: two builds can hold a file of the same size written in
  # the same second
  defp etag(version, {size, mtime}),
    do: <<?", version::binary, ?-, {size, mtime} |> :erlang.phash2() |> Integer.to_string(16)::binary, ?">>

  defp skipped_dirs do
    case String.split(media_path(), "/", trim: true) do
      [dir] -> [dir]
      _other -> []
    end
  end

  # Source maps sit beside their hashed owners
  defp immutable_files(manifest, files) do
    manifest
    |> SiteAssets.manifest_files()
    |> Enum.flat_map(&[&1, &1 <> ".map"])
    |> Enum.filter(&Map.has_key?(files, &1))
    |> MapSet.new()
  end

  # Each entry's `pattern` compiled as the application compiles a rule
  defp read_redirects(%{"redirects" => entries}) when is_list(entries), do: Enum.flat_map(entries, &redirect_entry/1)
  defp read_redirects(_none), do: []

  defp redirect_languages(%{"languages" => [_ | _] = codes, "default_language" => default}) when is_binary(default) do
    if Enum.all?(codes, &is_binary/1), do: {codes, default}
  end

  defp redirect_languages(_none), do: nil

  defp redirect_entry(%{"pattern" => pattern, "status" => status} = entry) when is_integer(status) do
    case ValidSource.compile(pattern) do
      {:ok, regex} ->
        [
          %{
            pattern: regex,
            target: entry["target"],
            status: status,
            exact: entry["exact"] == true,
            language: entry["language"]
          }
        ]

      :error ->
        []
    end
  end

  defp redirect_entry(_entry), do: []

  defp read_json(root, name) do
    path = Path.join(root, name)

    with {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, json} <- File.read(path),
         {:ok, decoded} <- Jason.decode(json) do
      decoded
    else
      _missing_or_invalid -> nil
    end
  end

  defp media_path do
    case Brando.config(:media_url) do
      url when is_binary(url) and url != "" -> url
      _none -> "/media"
    end
  end

  defp admin_path do
    router = Brando.router()

    if Code.ensure_loaded?(router) and function_exported?(router, :__brando_admin_path__, 0),
      do: router.__brando_admin_path__(),
      else: "/admin"
  end
end
