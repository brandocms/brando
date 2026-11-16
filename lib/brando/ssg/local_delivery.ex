defmodule Brando.SSG.LocalDelivery do
  @moduledoc """
  Serves a static site's published build from the installation itself, the
  deploy strategy `:local` (`Brando.Sites.DeployConfig`).

  `Brando.Plug.SiteAssets` calls it first, in the endpoint before the router.
  It answers on the domain of the live environment of an active `:static`
  site whose strategy is `:local` and which has a published build
  (`Brando.Sites.Site`'s `:published_build`, set by a deploy or rollback),
  read from `Brando.Tenant.Cache`. Every other request costs that one cache
  read and passes on untouched.

  On such a host, a `GET` or `HEAD`:

    * for a path the build has a file for answers that file: `/about` and
      `/about/` answer `about/index.html`, `/` the root's `index.html`;
    * for a path its redirect list (`_redirects.json`) answers, a redirect or
      `410 Gone`, as `Brando.SSG.RedirectList` describes: the first entry that
      matches the decoded path wins, a rule applies only to a request in its
      language, and a file of the build wins over an entry that is not exact;
    * for any other path answers the build's `404.html` with status 404, or a
      plain 404 when the build has none. A page the environment has but the
      build does not is never reached.

  Other methods (a form's `POST`), a request carrying a build's valid signed
  context (`Brando.SSG.Context.signed?/1`), and the paths `dynamic_paths/1`
  lists keep reaching Phoenix.

  HTML and the other files are sent with an `ETag` and
  `Cache-Control: no-cache`; the files the build's Vite manifest lists, and a
  request with a `vsn` query as `Plug.Static` reads it, with a year's
  immutable caching. A gzipped file (the sitemap) is sent as the application's
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
  alias Brando.Sites.Redirect.ValidSource
  alias Brando.Sites.Redirects
  alias Brando.Sites.Site
  alias Brando.SSG.BuildPath
  alias Brando.SSG.Builds
  alias Brando.SSG.Context
  alias Brando.Tenant.Cache

  require Logger

  @methods ~w(GET HEAD)
  @sites_key {__MODULE__, :sites}
  @redirect_list "_redirects.json"
  @not_found "404.html"
  @immutable "public, max-age=31536000, immutable"
  @revalidate "no-cache"

  # Brando's own paths that answer on a site's host whatever it serves
  @dynamic_paths ["/__brando", "/__p__", "/__ssg_preview__", "/__livepreview"]
  # Only where the admin answers (`BrandoAdmin.AdminHost.serves_admin?/1`)
  @admin_paths ["/mcp", "/.well-known/oauth-protected-resource", "/.well-known/oauth-authorization-server"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method, host: host} = conn, _opts) when method in @methods do
    case Cache.get_local_build(String.downcase(host)) do
      nil -> conn
      {site, _environment} -> serve(conn, site)
    end
  end

  def call(conn, _opts), do: conn

  @doc """
  The path prefixes that keep reaching Phoenix on a host serving its build:
  Brando's own (shared and build previews, live preview, the forms' and
  icons' `/__brando`), the media path, the admin's and MCP's paths where the
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
      true -> conn |> answer(site) |> halt()
    end
  end

  defp dynamic_path?(%Plug.Conn{path_info: path_info} = conn) do
    Enum.any?(dynamic_paths(conn), fn prefix ->
      segments = String.split(prefix, "/", trim: true)
      segments != [] and List.starts_with?(path_info, segments)
    end)
  end

  defp answer(conn, site) do
    case published(site) do
      {:ok, build} ->
        file = requested_file(conn, build)

        case redirect(conn, site, build) do
          {true, status, target} -> send_redirect(conn, status, target)
          {false, _status, _target} when is_binary(file) -> send_build_file(conn, build, file)
          {false, status, target} -> send_redirect(conn, status, target)
          nil when is_binary(file) -> send_build_file(conn, build, file)
          nil -> send_not_found(conn, build)
        end

      :error ->
        conn
        |> put_resp_header("cache-control", @revalidate)
        |> put_resp_header("retry-after", "60")
        |> send_resp(503, "Service unavailable")
    end
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

  # The first entry that matches the decoded path, in the request's language
  defp redirect(conn, site, build) do
    with {:ok, segments} <- decode(conn.path_info) do
      path = "/" <> Enum.join(segments, "/")
      {language, _rest} = Brando.I18n.parse_path(segments, site)

      Enum.find_value(build.redirects, fn entry ->
        if entry.language in [nil, language] do
          case Redirects.target(path, entry.pattern, entry.target) do
            nil -> nil
            target -> {entry.exact, entry.status, target}
          end
        end
      end)
    else
      _undecodable -> nil
    end
  end

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

  defp send_build_file(conn, build, relative) do
    path = Path.join(build.root, relative)
    etag = Map.fetch!(build.files, relative)

    if immutable?(conn, build, relative) do
      conn
      |> put_resp_header("cache-control", @immutable)
      |> send_file_as(200, path, relative)
    else
      conn = conn |> put_resp_header("cache-control", @revalidate) |> put_resp_header("etag", etag)

      if etag in get_req_header(conn, "if-none-match"),
        do: send_resp(conn, 304, ""),
        else: send_file_as(conn, 200, path, relative)
    end
  end

  defp send_not_found(conn, build) do
    conn = put_resp_header(conn, "cache-control", @revalidate)

    if Map.has_key?(build.files, @not_found),
      do: send_file_as(conn, 404, Path.join(build.root, @not_found), @not_found),
      else: conn |> put_resp_header("content-type", "text/plain; charset=utf-8") |> send_resp(404, "Not found")
  end

  # The sitemap is stored gzipped and sent as `BrandoWeb.SitemapController`
  # sends it, a download
  defp send_file_as(conn, status, path, relative) do
    conn =
      conn
      |> put_resp_header("content-type", content_type(relative))
      |> put_resp_header("x-content-type-options", "nosniff")

    if Path.extname(relative) == ".gz",
      do:
        conn
        |> put_resp_header("content-disposition", ~s[attachment; filename="#{URI.encode(Path.basename(relative))}"])
        |> send_file(status, path),
      else: send_file(conn, status, path)
  end

  defp content_type(relative) do
    case MIME.from_path(relative) do
      "text/" <> _subtype = type -> type <> "; charset=utf-8"
      "application/json" = type -> type <> "; charset=utf-8"
      type -> type
    end
  end

  # Content-addressed files the build's Vite manifest lists, or a request
  # versioned with `?vsn=`, as `Plug.Static` reads one
  defp immutable?(%Plug.Conn{query_string: "vsn=" <> _}, _build, _relative), do: true
  defp immutable?(_conn, build, relative), do: MapSet.member?(build.immutable, relative)

  # -- The published build in memory ----------------------------------------------

  defp published(%Site{id: site_id, published_build: version} = site) do
    case :persistent_term.get({__MODULE__, site_id}, nil) do
      %{version: ^version} = build -> {:ok, build}
      _other -> load(site)
    end
  end

  # One load at a time on this node; a request that waited finds it loaded
  defp load(%Site{id: site_id, published_build: version} = site) do
    :global.trans(
      {{__MODULE__, :load}, self()},
      fn ->
        case :persistent_term.get({__MODULE__, site_id}, nil) do
          %{version: ^version} = build -> {:ok, build}
          _other -> read_build(site)
        end
      end,
      [node()],
      :infinity
    )
  end

  defp read_build(%Site{id: site_id, published_build: version} = site) do
    root = Path.join(Builds.build_root(site), version)

    if Regex.match?(~r/\Av[0-9]+\z/, version) and BuildPath.managed?(root, site) and dir?(root) do
      files = list_files(root, skipped_dirs())
      manifest = read_json(root, "manifest.json")

      build = %{
        version: version,
        root: root,
        files: Map.delete(files, @redirect_list),
        immutable: immutable_files(manifest, files),
        redirects: read_redirects(root)
      }

      :persistent_term.put({__MODULE__, site_id}, build)
      :persistent_term.put(@sites_key, MapSet.put(:persistent_term.get(@sites_key, MapSet.new()), site_id))
      {:ok, build}
    else
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
      {:ok, names} ->
        Enum.flat_map(names, fn name ->
          child = if relative == "", do: name, else: Path.join(relative, name)

          case File.lstat(Path.join(root, child), time: :posix) do
            {:ok, %{type: :directory}} ->
              if relative == "" and name in skipped_dirs, do: [], else: walk(root, child, [])

            {:ok, %{type: :regular, size: size, mtime: mtime}} ->
              [{child, etag(size, mtime)}]

            _symlink_or_other ->
              []
          end
        end)

      {:error, _reason} ->
        []
    end
  end

  defp etag(size, mtime), do: <<?", {size, mtime} |> :erlang.phash2() |> Integer.to_string(16)::binary, ?">>

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
  defp read_redirects(root) do
    case read_json(root, @redirect_list) do
      %{"redirects" => entries} when is_list(entries) -> Enum.flat_map(entries, &redirect_entry/1)
      _none -> []
    end
  end

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
