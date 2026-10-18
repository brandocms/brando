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

  The admin (`assets/backend`) takes `@brandocms/brandojs` from npm or from a
  local source, and its `package.json` says which:

    * **npm**, pinned to Brando's version (`"@brandocms/brandojs": "0.55.0"`).
      Released Brando versions generate this. The task runs `pnpm install`
      and needs no BrandoJS source.
    * **A Yalc copy** of a checkout (`file:.yalc/…`). Use it to work on Brando
      itself: publish the checkout with `npx yalc publish` and the backend's
      Vite dev server pulls each new publish. Development versions of Brando
      (`-dev`) have no npm release and generate this.
    * **A linked checkout** (`link:../../brando/assets`), which pnpm installs
      from as it is.

  Without options, the task keeps the source `package.json` names. For a Yalc
  copy it publishes the selected Brando dependency's `assets` directory again.
  Hex packages do not include it: supply `--source` pointing to a matching
  checkout, or `--npm`, in that case. Keep the Elixir and JS revisions
  aligned. A `package.json` without BrandoJS gets what a generated admin has:
  npm at Brando's version, or for a development version a Yalc copy.

    * `--local` switches the admin to a Yalc copy of the Brando dependency's
      `assets` directory, `--source PATH` to a Yalc copy of PATH.
    * `--npm` switches it to the npm release of Brando's version and removes
      the Yalc copy.

  A Yalc copy is published to a project-local Yalc store under `_build`.
  Node.js, pnpm and, for a Yalc copy, Yalc must already be installed; the
  task checks them before it changes anything. pnpm
  installs the native EuropaCSS compiler the admin's CSS, and a generated
  site's, build with from npm.
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

    # Everything that can fail is checked before the admin changes, so a
    # missing tool or source never leaves it half-switched.
    source = options |> source(spec, Brando.version()) |> check_source!(backend, spec)
    Enum.each(required_tools(source), &require_tool!/1)
    install_brandojs(source, backend, spec)

    Enum.each(consumers, fn path ->
      run!("pnpm", ["install"], path)
      if options[:build] != false, do: run!("pnpm", ["build"], path)
    end)
  end

  @doc """
  Where the admin takes BrandoJS from, given the options, the BrandoJS spec in
  its package.json and Brando's version:

    * `:npm`, the npm version package.json pins;
    * `{:npm, :switch}`, npm at Brando's version, written to package.json;
    * `{:yalc, source}`, a Yalc copy of `source`, a path or `:dependency` (the
      Brando dependency's `assets`);
    * `{:linked, path}`, the checkout a `link:` or `file:` spec names, as it is.

  A package.json without BrandoJS gets what a generated admin has.
  """
  def source(options, spec, version) do
    case Enum.filter([:local, :source, :npm], &options[&1]) do
      [] -> current_source(spec, version)
      [:local] -> {:yalc, :dependency}
      [:source] -> {:yalc, options[:source]}
      [:npm] -> npm!(version)
      _ -> Mix.raise("Choose one of --local, --source and --npm. " <> @usage)
    end
  end

  defp check_source!({:yalc, path}, _backend, spec),
    do: {:yalc, brandojs_dir!(source_path(path, spec), "Use --source for a matching BrandoJS checkout.")}

  defp check_source!({:linked, path}, backend, spec) do
    hint = "assets/backend/package.json takes it from #{spec}; fix that path, or use --local, --source or --npm."
    path = Path.expand(path, backend)

    # `file:` also takes a packed tarball, which pnpm installs as it is.
    if tarball?(path),
      do: if(File.regular?(path), do: {:linked, path}, else: Mix.raise("Missing #{path}. #{hint}")),
      else: {:linked, brandojs_dir!(path, hint)}
  end

  defp check_source!(npm, _backend, _spec), do: npm

  defp tarball?(path), do: String.ends_with?(path, [".tgz", ".tar.gz"])

  defp install_brandojs(:npm, _backend, spec), do: npm_notice(spec)
  defp install_brandojs({:npm, :switch}, backend, _spec), do: switch_to_npm(backend)
  defp install_brandojs({:yalc, path}, backend, _spec), do: yalc_add(backend, path)
  defp install_brandojs({:linked, _path}, _backend, _spec), do: :ok

  defp current_source(nil, version),
    do: if(BrandoJS.development?(version), do: {:yalc, :dependency}, else: {:npm, :switch})

  defp current_source(spec, _version) do
    cond do
      BrandoJS.yalc?(spec) -> {:yalc, :dependency}
      BrandoJS.local?(spec) -> {:linked, String.replace(spec, ~r/^(link|file):/, "")}
      true -> :npm
    end
  end

  defp npm!(version) do
    if BrandoJS.development?(version),
      do:
        Mix.raise(
          "Brando #{version} is a development version and has no npm release of #{BrandoJS.package()}. Use --local or --source."
        ),
      else: {:npm, :switch}
  end

  @doc "The executables setting up the admin from `source` (see `source/3`) needs."
  def required_tools({:yalc, _source}), do: ["node", "pnpm", "yalc"]
  def required_tools(_source), do: ["node", "pnpm"]

  defp npm_notice(spec) do
    if spec != Brando.version(),
      do: Mix.shell().info("assets/backend pins #{BrandoJS.package()} #{spec}; Brando is #{Brando.version()}.")
  end

  # Switching to npm pins Brando's version and drops the Yalc copy, so the
  # Vite plugin that follows Yalc publishes has nothing left to follow.
  defp switch_to_npm(backend) do
    version = Brando.version()
    path = Path.join(backend, "package.json")
    File.write!(path, BrandoJS.put_spec(File.read!(path), version))
    remove_yalc_copy(backend)
    Mix.shell().info("#{BrandoJS.package()} now comes from npm at #{version}.")
  end

  # `--pure` copies the package into .yalc and yalc.lock only. Without it Yalc
  # also writes a copy into node_modules, which pnpm then moves aside to
  # node_modules/.ignored with a warning. pnpm installs the `file:` spec,
  # written here instead of by Yalc, from the .yalc copy.
  defp yalc_add(backend, source) do
    store = Mix.Project.build_path() |> Path.join("brando_yalc") |> Path.expand()
    run!("yalc", ["publish", "--store-folder", store], source)
    run!("yalc", ["add", BrandoJS.package(), "--pure", "--store-folder", store], backend)

    package = Path.join(backend, "package.json")
    contents = File.read!(package)
    yalc_spec = BrandoJS.yalc_spec()

    if BrandoJS.dependency(Jason.decode!(contents)) != yalc_spec,
      do: File.write!(package, BrandoJS.put_spec(contents, yalc_spec))
  end

  defp brandojs_dir!(dir, hint) do
    unless File.regular?(Path.join(dir, "package.json")),
      do: Mix.raise("Missing #{dir}/package.json. #{hint}")

    unless dir |> read_package() |> Map.get("name") == BrandoJS.package(),
      do: Mix.raise("#{dir} is not the #{BrandoJS.package()} package directory. #{hint}")

    dir
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

  defp source_path(:dependency, spec) do
    case Mix.Project.deps_paths()[:brando] do
      nil -> Mix.raise("Brando must be a dependency of this application, or supply --source PATH.")
      path -> dependency_assets!(Path.join(path, "assets") |> Path.expand(), spec)
    end
  end

  defp source_path(path, _spec), do: Path.expand(path)

  # Brando from Hex has no assets directory.
  defp dependency_assets!(dir, spec) do
    if File.dir?(dir) do
      dir
    else
      npm = if BrandoJS.development?(Brando.version()), do: "", else: ", or --npm for the npm release of Brando's version"

      Mix.raise("""
      The Brando dependency has no #{dir}: Hex packages do not include BrandoJS's source, which \
      assets/backend takes #{BrandoJS.package()} from#{if spec, do: " (#{spec})", else: ""}. Use --source PATH for a \
      matching BrandoJS checkout#{npm}.
      """)
    end
  end

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
