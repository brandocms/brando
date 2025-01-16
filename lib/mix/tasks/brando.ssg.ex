defmodule Mix.Tasks.Brando.Ssg do
  use Mix.Task

  @shortdoc "Static site generation"

  @moduledoc """
  Static site generation

      mix brando.ssg

  """
  @default_host "http://localhost:4000"
  def run(_) do
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.shell().info("""

    ------------------------------
    % Brando Static Site Generator
    ------------------------------
    """)

    Mix.Tasks.Run.run([])
    :inets.start()

    ssg_path = Brando.SSG.get_root_path()
    File.mkdir_p!(ssg_path)
    {:ok, ssg_urls} = Brando.SSG.get_urls()

    Application.put_env(:brando, :ssg_run, :css)
    Application.put_env(Brando.config(:otp_app), :hmr, false)
    Application.put_env(Brando.config(:otp_app), :show_breakpoint_debug, false)

    if Mix.shell().yes?("\nGenerate static files? (cleans priv/static first)") do
      # delete static
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

    if Mix.shell().yes?("\nGenerate HTML?") do
      Application.put_env(:brando, :ssg_run, :html)

      for url <- ssg_urls do
        # we just need to access the url to generate html
        full_url = Path.join([@default_host, url])
        :httpc.request(String.to_charlist(full_url))
      end
    end

    Application.put_env(:brando, :ssg_run, :media)

    if Mix.shell().yes?("\nCopy media directory?") do
      media_path = Path.join([File.cwd!(), "media"])
      File.cp_r!(media_path, Path.join([ssg_path, "media"]))
    end

    Application.put_env(:brando, :ssg_run, :normal)
  end
end
