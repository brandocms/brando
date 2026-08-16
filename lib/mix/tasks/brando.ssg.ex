defmodule Mix.Tasks.Brando.Ssg do
  @shortdoc "Static site generation"

  @moduledoc """
  Static site generation

      mix brando.ssg
      mix brando.ssg --force
      mix brando.ssg --site acme --force

  Options:

    * `--force` - Skip all prompts and run all steps
    * `--site` - Site key to export in multi-site mode

  """
  use Mix.Task

  @default_host "http://localhost:4000"
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [force: :boolean, site: :string])
    force? = Keyword.get(opts, :force, false)
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.shell().info("""

    ------------------------------
    % Brando Static Site Generator
    ------------------------------
    """)

    Mix.Tasks.Run.run([])
    :inets.start()
    site = select_tenant!(opts[:site])

    ssg_path = Brando.SSG.get_root_path()
    File.mkdir_p!(ssg_path)
    {:ok, ssg_urls} = Brando.SSG.get_urls()

    Application.put_env(:brando, :ssg_run, :css)
    Application.put_env(Brando.config(:otp_app), :hmr, false)
    Application.put_env(Brando.config(:otp_app), :show_breakpoint_debug, false)

    uploaded_assets_path = Brando.Assets.SiteAssets.current_root()

    if force? or Mix.shell().yes?("\nGenerate static files?") do
      copy_or_build_assets(uploaded_assets_path, ssg_path)
    end

    if force? or Mix.shell().yes?("\nGenerate HTML?") do
      Application.put_env(:brando, :ssg_run, :html)

      for url <- ssg_urls do
        # we just need to access the url to generate html
        full_url = Path.join([@default_host, url])
        :httpc.request(String.to_charlist(full_url))
      end
    end

    Application.put_env(:brando, :ssg_run, :media)

    if force? or Mix.shell().yes?("\nCopy media directory?") do
      media_path = media_path(site)
      File.cp_r!(media_path, Path.join([ssg_path, "media"]))
    end

    Application.put_env(:brando, :ssg_run, :normal)
  end

  defp copy_or_build_assets(nil, ssg_path) do
    static_path = Path.join([File.cwd!(), "priv", "static"])

    IO.write([
      IO.ANSI.blue(),
      "* ",
      IO.ANSI.reset(),
      "Deleting static files... "
    ])

    File.rm_rf!(static_path)
    IO.write([IO.ANSI.green(), "done!\n", IO.ANSI.reset()])
    # generate static files
    assets_path = Path.join([File.cwd!(), "assets", "frontend"])
    vite_path = Path.join([File.cwd!(), "assets", "frontend", "node_modules", ".bin", "vite"])

    IO.write([
      IO.ANSI.blue(),
      "* ",
      IO.ANSI.reset(),
      "Building static files... "
    ])

    System.cmd(vite_path, ["build"], cd: assets_path)
    IO.write([IO.ANSI.green(), "done!\n", IO.ANSI.reset()])

    IO.write([
      IO.ANSI.blue(),
      "* ",
      IO.ANSI.reset(),
      "Copying static files... "
    ])

    File.cp_r!(static_path, ssg_path)
    IO.write([IO.ANSI.green(), "done!\n", IO.ANSI.reset()])
  end

  defp copy_or_build_assets(uploaded_assets_path, ssg_path) do
    IO.write([
      IO.ANSI.blue(),
      "* ",
      IO.ANSI.reset(),
      "Copying active uploaded asset set... "
    ])

    File.cp_r!(uploaded_assets_path, ssg_path)
    IO.write([IO.ANSI.green(), "done!\n", IO.ANSI.reset()])
  end

  defp select_tenant!(requested_site_key) do
    case Brando.Tenant.mode() do
      :none ->
        nil

      mode when mode in [:single, :multi] ->
        site_key =
          if mode == :single,
            do: Brando.config(:site_key),
            else: requested_site_key || Mix.raise("--site is required in multi-site mode")

        with %Brando.Sites.Site{} = site <- Brando.Tenant.Registry.get_site_by_key(site_key),
             %Brando.Environments.Environment{} = environment <-
               Brando.Tenant.Cache.get_live_env(site.key) do
          Brando.Tenant.put_prefix(Brando.Tenant.prefix(site, environment))
          site
        else
          _ -> Mix.raise("Could not resolve an active site and live environment for #{inspect(site_key)}")
        end
    end
  end

  defp media_path(nil), do: Brando.config(:media_path)

  defp media_path(site) do
    if Brando.Tenant.mode() == :multi,
      do: Brando.Tenant.Storage.media_root(site),
      else: Brando.config(:media_path)
  end
end
