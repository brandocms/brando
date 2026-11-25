defmodule Brando.Plug.SiteAssets do
  @moduledoc """
  Serves files from the persistent frontend asset set the host's environment
  uses (its own set, else its site's active set), or from a set a shared
  preview has pinned.

  On the host of a site the installation serves a static build for, the
  build answers first (`Brando.SSG.LocalDelivery`), and only the paths that
  keep reaching Phoenix, and the files the build lacks that this plug or the
  release's `Plug.Static` has (`static_file?/1`), get this far.

  Place this plug before the application's release `Plug.Static`. Cached
  `MapSet`s reject misses without touching the filesystem; misses fall through
  unchanged so release assets remain the fallback. Pinned sets only serve the
  content-addressed files their Vite manifest lists, at their original URLs,
  so a preview rendered against an older build keeps loading its stylesheets,
  chunks, and fonts after the active set or release changes.

  In `:multi`, a host that belongs to no site, as the admin's does, gets, per
  path, the file a site's own host would send, unless sites hold different
  content under that path (`Brando.Assets.SiteAssets.unscoped_path/1`): the
  admin serves live and shared previews from its own host, and their pages
  name the site's assets host-relative. A host that belongs to a site gets
  that site's sets only, and the set its environment uses
  (`Brando.Assets.SiteAssets.serve_path/3`). In `:single`, the host's
  environment, or the live one for a host no environment names, picks the
  set the same way. A path those miss answers from the own set of another
  environment of the same site (`Brando.Assets.SiteAssets.other_environment_path/3`),
  sent with `Cache-Control: no-cache`: a live or shared preview of that
  environment is shown on this host and names that set's files. In
  development, the dev site's hosts, and the admin's for its live preview,
  then answer from the `public/` folder of its Vite project
  (`Brando.Assets.SiteAssets.dev_site_public_file/3`,
  `Brando.Assets.SiteAssets.unscoped_public_file/1`), also with `no-cache`.

  Its files, and those of the plugs after it that answer before the router
  (the release's `Plug.Static`, `Brando.Plug.Media`), are sent with
  `Access-Control-Allow-Origin: *`. Live previews and shared preview snapshots
  are sandboxed (`Brando.Plug.LivePreview.sandbox_policy/0`), so their origin
  is opaque and their module scripts, fonts and other `crossorigin` requests
  are cross-origin: without the header, the browser refuses them. The files
  are public and the header allows no credentials, so it exposes nothing a
  request without cookies would not get. Admin paths, preview pages and
  everything the router answers are left alone.

  Every response on a static site's preview host (`Brando.SSG.PreviewHost`)
  carries `X-Robots-Tag: noindex, nofollow`, whichever plug sends it.
  """

  import Plug.Conn, only: [get_resp_header: 2, halt: 1, put_resp_header: 3, register_before_send: 2, send_file: 3]

  alias Brando.Assets.SiteAssets
  alias Brando.Assets.SiteAssets.Capture
  alias Brando.SSG.LocalDelivery
  alias Brando.SSG.PreviewHost
  alias Brando.Tenant.Frontend

  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts), do: conn |> no_index_preview_host() |> serve(opts)

  defp serve(%Plug.Conn{method: method} = conn, opts) when method in @allowed_methods do
    case LocalDelivery.call(conn, opts) do
      %Plug.Conn{halted: true} = served -> served
      conn -> serve_asset(conn)
    end
  end

  defp serve(conn, _opts), do: conn

  # Whatever answers on a static site's preview host, this plug, a plug after
  # it or the router, tells crawlers to leave it alone
  defp no_index_preview_host(conn) do
    if PreviewHost.preview_host?(conn.host),
      do: register_before_send(conn, &put_resp_header(&1, "x-robots-tag", "noindex, nofollow")),
      else: conn
  end

  @doc """
  Whether the endpoint's asset pipeline would answer `conn` with a file: this
  plug, from the asset set the host uses or another environment's, or the
  release's `Plug.Static`, from the release's compiled static directory
  (`Brando.Assets.SiteAssets.Capture.release_root/0`) under one of the web
  module's `static_paths/0`, which a generated endpoint passes as its `only:`.
  A web module without `static_paths/0` leaves the release's directory alone
  to decide. The two lists should be the same (the System check's "Static
  paths of served builds" compares them): a request this lets through that
  `Plug.Static` does not serve gets the build's 404 page from
  `Brando.Plug.Tenant`.

  On a host that serves a published build (`Brando.SSG.LocalDelivery`), a file
  the build lacks reaches the pipeline when this says it has one: the admin's
  bundles, a preview's newer assets and those of pages Phoenix renders there.
  """
  @spec static_file?(Plug.Conn.t()) :: boolean()
  def static_file?(%Plug.Conn{} = conn) do
    case relative_path(conn.path_info) do
      nil ->
        false

      relative_path ->
        release_file?(relative_path) or match?({file, _cache} when is_binary(file), serve_path(conn, relative_path))
    end
  end

  defp release_file?(relative_path) do
    static_path?(relative_path) and File.regular?(Path.join(Capture.release_root(), relative_path))
  end

  defp static_path?(relative_path) do
    web_module = Brando.config(:web_module)

    if is_atom(web_module) and Code.ensure_loaded?(web_module) and function_exported?(web_module, :static_paths, 0),
      do: hd(Path.split(relative_path)) in web_module.static_paths(),
      else: true
  end

  defp serve_asset(conn) do
    conn = allow_any_origin(conn)

    with relative_path when is_binary(relative_path) <- relative_path(conn.path_info),
         {file, cache_control} when is_binary(file) <- serve_path(conn, relative_path) do
      conn
      |> put_resp_header("content-type", MIME.from_path(relative_path))
      |> put_resp_header("cache-control", cache_control)
      |> Brando.Plug.Usage.put_file(file)
      |> send_file(200, file)
      |> halt()
    else
      _miss -> conn
    end
  end

  @no_cors_roots ["admin", "__livepreview"]
  @static_statuses [200, 206, 304]

  defp allow_any_origin(%Plug.Conn{path_info: [root | _]} = conn) when root in @no_cors_roots, do: conn
  defp allow_any_origin(conn), do: register_before_send(conn, &put_allow_origin/1)

  # Only a file a plug before the router sent: the router marks every
  # connection it handles
  defp put_allow_origin(conn) do
    if conn.status in @static_statuses and not Map.has_key?(conn.private, :phoenix_router) and
         get_resp_header(conn, "access-control-allow-origin") == [] do
      put_resp_header(conn, "access-control-allow-origin", "*")
    else
      conn
    end
  end

  @immutable "public, max-age=31536000, immutable"

  # A host with no site answers a path for whichever site holds it, and stops
  # when a second site brings other content under that name: a cache must ask
  # again each time, or it keeps sending the first site's file. The same holds
  # for a file of another environment's set on an environment's host.
  @ask_again "no-cache"

  defp serve_path(conn, relative_path) do
    case Brando.Tenant.mode() do
      :multi ->
        case Frontend.resolve(conn.host) do
          {site, environment} -> environment_path(site, environment, relative_path)
          nil -> {unscoped_path(conn.host, relative_path), @ask_again}
        end

      _standalone ->
        environment_path(nil, standalone_environment(conn.host), relative_path)
    end
  end

  # The host's own sets first; another environment's own set only after a
  # miss, and the development site's project `public/` folder last
  defp environment_path(site, environment, relative_path) do
    case SiteAssets.serve_path(site, environment, relative_path) do
      nil ->
        {SiteAssets.other_environment_path(site, environment, relative_path) ||
           SiteAssets.dev_site_public_file(site, environment, relative_path), @ask_again}

      file ->
        {file, @immutable}
    end
  end

  # The development site's project `public/` folder answers on the admin's
  # host alone, for its live preview
  defp unscoped_path(host, relative_path) do
    SiteAssets.unscoped_path(relative_path) ||
      if BrandoAdmin.AdminHost.admin_host?(host), do: SiteAssets.unscoped_public_file(relative_path)
  end

  # `:single` resolves the host to an environment of its one site; `:none` has none
  defp standalone_environment(host) do
    case Frontend.resolve(host) do
      {_site, environment} -> environment
      nil -> nil
    end
  end

  defp relative_path(path_info) do
    decoded = Enum.map(path_info, &URI.decode/1)

    if decoded == [] or Enum.any?(decoded, &(&1 in ["", ".", ".."] or String.contains?(&1, ["/", "\\"]))) do
      nil
    else
      Path.join(decoded)
    end
  end
end
