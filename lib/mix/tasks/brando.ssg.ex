defmodule Mix.Tasks.Brando.Ssg do
  use Mix.Task

  @shortdoc "Static site generation"

  @moduledoc """
  Static site generation

      mix brando.ssg

  """
  @default_host "http://localhost:4000"
  @spec run(any) :: no_return
  def run(_) do
    Application.put_env(:phoenix, :serve_endpoints, true)
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Static Site Generator
    ------------------------------
    """)

    ssg_path = Path.join([File.cwd!(), "ssg"])
    {:ok, ssg_urls} = Brando.SSG.get_urls()

    Application.put_env(:brando, :ssg_run, true)
    Application.put_env(Brando.config(:otp_app), :hmr, false)
    Application.put_env(Brando.config(:otp_app), :show_breakpoint_debug, false)

    if Mix.shell().yes?("\nGenerate static files? (cleans priv/static first)") do
      # delete static
      static_path = Path.join([File.cwd!(), "priv", "static"])
      File.rm_rf!(static_path)
      # generate static files
      assets_path = Path.join([File.cwd!(), "assets", "frontend"])
      vite_path = Path.join([File.cwd!(), "assets", "frontend", "node_modules", ".bin", "vite"])
      System.cmd(vite_path, ["build"], cd: assets_path)
      File.cp_r!(static_path, ssg_path)
    end

    :inets.start()

    if Mix.shell().yes?("\nGenerate HTML?") do
      for url <- ssg_urls do
        # we just need to access the url to generate html
        full_url = Path.join([@default_host, url])
        :httpc.request(String.to_charlist(full_url))
      end
    end

    if Mix.shell().yes?("\nCopy media directory?") do
      media_path = Path.join([File.cwd!(), "media"])
      File.cp_r!(media_path, Path.join([ssg_path, "media"]))
    end
  end
end
