defmodule Mix.Tasks.Brando.Ssg do
  @shortdoc "Build a static site interactively"

  @moduledoc """
  Builds a static snapshot through the same callable API used by the publishing
  worker.

      mix brando.ssg
      mix brando.ssg --yes
      mix brando.ssg --site acme --environment staging --output ./ssg
      mix brando.ssg --site acme --dry-run

  Options:

    * `--yes` (or `--force`) - skip the confirmation prompt. Without it and
      without a terminal to answer on, the task builds nothing and exits
      non-zero
    * `--site` - site key in multi-site mode
    * `--environment` - environment key (defaults to the live environment)
    * `--output` - output directory. By default, with several sites, the
      site's own `sites/<key>/ssg/manual` (beside the background builds in
      `sites/<key>/ssg/builds`); otherwise the application's SSG path
      (`./ssg`, or the SSG module's `render_path`)
    * `--dry-run` - resolve URLs without requesting or writing files
    * `--no-compile-assets` - use existing release assets without running Vite

  The task starts the endpoint as a server on the port the project configures
  for it, without its watchers (no Vite dev servers), and requests every page
  from that listener. An endpoint with no `:http` configuration cannot be
  built from: the task says so before it requests anything.

  The task remains compatible with non-tenant applications. Tenant builds may
  target any named environment, whether or not it has a public domain.
  """

  use Mix.Task

  alias Brando.Assets.SiteAssets
  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.SSG
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  @switches [
    yes: :boolean,
    force: :boolean,
    site: :string,
    environment: :string,
    output: :string,
    dry_run: :boolean,
    compile_assets: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: @switches)
    # The build requests every page from the running endpoint's listener (see
    # `Brando.SSG.listener_url/1`), so unlike the other tasks this one must
    # listen. It needs no Vite dev servers, which the watchers would start.
    Application.put_env(:phoenix, :serve_endpoints, true)
    without_watchers(Brando.otp_app(), Brando.endpoint())
    Application.put_env(:logger, :level, :error)

    Mix.shell().info("""

    ------------------------------
    % Brando Static Site Generator
    ------------------------------
    """)

    Mix.Tasks.Run.run([])

    {site, environment} = select_context!(opts)
    output_path = opts[:output] |> Kernel.||(default_output(site)) |> Path.expand()

    asset_set =
      if site && Tenant.mode() == :multi,
        do: SiteAssets.effective_set(site, environment),
        else: SiteAssets.effective_set(nil, environment)

    dry_run? = Keyword.get(opts, :dry_run, false)

    show_plan(site, environment, asset_set, output_path, dry_run?)

    if Mix.Brando.confirm?("\nGenerate this static snapshot?", opts) do
      maybe_compile_assets(asset_set, opts, dry_run?)
      result = run_build(site, environment, asset_set, output_path, dry_run?)
      report_result!(result)
    else
      Mix.shell().info("Static generation cancelled.")
    end
  end

  defp without_watchers(otp_app, endpoint) do
    case Application.get_env(otp_app, endpoint) do
      config when is_list(config) -> Application.put_env(otp_app, endpoint, Keyword.put(config, :watchers, []))
      _none -> :ok
    end
  end

  # With several sites, one shared directory would hold whichever site was
  # built last: each site's own goes beside its background builds.
  defp default_output(%Site{} = site) do
    if Tenant.mode() == :multi,
      do: Path.join([Storage.site_root(site), "ssg", "manual"]),
      else: SSG.get_root_path()
  end

  defp default_output(nil), do: SSG.get_root_path()

  defp select_context!(opts) do
    case Tenant.mode() do
      :none ->
        {nil, nil}

      mode when mode in [:single, :multi] ->
        site_key =
          if mode == :single,
            do: Brando.config(:site_key),
            else: opts[:site] || Mix.raise("--site is required in multi-site mode")

        with %Site{} = site <- Registry.get_site_by_key(site_key),
             %Environment{} = environment <- select_environment(site, opts[:environment]) do
          {site, environment}
        else
          _ -> Mix.raise("Could not resolve site/environment for #{inspect(site_key)}")
        end
    end
  end

  defp select_environment(site, nil), do: Cache.get_live_env(site.key)
  defp select_environment(site, key), do: Registry.get_environment_by_key(site, key)

  defp show_plan(site, environment, asset_set, output_path, dry_run?) do
    Mix.shell().info("Mode: #{if dry_run?, do: "dry run", else: "build"}")
    Mix.shell().info("Site: #{if site, do: site.name <> " (" <> site.key <> ")", else: "standalone"}")
    Mix.shell().info("Environment: #{if environment, do: environment.name, else: "public"}")
    Mix.shell().info("Assets: #{if asset_set, do: asset_set.name, else: "current release"}")
    Mix.shell().info("Output: #{output_path}")
  end

  defp maybe_compile_assets(%{path: _uploaded_set}, _opts, _dry_run?), do: :ok
  defp maybe_compile_assets(_asset_set, _opts, true), do: :ok

  defp maybe_compile_assets(nil, opts, false) do
    if Keyword.get(opts, :compile_assets, true) do
      vite = Path.join([File.cwd!(), "assets", "frontend", "node_modules", ".bin", "vite"])
      assets_path = Path.join([File.cwd!(), "assets", "frontend"])

      unless File.regular?(vite) do
        Mix.raise("Vite executable not found at #{vite}; pass --no-compile-assets to use existing priv/static")
      end

      Mix.shell().info("Building release frontend assets…")

      case System.cmd(vite, ["build"], cd: assets_path, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, status} -> Mix.raise("Vite build failed (#{status}):\n#{output}")
      end
    end
  end

  defp run_build(nil, nil, asset_set, output_path, dry_run?) do
    SSG.build(output_path: output_path, asset_set: asset_set, dry_run: dry_run?)
  end

  defp run_build(site, environment, asset_set, output_path, dry_run?) do
    SSG.build(site, environment,
      output_path: output_path,
      asset_set: asset_set,
      dry_run: dry_run?
    )
  end

  defp report_result!({:ok, result}) do
    Mix.shell().info(
      "Generated #{result.url_count} URLs and #{result.file_count} files (#{result.total_size} bytes) in #{result.output_path}"
    )
  end

  defp report_result!({:error, reason, result}) do
    Enum.each(result.failed_urls, &Mix.shell().error("Failed: #{&1}"))
    Mix.raise("Static generation failed: #{SSG.error_message(reason)}")
  end
end
