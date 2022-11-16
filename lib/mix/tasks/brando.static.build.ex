defmodule Mix.Tasks.Brando.Static.Build do
  use Mix.Task

  @shortdoc "Build static files and digest"

  def run(args) do
    {parsed_opts, _, _} = OptionParser.parse(args, switches: [verbose: :boolean, clean: :boolean])

    opts = (is_nil(parsed_opts[:verbose]) && []) || [into: IO.binstream(:stdio, :line)]

    if parsed_opts[:clean] == true do
      File.rm_rf!("priv/static")
    end

    Mix.shell().info("==> Build backend assets")
    System.cmd("sh", ["-c", "cd assets/backend; yarn build"], opts)

    Mix.shell().info("==> Build frontend assets")
    System.cmd("sh", ["-c", "cd assets/frontend; yarn build"], opts)

    Mix.shell().info("=> Digesting assets")
    Mix.Task.run("phx.digest")
    Mix.shell().info("==> Assets built")
  end
end
