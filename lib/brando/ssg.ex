defmodule Brando.SSG do
  @moduledoc """
  Static-site generation primitives and callable build API.

  Applications declare URLs in their web `SSG` module with `urls/2`. Brando's
  publish lifecycle calls `build/3` for a particular site and named content
  environment; `mix brando.ssg` remains available as an interactive wrapper.
  """

  use Brando.Tracing.Decorator

  alias Brando.Assets.SiteAssetSet
  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.SSG.Context
  alias Brando.Tenant
  alias Brando.Tenant.Storage
  alias Brando.Tracing

  @default_receive_timeout 60_000
  @redirect_statuses [301, 302, 303, 307, 308]
  @max_redirects 10

  # A path no site has a page on, requested for the site's error page
  @not_found_path "/__brando_ssg__/not-found"
  @redirects_file "_redirects.json"
  @sitemap_index "sitemaps/sitemap.xml.gz"
  @link_tag ~r/<link\b[^>]*>/i
  @tag_attributes %{
    "rel" => ~r/\srel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i,
    "type" => ~r/\stype\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i,
    "href" => ~r/\shref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i
  }
  @heex_debug_options [:debug_heex_annotations, :debug_attributes]

  @doc """
  The path a build requests for the site's error page, which it stores as
  `404.html`. No route answers it, so the application answers it as any
  missing path, with status 404, and logs no 404 for it
  (`Brando.Sites.FourOhFour`).
  """
  @spec not_found_path() :: String.t()
  def not_found_path, do: @not_found_path

  @doc "The name of the redirect list at the root of a build (`Brando.SSG.RedirectList`)."
  @spec redirects_file() :: String.t()
  def redirects_file, do: @redirects_file

  @doc """
  Declares a group of paths in the application's web SSG module.

  `mix brando.gen.ssg` writes `lib/my_app_web/ssg.ex`, listing each site's
  published pages from its content; add a block for each other content type
  with pages:

  ```
      urls :projects do
        {:ok, projects} = MyApp.Projects.list_projects(%{status: :published})
        Enum.map(projects, &MyApp.Projects.Project.__absolute_url__/1)
      end
  ```

  The functions run inside the selected environment's tenant prefix.
  """
  defmacro urls(key, do: block) do
    quote do
      def unquote(:"__urls_for_#{key}__")() do
        unquote(block)
      end
    end
  end

  defmacro render_path(path) do
    quote do
      def __render_path__ do
        unquote(path)
      end
    end
  end

  defp has_custom_render_path(module) do
    {:__render_path__, 0} in module.__info__(:functions)
  end

  @doc "Returns the legacy standalone output directory."
  def get_root_path(module \\ Brando.web_module(SSG)) do
    ssg_module = module

    case Code.ensure_compiled(ssg_module) do
      {:module, _} ->
        if has_custom_render_path(ssg_module) do
          ssg_module.__render_path__()
        else
          Path.join([File.cwd!(), "ssg"])
        end

      {:error, _} ->
        raise "Missing SSG module `#{ssg_module}`"
    end
  end

  @doc "Evaluates all declared URL groups in a database transaction."
  def get_urls(module \\ Brando.web_module(SSG)) do
    ssg_module = module

    case Code.ensure_compiled(ssg_module) do
      {:module, _} ->
        ssg_functions =
          :functions
          |> ssg_module.__info__()
          |> Enum.filter(fn {name, arity} ->
            arity == 0 and String.starts_with?(Atom.to_string(name), "__urls_for_")
          end)

        entries = Stream.flat_map(ssg_functions, &apply(ssg_module, elem(&1, 0), []))

        Brando.Repo.transaction(fn -> Enum.to_list(entries) end)

      {:error, _} ->
        raise "Missing SSG module `#{ssg_module}`"
    end
  end

  @doc """
  Builds a static snapshot for one site and environment.

  Output is written to `:output_path`. Assets come from the build's selected
  `Brando.Assets.SiteAssetSet`, falling back to the release's `priv/static`.
  Requests carry a short-lived signed SSG header so environments without a
  domain can be rendered through the normal endpoint and tenant plug.

  Pages are requested from the endpoint's own HTTP listener: `http`, the
  loopback address and the port the endpoint (`:endpoint`, by default the
  application's) is listening on, read when the build starts. A listener bound
  to one address other than a wildcard is requested on that address. Each
  request says `Host: localhost:<port>`, a host `Plug.SSL` (`force_ssl`)
  excludes by default, and `x-forwarded-proto: https` when the endpoint's URL
  is `https`, which its `rewrite_on: [:x_forwarded_proto]` reads. The site
  comes from the signed header, not from the host. An explicit `:base_url`
  wins, and is requested as it is. Without a listener, and without
  `:base_url`, the build fails with `{:no_http_listener, endpoint}` before any
  URL is requested or the output is touched (`error_message/1` describes it).
  A dry run requests nothing and needs no listener.

  A build requests only its own origin: the listener's, or
  `http://localhost:<port>` (and `https://localhost:<port>` when it sends
  `x-forwarded-proto: https`), which is requested over `http` on the
  listener's address. A listed path that redirects within the build's origin
  is stored with the answer it ends at, and the header goes along. A redirect
  to any other origin fails that URL without a request. On a build that
  requests the listener, one to the same path on `https` under `localhost` or
  the endpoint's host, or one that keeps answering a redirect to itself there,
  fails it naming `force_ssl` as the likely cause.

  The injectable `:fetcher` option has arity two (`url`, request options) and
  is intended for tests or custom transports. The request options include
  `redirect: false`: a fetcher returns a redirect with its `:headers` rather
  than following it, so that the build can check the target.

  Each file holds the bytes the application answered, unchanged. A build
  fails with `{:heex_debug_output, options}` before it requests anything when
  the application is configured to write HEEx debug comments or
  `data-phx-loc` attributes into its pages
  (`config :phoenix_live_view, debug_heex_annotations: true` or
  `debug_attributes: true`), which development configs usually do.

  Besides the listed URLs, the build writes what a static host needs to
  serve the site on its own, requested the same way with the same header:

    * the Markdown alternate (`about.md`) each page names with
      `<link rel="alternate" type="text/markdown">`, on the site's own host;
    * `404.html`, the site's error page: the answer to `not_found_path/0`,
      which must be a 404;
    * `sitemaps/`, the sitemap of the environment being built
      (`Brando.Sitemap.write_static/2`, from `:sitemap_module`, by default the
      application's), with entries on the site's public base URL;
    * `robots.txt`, as the application answers it for the site on its public
      host, naming that sitemap when the build has one;
    * `_redirects.json`, the site's redirects (`Brando.SSG.RedirectList`):
      the listed paths that answered a redirect, then the redirect rules.

  A failure there is a failed URL, under its path. `site_files: false` builds
  the listed URLs, assets and media only.
  """
  @spec build(keyword()) :: {:ok, map()} | {:error, term(), map()}
  def build(opts) when is_list(opts) do
    site = %Site{id: nil, key: "standalone", delivery_mode: :static}
    environment = %Environment{id: nil, site_id: nil, key: "live", live: true}
    build(site, environment, opts)
  end

  @spec build(Site.t(), Environment.t(), keyword()) :: {:ok, map()} | {:error, term(), map()}
  @decorate span("brando.ssg.build", site: [:site, :key], environment: [:environment, :key])
  def build(%Site{id: site_id} = site, %Environment{site_id: site_id} = environment, opts) do
    output_path = Keyword.fetch!(opts, :output_path)
    dry_run? = Keyword.get(opts, :dry_run, false)
    Tracing.set_attributes(%{"brando.dry_run": dry_run?})
    progress = Keyword.get(opts, :progress, fn _event -> :ok end)

    Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
      build_under_tenant(site, environment, output_path, opts, dry_run?, progress)
    end)
  end

  @decorate span("brando.ssg.build")
  def build(%Site{}, %Environment{}, opts),
    do: {:error, :environment_belongs_to_another_site, empty_result(opts[:output_path], false)}

  defp build_under_tenant(site, environment, output_path, opts, dry_run?, progress) do
    with :ok <- check_heex_debug_output(dry_run?),
         {:ok, opts} <- put_base_url(opts, dry_run?),
         {:ok, urls} <- get_urls(Keyword.get(opts, :ssg_module, Brando.web_module(SSG))),
         {:ok, normalized_urls} <- normalize_urls(urls),
         :ok <- prepare_output(output_path, dry_run?),
         :ok <- copy_assets(site, output_path, opts, dry_run?),
         request = if(not dry_run?, do: build_request(site, environment, opts)),
         {:ok, render_result} <- render_urls(request, normalized_urls, output_path, dry_run?, progress),
         {:ok, render_result} <- write_site_files(request, normalized_urls, output_path, opts, render_result),
         :ok <- copy_media(site, output_path, opts, dry_run?),
         {:ok, stats} <- output_stats(output_path, dry_run?) do
      result =
        render_result
        |> Map.merge(stats)
        |> Map.put(:output_path, output_path)
        |> Map.put(:dry_run, dry_run?)

      if result.failed_urls == [], do: {:ok, result}, else: {:error, :url_failures, result}
    else
      {:error, reason, result} -> {:error, reason, result}
      {:error, reason} -> {:error, reason, empty_result(output_path, dry_run?)}
    end
  end

  # HEEx writes them at compile time from this configuration; a build stores
  # pages as answered, so it does not start rather than strip them
  defp check_heex_debug_output(true), do: :ok

  defp check_heex_debug_output(false) do
    case Enum.filter(@heex_debug_options, &Application.get_env(:phoenix_live_view, &1, false)) do
      [] -> :ok
      options -> {:error, {:heex_debug_output, options}}
    end
  end

  defp put_base_url(opts, true), do: {:ok, opts}

  defp put_base_url(opts, false) do
    if Keyword.has_key?(opts, :base_url) do
      {:ok, opts}
    else
      endpoint = Keyword.get_lazy(opts, :endpoint, &Brando.endpoint/0)

      case listener_url(endpoint) do
        {:ok, base_url} -> {:ok, Keyword.merge(opts, base_url: base_url, listener: listener(endpoint, base_url))}
        :error -> {:error, {:no_http_listener, endpoint}}
      end
    end
  end

  # A build requests the listener as `localhost`, which `Plug.SSL` excludes by
  # default whatever the listener's address, and says when the endpoint's own
  # scheme is https, for an application that excludes other hosts. With that
  # header honoured, a URL built from the request names https.
  defp listener(endpoint, base_url) do
    %URI{port: port} = URI.parse(base_url)
    forwarded? = endpoint.struct_url().scheme == "https"
    forwarded = if forwarded?, do: [{"x-forwarded-proto", "https"}], else: []
    schemes = if forwarded?, do: ["http", "https"], else: ["http"]

    %{
      headers: [{"host", "localhost:#{port}"} | forwarded],
      origins: Enum.map(schemes, &origin(URI.parse("#{&1}://localhost:#{port}"))),
      # Where `force_ssl` sends a request: the host it came with, or the endpoint's
      force_ssl_hosts: ["localhost", String.downcase(endpoint.host(), :ascii)]
    }
  end

  @doc """
  The origin a build requests its pages from: `endpoint`'s running HTTP
  listener, as `http://127.0.0.1:<port>`, or on the address the listener is
  bound to when that is not a wildcard. `:error` when the endpoint is not
  running or has no HTTP listener (`server: false`, or HTTPS only).
  """
  @spec listener_url(module()) :: {:ok, String.t()} | :error
  def listener_url(endpoint) do
    case endpoint.server_info(:http) do
      {:ok, {ip, port}} when is_integer(port) and port > 0 -> {:ok, "http://#{listener_host(ip)}:#{port}"}
      _no_listener -> :error
    end
  rescue
    # An endpoint that is not running has no config table to read its adapter
    # from; a module that is not an endpoint has no server_info/1.
    _not_running in [ArgumentError, UndefinedFunctionError] -> :error
  catch
    :exit, _not_running -> :error
  end

  defp listener_host({0, 0, 0, 0}), do: "127.0.0.1"
  defp listener_host({0, 0, 0, 0, 0, 0, 0, 0}), do: "[::1]"
  defp listener_host(ip) when tuple_size(ip) == 4, do: ip |> :inet.ntoa() |> to_string()
  defp listener_host(ip) when tuple_size(ip) == 8, do: "[#{ip |> :inet.ntoa() |> to_string()}]"
  defp listener_host(_local_socket_or_unknown), do: "127.0.0.1"

  @doc "A sentence for a build's error reason, for the caller of `build/3`, which can pass `:base_url`."
  @spec error_message(term()) :: String.t()
  def error_message({:no_http_listener, endpoint}) do
    "#{inspect(endpoint)} has no HTTP listener to request the pages from. " <>
      "Run the endpoint as a server (`server: true`) with an `:http` port, or pass `:base_url`."
  end

  def error_message({:heex_debug_output, options}) do
    settings = Enum.map_join(options, ", ", &"#{&1}: true")

    "The application writes HEEx debug output into its pages (`config :phoenix_live_view, #{settings}`), " <>
      "which a static build must not contain. Turn it off where the build runs (development configs " <>
      "usually turn it on in config/dev.exs), recompile and build again."
  end

  def error_message(reason), do: inspect(reason)

  defp normalize_urls(urls) when is_list(urls) do
    urls
    |> Enum.reduce_while({:ok, []}, fn url, {:ok, normalized} ->
      case normalize_url(url) do
        {:ok, path} -> {:cont, {:ok, [path | normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, paths |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp normalize_urls(_urls), do: {:error, :invalid_url_list}

  defp normalize_url(url) when is_binary(url) do
    uri = URI.parse(url)
    path = if uri.scheme, do: uri.path, else: String.split(url, "?", parts: 2) |> hd()
    path = if path in [nil, ""], do: "/", else: path
    decoded = URI.decode(path)
    segments = String.split(decoded, "/", trim: true)

    if Enum.any?(segments, &(&1 in [".", ".."] or String.contains?(&1, ["\\", <<0>>]))) do
      {:error, {:unsafe_url_path, url}}
    else
      {:ok, "/" <> Enum.join(segments, "/")}
    end
  rescue
    _invalid_encoding -> {:error, {:invalid_url, url}}
  end

  defp normalize_url(url), do: {:error, {:invalid_url, url}}

  defp prepare_output(_output_path, true), do: :ok

  defp prepare_output(output_path, false) when is_binary(output_path) do
    expanded_path = Path.expand(output_path)

    if unsafe_output_root?(expanded_path) do
      {:error, {:unsafe_output_path, expanded_path}}
    else
      case File.rm_rf(expanded_path) do
        {:ok, _removed} -> File.mkdir_p(expanded_path)
        {:error, reason, path} -> {:error, {:prepare_output_failed, path, reason}}
      end
    end
  end

  defp prepare_output(output_path, false), do: {:error, {:invalid_output_path, output_path}}

  defp copy_assets(_site, _output_path, _opts, true), do: :ok

  @decorate span("brando.ssg.copy_assets")
  defp copy_assets(site, output_path, opts, false) do
    source = asset_source(site, opts)

    cond do
      is_nil(source) -> :ok
      File.dir?(source) -> copy_directory(source, output_path)
      true -> {:error, {:asset_source_not_found, source}}
    end
  end

  defp asset_source(_site, opts) do
    case Keyword.get(opts, :asset_set) do
      %SiteAssetSet{path: path} -> path
      _release -> Keyword.get(opts, :static_path, Path.join([File.cwd!(), "priv", "static"]))
    end
  end

  # What every request of a build carries: its origin, the signed context and
  # the listener's headers, and the site's own origins, which a page's links
  # may name
  defp build_request(site, environment, opts) do
    token = if Tenant.enabled?(), do: Context.sign(site, environment)
    base_url = Keyword.fetch!(opts, :base_url)
    listener = Keyword.get(opts, :listener)
    listener_headers = if listener, do: listener.headers, else: []
    headers = if token, do: [{Context.header(), token} | listener_headers], else: listener_headers

    %{
      base_url: base_url,
      fetcher: Keyword.get(opts, :fetcher, &default_fetcher/2),
      listener: listener,
      site_origins:
        Enum.uniq(Enum.map([base_url, Brando.Utils.hostname(), Brando.Utils.public_hostname()], &origin(URI.parse(&1)))),
      opts: [
        headers: headers,
        receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
        retry: false,
        redirect: false
      ]
    }
  end

  @decorate span("brando.ssg.render_urls")
  defp render_urls(request, urls, output_path, dry_run?, progress) do
    total = length(urls)
    Tracing.set_attributes(%{"brando.url_count": total})

    urls
    |> Enum.with_index(1)
    |> Enum.reduce({[], [], [], 0}, fn {url, index}, acc ->
      progress.({:rendering, index, total, url})
      add_rendered(acc, url, render_url(url, request, output_path, dry_run?))
    end)
    |> then(fn {failures, redirects, markdown, processed} ->
      Tracing.set_attributes(%{"brando.failed_url_count": length(failures)})

      {:ok,
       %{
         url_count: total,
         processed_urls: processed,
         failed_urls: Enum.reverse(failures),
         page_redirects: Enum.reverse(redirects),
         markdown_paths: markdown |> Enum.reverse() |> Enum.uniq()
       }}
    end)
  end

  defp add_rendered({failures, redirects, markdown, processed}, _url, {:ok, page}) do
    redirects = if page.redirect, do: [page.redirect | redirects], else: redirects
    {failures, redirects, Enum.reverse(page.markdown, markdown), processed + 1}
  end

  defp add_rendered({failures, redirects, markdown, processed}, url, {:error, reason}),
    do: {[format_failure(url, reason) | failures], redirects, markdown, processed + 1}

  defp render_url(_url, _request, _output_path, true), do: {:ok, %{redirect: nil, markdown: []}}

  defp render_url(url, request, output_path, false) do
    case fetch_path(request, url) do
      {:ok, %{status: status, body: body}, redirect} when status in 200..299 ->
        body = IO.iodata_to_binary(body)

        with :ok <- write_file(output_file(output_path, url), body) do
          {:ok, %{redirect: page_redirect(url, redirect), markdown: markdown_paths(body, url, request)}}
        end

      {:ok, %{status: status}, _redirect} ->
        {:error, {:http_status, status}}

      other ->
        fetch_error(other)
    end
  rescue
    exception -> {:error, {:request_exception, Exception.message(exception)}}
  end

  defp fetch_path(request, path, extra_headers \\ []) do
    request_url = URI.merge(ensure_trailing_slash(request.base_url), String.trim_leading(path, "/")) |> to_string()
    request = update_in(request, [:opts, :headers], &(&1 ++ extra_headers))
    fetch(request, request_url, @max_redirects)
  end

  defp fetch_error({:refused_redirect, reason}), do: {:error, reason}
  defp fetch_error({:error, reason}), do: {:error, {:request_failed, reason}}
  defp fetch_error(response), do: {:error, {:invalid_fetcher_response, response}}

  # A listed path that answered a redirect: the path it ended at, on the
  # build's origin, with the first redirect's status. The same page in
  # another form (a trailing slash, the host in capitals) is no redirect.
  defp page_redirect(_url, nil), do: nil

  defp page_redirect(url, {status, final_url}) do
    %URI{path: path, query: query} = URI.parse(final_url)
    path = if path in [nil, ""], do: "/", else: path

    cond do
      is_nil(query) and normalize_url(path) == {:ok, url} -> nil
      is_nil(query) -> %{source: url, target: path, status: status}
      true -> %{source: url, target: path <> "?" <> query, status: status}
    end
  end

  # The paths of the Markdown alternates an HTML page names on the site's own
  # origins (`Brando.SEO.Markdown`), written next to the page
  defp markdown_paths(body, url, request) do
    if Path.extname(url) in ["", ".html", ".htm"] do
      @link_tag
      |> Regex.scan(body)
      |> Enum.flat_map(fn [tag] -> markdown_href(tag, request) end)
    else
      []
    end
  end

  defp markdown_href(tag, request) do
    with "text/markdown" <- tag |> tag_attribute("type") |> String.downcase(),
         true <- "alternate" in String.split(String.downcase(tag_attribute(tag, "rel"))),
         {:ok, path} <- site_path(tag_attribute(tag, "href"), request),
         ".md" <- Path.extname(path) do
      [path]
    else
      _not_a_markdown_alternate -> []
    end
  end

  defp tag_attribute(tag, name) do
    case Regex.run(Map.fetch!(@tag_attributes, name), tag, capture: :all_but_first) do
      nil -> ""
      values -> values |> Enum.find("", &(&1 != "")) |> String.replace("&amp;", "&")
    end
  end

  defp site_path(href, request) do
    uri = URI.parse(href)

    cond do
      is_nil(uri.scheme) and is_nil(uri.host) and String.starts_with?(href, "/") and
          not String.starts_with?(href, "//") ->
        normalize_url(href)

      uri.scheme in ["http", "https"] and origin(uri) in request.site_origins ->
        normalize_url(uri.path || "/")

      true ->
        :error
    end
  rescue
    _invalid -> :error
  end

  defp write_site_files(nil, _urls, _output_path, _opts, result), do: {:ok, without_page_data(result)}

  @decorate span("brando.ssg.write_site_files")
  defp write_site_files(request, urls, output_path, opts, result) do
    if Keyword.get(opts, :site_files, true) do
      markdown_failures =
        Enum.flat_map(result.markdown_paths -- urls, &fetch_file(request, &1, output_file(output_path, &1)))

      {sitemap?, sitemap_failures} = write_sitemap(output_path, opts)
      sitemap_header = [{Context.sitemap_header(), if(sitemap?, do: "1", else: "0")}]

      failures =
        markdown_failures ++
          fetch_not_found_page(request, output_path) ++
          sitemap_failures ++
          fetch_file(request, "/robots.txt", Path.join(output_path, "robots.txt"), sitemap_header)

      built_paths = urls ++ result.markdown_paths

      with :ok <- write_redirects(output_path, built_paths, result.page_redirects) do
        {:ok, %{without_page_data(result) | failed_urls: result.failed_urls ++ failures}}
      end
    else
      {:ok, without_page_data(result)}
    end
  end

  defp without_page_data(result), do: Map.drop(result, [:page_redirects, :markdown_paths])

  # A file the application answers with 2xx: [] when written, else its failure
  defp fetch_file(request, path, target, extra_headers \\ []) do
    case fetch_path(request, path, extra_headers) do
      {:ok, %{status: status, body: body}, _redirect} when status in 200..299 ->
        write_result(path, write_file(target, IO.iodata_to_binary(body)))

      {:ok, %{status: status}, _redirect} ->
        [format_failure(path, {:http_status, status})]

      other ->
        {:error, reason} = fetch_error(other)
        [format_failure(path, reason)]
    end
  rescue
    exception -> [format_failure(path, {:request_exception, Exception.message(exception)})]
  end

  # The application answers a missing path with the site's error page and 404,
  # which is the answer wanted here
  defp fetch_not_found_page(request, output_path) do
    case fetch_path(request, @not_found_path) do
      {:ok, %{status: 404, body: body}, _redirect} ->
        write_result(@not_found_path, write_file(Path.join(output_path, "404.html"), IO.iodata_to_binary(body)))

      {:ok, %{status: status}, _redirect} ->
        [format_failure(@not_found_path, {:not_found_status, status})]

      other ->
        {:error, reason} = fetch_error(other)
        [format_failure(@not_found_path, reason)]
    end
  rescue
    exception -> [format_failure(@not_found_path, {:request_exception, Exception.message(exception)})]
  end

  defp write_result(_path, :ok), do: []
  defp write_result(path, {:error, reason}), do: [format_failure(path, reason)]

  # {whether the build has a sitemap index, failures}
  defp write_sitemap(output_path, opts) do
    module = Keyword.get_lazy(opts, :sitemap_module, &Brando.sitemap/0)

    case Brando.Sitemap.write_static(Path.join(output_path, "sitemaps"), module: module) do
      {:ok, _files} -> {File.regular?(Path.join(output_path, @sitemap_index)), []}
      {:error, reason} -> {false, [format_failure("/" <> @sitemap_index, {:sitemap_failed, reason})]}
    end
  end

  defp write_redirects(output_path, built_paths, page_redirects) do
    target = Path.join(output_path, @redirects_file)
    json = Jason.encode_to_iodata!(Brando.SSG.RedirectList.build(page_redirects, built_paths), pretty: true)

    case File.write(target, json) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, target, reason}}
    end
  end

  defp default_fetcher(url, opts), do: Req.get(url, opts)

  # Req would follow a redirect to any host with the signed header still on the
  # request, and the caller could not tell. So a build follows redirects itself.
  # `repeating?`: the request answered a redirect to itself, followed once.
  # `{:ok, response, redirect}`: `redirect` is nil, or the first redirect's
  # status and the URL the answer came from when the request was redirected
  defp fetch(request, url, redirects_left, repeating? \\ false, first_status \\ nil) do
    case request.fetcher.(url, request.opts) do
      {:ok, %{status: status} = response} when status in @redirect_statuses ->
        case redirect_location(response) do
          nil ->
            {:ok, response, nil}

          location ->
            target = URI.merge(url, location)
            follow_redirect(request, URI.parse(url), target, status, redirects_left, repeating?, first_status || status)
        end

      {:ok, %{status: _status} = response} ->
        {:ok, response, if(first_status, do: {first_status, url})}

      result ->
        result
    end
  end

  defp follow_redirect(request, %URI{} = source, %URI{} = target, status, redirects_left, repeating?, first_status) do
    next = on_listener(target, source, request.listener)
    to_itself? = to_string(next) == to_string(source)

    cond do
      origin(next) != origin(source) ->
        {:refused_redirect, refusal(request.listener, source, target, status)}

      to_itself? and repeating? and force_ssl_redirect?(request.listener, source, target) ->
        {:refused_redirect, {:https_redirect, status, target}}

      redirects_left == 0 ->
        {:refused_redirect, :too_many_redirects}

      true ->
        fetch(request, to_string(next), redirects_left - 1, to_itself?, first_status)
    end
  end

  # The host the build sends names the listener too, on https when the build
  # says so: `localhost` may not resolve to the address it listens on, so the
  # request goes there, over the listener's plain http.
  defp on_listener(target, _source, nil), do: target

  defp on_listener(target, source, listener) do
    if origin(target) in listener.origins,
      do: %URI{target | scheme: source.scheme, host: source.host, port: source.port},
      else: target
  end

  defp refusal(listener, source, target, status) do
    if force_ssl_redirect?(listener, source, target),
      do: {:https_redirect, status, target},
      else: {:redirect_off_origin, status, target}
  end

  # What `Plug.SSL` answers on a build that chose the listener itself: the same
  # path on https, under the host the build sent or the endpoint's own
  defp force_ssl_redirect?(nil, _source, _target), do: false

  defp force_ssl_redirect?(listener, source, target) do
    target.scheme == "https" and target.path == source.path and
      is_binary(target.host) and String.downcase(target.host, :ascii) in listener.force_ssl_hosts
  end

  # Userinfo counts: a target naming the origin's host as userinfo has another
  # host, and one adding credentials is not a page of this site. A merged
  # protocol-relative target has no port, and a target with no host has nil here.
  defp origin(%URI{} = uri) do
    host = uri.host && String.downcase(uri.host, :ascii)
    {uri.scheme, uri.userinfo, host, uri.port || URI.default_port(uri.scheme)}
  end

  defp redirect_location(%{headers: headers}) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(to_string(name)) == "location", do: value |> List.wrap() |> List.first()
    end)
  end

  defp redirect_location(_response), do: nil

  defp write_file(target, body) do
    with :ok <- File.mkdir_p(Path.dirname(target)),
         :ok <- File.write(target, body) do
      :ok
    else
      {:error, reason} -> {:error, {:write_failed, target, reason}}
    end
  end

  defp output_file(output_path, "/"), do: Path.join(output_path, "index.html")

  defp output_file(output_path, url) do
    relative = String.trim_leading(url, "/")

    if Path.extname(relative) == "" do
      Path.join([output_path, relative, "index.html"])
    else
      Path.join(output_path, relative)
    end
  end

  defp copy_media(_site, _output_path, _opts, true), do: :ok

  @decorate span("brando.ssg.copy_media")
  defp copy_media(site, output_path, opts, false) do
    source = Keyword.get(opts, :media_path, media_source(site))

    if File.dir?(source) do
      copy_directory(source, Path.join(output_path, "media"))
    else
      :ok
    end
  end

  defp media_source(site) do
    if Tenant.mode() == :multi, do: Storage.media_root(site), else: Brando.config(:media_path)
  end

  defp copy_directory(source, destination) do
    with :ok <- validate_copy_source(source),
         :ok <- File.mkdir_p(Path.dirname(destination)),
         {:ok, _files} <- File.cp_r(source, destination) do
      :ok
    else
      {:error, {:unsupported_source_file, _path}} = error -> error
      {:error, {:source_file_stat_failed, _path, _reason}} = error -> error
      {:error, {:source_directory_read_failed, _path, _reason}} = error -> error
      {:error, reason, path} -> {:error, {:copy_failed, path, reason}}
      {:error, reason} -> {:error, {:copy_failed, source, reason}}
    end
  end

  defp validate_copy_source(directory) do
    case File.ls(directory) do
      {:ok, entries} -> validate_copy_entries(directory, entries)
      {:error, reason} -> {:error, {:source_directory_read_failed, directory, reason}}
    end
  end

  defp validate_copy_entries(directory, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case validate_copy_entry(Path.join(directory, entry)) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_copy_entry(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> validate_copy_source(path)
      {:ok, %{type: :regular}} -> :ok
      {:ok, _symlink_or_special} -> {:error, {:unsupported_source_file, path}}
      {:error, reason} -> {:error, {:source_file_stat_failed, path, reason}}
    end
  end

  defp output_stats(_output_path, true), do: {:ok, %{file_count: 0, total_size: 0}}

  defp output_stats(output_path, false) do
    output_path
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reduce_while({:ok, 0, 0}, fn path, {:ok, count, size} ->
      case File.stat(path) do
        {:ok, %{type: :regular, size: file_size}} -> {:cont, {:ok, count + 1, size + file_size}}
        {:ok, _other} -> {:cont, {:ok, count, size}}
        {:error, reason} -> {:halt, {:error, {:stat_failed, path, reason}}}
      end
    end)
    |> case do
      {:ok, count, size} -> {:ok, %{file_count: count, total_size: size}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_trailing_slash(url), do: String.trim_trailing(url, "/") <> "/"

  defp unsafe_output_root?(path) do
    forbidden = ["/", Path.expand(File.cwd!()), System.user_home(), System.tmp_dir!()]
    path in Enum.reject(forbidden, &is_nil/1)
  end

  defp format_failure(url, {:http_status, status}), do: "#{url} (HTTP #{status})"

  # The target comes from the response and this text goes to the database: only
  # its origin, since a URI with no host prints its raw authority, and inspected,
  # since a header can hold invalid UTF-8.
  defp format_failure(url, {:redirect_off_origin, status, %URI{} = target}) do
    target_origin = to_string(%URI{scheme: target.scheme, host: target.host, port: target.port})
    "#{url} (HTTP #{status} redirect to another origin: #{inspect(target_origin)})"
  end

  defp format_failure(url, {:https_redirect, status, %URI{} = target}) do
    target_origin = to_string(%URI{scheme: target.scheme, host: target.host, port: target.port})

    "#{url} (HTTP #{status} redirect to #{inspect(target_origin)}: likely the endpoint's `force_ssl` " <>
      "redirecting the build's requests. Exclude the host `localhost` (its `:exclude`), or add " <>
      "`rewrite_on: [:x_forwarded_proto]` with an `https` endpoint URL)"
  end

  defp format_failure(url, {:not_found_status, status}),
    do: "#{url} (HTTP #{status} where the site's error page answers 404: no 404.html written)"

  defp format_failure(url, {:sitemap_failed, message}) when is_binary(message),
    do: "#{url} (the sitemap failed: #{message})"

  defp format_failure(url, reason), do: "#{url} (#{inspect(reason)})"

  defp empty_result(output_path, dry_run?) do
    %{
      output_path: output_path,
      dry_run: dry_run?,
      file_count: 0,
      total_size: 0,
      url_count: 0,
      processed_urls: 0,
      failed_urls: []
    }
  end
end
