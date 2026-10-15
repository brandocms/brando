defmodule Mix.Tasks.Brando.Assets.Setup do
  use Mix.Task

  @shortdoc "Links the selected BrandoJS source through Yalc and builds consumer assets"
  @moduledoc """
  Installs and builds the application's Brando assets during local development.

      mix brando.assets.setup
      mix brando.assets.setup --no-build
      mix brando.assets.setup --backend-only
      mix brando.assets.setup --source /path/to/matching/brando/assets

  Uses the selected Brando dependency's `assets` directory by default. Hex
  packages do not include the developing JS source: supply `--source` pointing
  to a matching checkout in that case. Keep the Elixir and JS revisions aligned.

  Publishes to a project-local Yalc store under `_build`, adds BrandoJS to the
  backend, and runs pnpm install in both Vite consumers. Unless `--no-build` is
  supplied, builds both consumers. It does not run a standalone framework build.
  Node.js, pnpm and Yalc must already be installed. Building the admin also
  needs the native EuropaCSS compiler, `europa`, and its Vite plugin, which the
  backend installs from `.yalc` until they are published; the task stops with
  instructions when either is missing.

  `--backend-only` installs and builds the admin (`assets/backend`) alone, for
  applications whose frontend uses another package manager or build.

  This is an operational task. The Igniter installer only generates source;
  it never runs this command as part of accepting a diff.
  """

  @impl Mix.Task
  def run(argv) do
    {options, rest, invalid} =
      OptionParser.parse(argv, strict: [source: :string, build: :boolean, backend_only: :boolean])

    if rest != [] || invalid != [],
      do: Mix.raise("Usage: mix brando.assets.setup [--source PATH] [--no-build] [--backend-only]")

    source = source_path(options)
    backend = Path.expand("assets/backend")
    consumers = if options[:backend_only], do: [backend], else: [backend, Path.expand("assets/frontend")]
    store = Mix.Project.build_path() |> Path.join("brando_yalc") |> Path.expand()

    Enum.each([source | consumers], fn path ->
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

    check_europa!(backend, options[:build] != false)

    Enum.each(["node", "pnpm", "yalc"], fn tool ->
      unless System.find_executable(tool),
        do: Mix.raise("#{tool} is required by mix brando.assets.setup but was not found on PATH.")
    end)

    run!("yalc", ["publish", "--store-folder", store], source)
    run!("yalc", ["add", "@brandocms/brandojs", "--store-folder", store], backend)

    Enum.each(consumers, fn path ->
      run!("pnpm", ["install"], path)
      if options[:build] != false, do: run!("pnpm", ["build"], path)
    end)
  end

  @europa_plugin "@brandocms/vite-plugin-europacss"

  # The admin's CSS builds with the native EuropaCSS compiler. Until its
  # packages are published, the backend installs the Vite plugin from .yalc
  # and the build runs the `europa` executable from PATH.
  defp check_europa!(backend, build?) do
    package = backend |> Path.join("package.json") |> File.read!() |> Jason.decode!()
    plugin = get_in(package, ["devDependencies", @europa_plugin]) || ""

    if String.starts_with?(plugin, "file:") and not File.dir?(Path.join(backend, String.trim_leading(plugin, "file:"))) do
      Mix.raise("""
      assets/backend installs #{@europa_plugin} from #{String.trim_leading(plugin, "file:")}, which is missing. \
      Until the package is published, add it from a EuropaCSS checkout: run `npx yalc publish --private` in its \
      packages/vite, then `npx yalc add --dev #{@europa_plugin}` in assets/backend.
      """)
    end

    if build? and is_nil(System.find_executable("europa")) and
         not File.exists?(Path.join(backend, "node_modules/.bin/europa")) do
      Mix.raise("""
      Building the admin needs the native EuropaCSS compiler, `europa`, on PATH. Build it in a EuropaCSS \
      checkout with `cargo build --locked --release -p europacss` and add its target/release to PATH, or \
      rerun with --no-build.
      """)
    end
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
