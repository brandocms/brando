defmodule Mix.Tasks.Brando.Assets.Setup do
  use Mix.Task

  alias Mix.Brando.BrandoJS

  @shortdoc "Installs and builds the application's Brando assets, BrandoJS from npm or a checkout"
  @moduledoc """
  Installs and builds the application's Brando assets during local development.

      mix brando.assets.setup
      mix brando.assets.setup --no-build
      mix brando.assets.setup --backend-only
      mix brando.assets.setup --local
      mix brando.assets.setup --source /path/to/brando/assets
      mix brando.assets.setup --npm

  The admin (`assets/backend`) takes `@brandocms/brandojs` from one of two
  sources, and its `package.json` says which:

    * **npm**, pinned to Brando's version (`"@brandocms/brandojs": "0.55.0"`).
      Released Brando versions generate this. The task runs `pnpm install`
      and needs no BrandoJS source.
    * **A local source**, a Yalc copy of a checkout (`file:.yalc/…`). Use it to
      work on Brando itself: publish the checkout with `npx yalc publish` and
      the backend's Vite dev server pulls each new publish. Development
      versions of Brando (`-dev`) have no npm release and generate this.

  Without options, the task keeps the source `package.json` names. For a local
  source it publishes the selected Brando dependency's `assets` directory.
  Hex packages do not include it: supply `--source` pointing to a matching
  checkout in that case. Keep the Elixir and JS revisions aligned.

    * `--local` switches the admin to a Yalc copy of the Brando dependency's
      `assets` directory, `--source PATH` to a Yalc copy of PATH.
    * `--npm` switches it to the npm release of Brando's version and removes
      the Yalc copy.

  A local source is published to a project-local Yalc store under `_build`.
  Node.js, pnpm and, for a local source, Yalc must already be installed. pnpm
  installs the native EuropaCSS compiler the admin's CSS builds with from npm.
  Unless `--no-build` is supplied, builds both consumers. It does not run a
  standalone framework build.

  `--backend-only` installs and builds the admin (`assets/backend`) alone, for
  applications whose frontend uses another package manager or build.

  This is an operational task. The Igniter installer only generates source;
  it never runs this command as part of accepting a diff.
  """

  @switches [source: :string, local: :boolean, npm: :boolean, build: :boolean, backend_only: :boolean]
  @usage "Usage: mix brando.assets.setup [--local | --source PATH | --npm] [--no-build] [--backend-only]"

  @impl Mix.Task
  def run(argv) do
    {options, rest, invalid} = OptionParser.parse(argv, strict: @switches)
    if rest != [] || invalid != [], do: Mix.raise(@usage)

    backend = Path.expand("assets/backend")
    consumers = if options[:backend_only], do: [backend], else: [backend, Path.expand("assets/frontend")]

    Enum.each(consumers, fn path ->
      unless File.regular?(Path.join(path, "package.json")),
        do: Mix.raise("Missing #{path}/package.json. Generate the assets first.")
    end)

    spec = backend |> read_package() |> BrandoJS.dependency()

    case source(options, spec, Brando.version()) do
      :npm -> install_npm(backend, spec, options[:npm])
      {:local, source} -> install_local(backend, source_path(source))
    end

    Enum.each(["node", "pnpm"], &require_tool!/1)

    Enum.each(consumers, fn path ->
      run!("pnpm", ["install"], path)
      if options[:build] != false, do: run!("pnpm", ["build"], path)
    end)
  end

  @doc """
  Where the admin takes BrandoJS from: `:npm`, or `{:local, source}` with
  `source` a path or `:dependency` (the Brando dependency's `assets`).
  """
  def source(options, spec, version) do
    case Enum.filter([:local, :source, :npm], &options[&1]) do
      [] -> if BrandoJS.local?(spec) or is_nil(spec), do: {:local, :dependency}, else: :npm
      [:local] -> {:local, :dependency}
      [:source] -> {:local, options[:source]}
      [:npm] -> npm!(version)
      _ -> Mix.raise("Choose one of --local, --source and --npm. " <> @usage)
    end
  end

  defp npm!(version) do
    if BrandoJS.development?(version),
      do:
        Mix.raise(
          "Brando #{version} is a development version and has no npm release of #{BrandoJS.package()}. Use --local or --source."
        ),
      else: :npm
  end

  # Switching to npm pins Brando's version and drops the Yalc copy, so the
  # Vite plugin that follows Yalc publishes has nothing left to follow.
  defp install_npm(backend, spec, switch?) do
    if switch? do
      version = Brando.version()
      path = Path.join(backend, "package.json")
      File.write!(path, BrandoJS.put_spec(File.read!(path), version))
      remove_yalc_copy(backend)
      Mix.shell().info("#{BrandoJS.package()} now comes from npm at #{version}.")
    else
      if spec != Brando.version(),
        do: Mix.shell().info("assets/backend pins #{BrandoJS.package()} #{spec}; Brando is #{Brando.version()}.")
    end
  end

  defp install_local(backend, source) do
    unless File.regular?(Path.join(source, "package.json")),
      do: Mix.raise("Missing #{source}/package.json. Use --source for a matching BrandoJS checkout.")

    unless source |> read_package() |> Map.get("name") == BrandoJS.package(),
      do: Mix.raise("--source must point to the #{BrandoJS.package()} package directory.")

    require_tool!("yalc")
    store = Mix.Project.build_path() |> Path.join("brando_yalc") |> Path.expand()
    run!("yalc", ["publish", "--store-folder", store], source)
    run!("yalc", ["add", BrandoJS.package(), "--store-folder", store], backend)
  end

  @doc "Removes BrandoJS's Yalc copy from `backend`, leaving any other package Yalc holds."
  def remove_yalc_copy(backend) do
    File.rm_rf!(Path.join([backend, ".yalc" | String.split(BrandoJS.package(), "/")]))
    Enum.each([".yalc/@brandocms", ".yalc"], &remove_if_empty(Path.join(backend, &1)))

    lock = Path.join(backend, "yalc.lock")

    with {:ok, body} <- File.read(lock),
         {:ok, %{"packages" => packages} = contents} <- Jason.decode(body) do
      case Map.delete(packages, BrandoJS.package()) do
        empty when map_size(empty) == 0 -> File.rm!(lock)
        rest -> File.write!(lock, Jason.encode!(%{contents | "packages" => rest}, pretty: true) <> "\n")
      end
    end
  end

  defp remove_if_empty(dir) do
    if File.dir?(dir) and File.ls!(dir) == [], do: File.rmdir!(dir)
  end

  defp source_path(:dependency) do
    case Mix.Project.deps_paths()[:brando] do
      nil -> Mix.raise("Brando must be a dependency of this application, or supply --source PATH.")
      path -> Path.join(path, "assets") |> Path.expand()
    end
  end

  defp source_path(path), do: Path.expand(path)

  defp read_package(dir), do: dir |> Path.join("package.json") |> File.read!() |> Jason.decode!()

  defp require_tool!(tool) do
    unless System.find_executable(tool),
      do: Mix.raise("#{tool} is required by mix brando.assets.setup but was not found on PATH.")
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
