defmodule Mix.Tasks.Brando.Assets.Setup do
  use Mix.Task

  @shortdoc "Links the selected BrandoJS source through Yalc and builds consumer assets"
  @moduledoc """
  Installs and builds the application's Brando assets during local development.

      mix brando.assets.setup
      mix brando.assets.setup --no-build
      mix brando.assets.setup --source /path/to/matching/brando/assets

  Uses the selected Brando dependency's `assets` directory by default. Hex
  packages do not include the developing JS source: supply `--source` pointing
  to a matching checkout in that case. Keep the Elixir and JS revisions aligned.

  Publishes to a project-local Yalc store under `_build`, adds BrandoJS to the
  backend, and runs pnpm install in both Vite consumers. Unless `--no-build` is
  supplied, builds both consumers. It does not run a standalone framework build.
  Node.js, pnpm and Yalc must already be installed.

  This is an operational task. The Igniter installer only generates source;
  it never runs this command as part of accepting a diff.
  """

  @impl Mix.Task
  def run(argv) do
    {options, rest, invalid} = OptionParser.parse(argv, strict: [source: :string, build: :boolean])
    if rest != [] || invalid != [], do: Mix.raise("Usage: mix brando.assets.setup [--source PATH] [--no-build]")

    source = source_path(options)
    backend = Path.expand("assets/backend")
    frontend = Path.expand("assets/frontend")
    store = Mix.Project.build_path() |> Path.join("brando_yalc") |> Path.expand()

    Enum.each([source, backend, frontend], fn path ->
      unless File.regular?(Path.join(path, "package.json")),
        do:
          Mix.raise(
            "Missing #{path}/package.json. Generate the assets first; use --source for a matching BrandoJS checkout."
          )
    end)

    unless source |> Path.join("package.json") |> File.read!() |> Jason.decode!() |> Map.get("name") ==
             "@brandocms/brandojs" do
      Mix.raise("--source must point to the @brandocms/brandojs package directory.")
    end

    Enum.each(["node", "pnpm", "yalc"], fn tool ->
      unless System.find_executable(tool),
        do: Mix.raise("#{tool} is required by mix brando.assets.setup but was not found on PATH.")
    end)

    run!("yalc", ["publish", "--store-folder", store], source)
    run!("yalc", ["add", "@brandocms/brandojs", "--store-folder", store], backend)

    Enum.each([backend, frontend], fn path ->
      run!("pnpm", ["install"], path)
      if options[:build] != false, do: run!("pnpm", ["build"], path)
    end)
  end

  defp source_path(options) do
    case options[:source] do
      nil ->
        case Mix.Project.deps_paths()[:brando] do
          nil -> Mix.raise("Brando must be a dependency of this application, or supply --source PATH.")
          path -> Path.join(path, "assets") |> Path.expand()
        end

      path ->
        Path.expand(path)
    end
  end

  defp run!(executable, args, directory) do
    Mix.shell().info("Running #{executable} #{Enum.join(args, " ")} in #{directory}")
    {_, status} = System.cmd(executable, args, cd: directory, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

    if status != 0,
      do:
        Mix.raise(
          "#{executable} failed in #{directory} (exit #{status}). Fix the reported error and rerun mix brando.assets.setup."
        )
  end
end
