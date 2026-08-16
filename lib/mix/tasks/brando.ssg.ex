defmodule Mix.Tasks.Brando.Ssg do
  @shortdoc "Build a static site interactively"

  @moduledoc """
  Builds a static snapshot through the same callable API used by the publishing
  worker.

      mix brando.ssg
      mix brando.ssg --force
      mix brando.ssg --site acme --environment staging --output ./ssg
      mix brando.ssg --site acme --dry-run

  Options:

    * `--force` - skip confirmation prompts
    * `--site` - site key in multi-site mode
    * `--environment` - environment key (defaults to the live environment)
    * `--output` - output directory (defaults to the application's SSG path)
    * `--dry-run` - resolve URLs without requesting or writing files
    * `--no-compile-assets` - use existing release assets without running Vite

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

  @switches [
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
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.shell().info("""

    ------------------------------
    % Brando Static Site Generator
    ------------------------------
    """)

    Mix.Tasks.Run.run([])

    {site, environment} = select_context!(opts)
    output_path = opts[:output] |> Kernel.||(SSG.get_root_path()) |> Path.expand()

    asset_set =
      if site && Tenant.mode() == :multi,
        do: SiteAssets.active_set(site),
        else: SiteAssets.active_set()

    dry_run? = Keyword.get(opts, :dry_run, false)

    show_plan(site, environment, asset_set, output_path, dry_run?)

    if Keyword.get(opts, :force, false) or Mix.shell().yes?("\nGenerate this static snapshot?") do
      maybe_compile_assets(asset_set, opts, dry_run?)
      result = run_build(site, environment, asset_set, output_path, dry_run?)
      report_result!(result)
    else
      Mix.shell().info("Static generation cancelled.")
    end
  end

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
    Mix.raise("Static generation failed: #{inspect(reason)}")
  end
end
