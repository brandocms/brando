defmodule Brando.SSG do
  @moduledoc """
  Static-site generation primitives and callable build API.

  Applications declare URLs in their web `SSG` module with `urls/2`. Brando's
  publish lifecycle calls `build/3` for a particular site and named content
  environment; `mix brando.ssg` remains available as an interactive wrapper.
  """

  alias Brando.Assets.SiteAssetSet
  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.SSG.Context
  alias Brando.Tenant
  alias Brando.Tenant.Storage

  @default_base_url "http://localhost:4000"
  @default_receive_timeout 60_000

  @doc """
  Declares a group of paths in the application's web SSG module.

  Create `lib/my_app_web/ssg.ex`:

  ```
      defmodule MyAppWeb.SSG do
        import Brando.SSG

        urls :pages do
          ["/", "/projects", "/about"]
        end

        urls :projects do
          %{status: :published}
          |> Projects.list_projects!()
          |> Enum.map(&Projects.Project.__absolute_url__/1)
        end
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

  The injectable `:fetcher` option has arity two (`url`, request options) and
  is intended for tests or custom transports.
  """
  @spec build(keyword()) :: {:ok, map()} | {:error, term(), map()}
  def build(opts) when is_list(opts) do
    site = %Site{id: nil, key: "standalone", delivery_mode: :static}
    environment = %Environment{id: nil, site_id: nil, key: "live", live: true}
    build(site, environment, opts)
  end

  @spec build(Site.t(), Environment.t(), keyword()) :: {:ok, map()} | {:error, term(), map()}
  def build(%Site{id: site_id} = site, %Environment{site_id: site_id} = environment, opts) do
    output_path = Keyword.fetch!(opts, :output_path)
    dry_run? = Keyword.get(opts, :dry_run, false)
    progress = Keyword.get(opts, :progress, fn _event -> :ok end)

    Tenant.with_prefix(Tenant.prefix(site, environment), fn ->
      build_under_tenant(site, environment, output_path, opts, dry_run?, progress)
    end)
  end

  def build(%Site{}, %Environment{}, opts),
    do: {:error, :environment_belongs_to_another_site, empty_result(opts[:output_path], false)}

  defp build_under_tenant(site, environment, output_path, opts, dry_run?, progress) do
    with {:ok, urls} <- get_urls(Keyword.get(opts, :ssg_module, Brando.web_module(SSG))),
         {:ok, normalized_urls} <- normalize_urls(urls),
         :ok <- prepare_output(output_path, dry_run?),
         :ok <- copy_assets(site, output_path, opts, dry_run?),
         {:ok, render_result} <-
           render_urls(site, environment, normalized_urls, output_path, opts, dry_run?, progress),
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

  defp render_urls(site, environment, urls, output_path, opts, dry_run?, progress) do
    token = if Tenant.enabled?(), do: Context.sign(site, environment)
    total = length(urls)

    urls
    |> Enum.with_index(1)
    |> Enum.reduce({[], 0}, fn {url, index}, {failures, processed} ->
      progress.({:rendering, index, total, url})

      case render_url(url, token, output_path, opts, dry_run?) do
        :ok -> {failures, processed + 1}
        {:error, reason} -> {[format_failure(url, reason) | failures], processed + 1}
      end
    end)
    |> then(fn {failures, processed} ->
      {:ok,
       %{
         url_count: total,
         processed_urls: processed,
         failed_urls: Enum.reverse(failures)
       }}
    end)
  end

  defp render_url(_url, _token, _output_path, _opts, true), do: :ok

  defp render_url(url, token, output_path, opts, false) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    request_url = URI.merge(ensure_trailing_slash(base_url), String.trim_leading(url, "/")) |> to_string()
    fetcher = Keyword.get(opts, :fetcher, &default_fetcher/2)

    headers = if token, do: [{Context.header(), token}], else: []

    request_opts = [
      headers: headers,
      receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout),
      retry: false
    ]

    case fetcher.(request_url, request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        write_response(output_path, url, body)

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}

      response ->
        {:error, {:invalid_fetcher_response, response}}
    end
  rescue
    exception -> {:error, {:request_exception, Exception.message(exception)}}
  end

  defp default_fetcher(url, opts), do: Req.get(url, opts)

  defp write_response(output_path, url, body) do
    target = output_file(output_path, url)

    with :ok <- File.mkdir_p(Path.dirname(target)),
         :ok <- File.write(target, format_body(body, url)) do
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

  defp format_body(body, url) do
    body = IO.iodata_to_binary(body)

    if Path.extname(url) in ["", ".html", ".htm"] do
      try do
        Phoenix.LiveView.HTMLFormatter.format(body, [])
      rescue
        _not_html -> body
      end
    else
      body
    end
  end

  defp copy_media(_site, _output_path, _opts, true), do: :ok

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
