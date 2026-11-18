defmodule Brando.Doctor.Checks.DependencySources do
  @moduledoc """
  Brando and its `@brandocms` npm packages taken from a local checkout, which
  a release build cannot see.

    * Brando as a path dependency (`{:brando, path: "../brando"}`). The
      Docker build that Florist runs copies only the project, so it fails
      late or builds against whatever is at that path, and every dependency
      recompiles when the checkout's HEAD moves. Read from where the running
      Brando was compiled from (`Brando.Doctor.Source`), so a release reports
      it too.
    * An `@brandocms` package in an asset project's `package.json`
      (`assets/backend`, `assets/frontend`, `assets/sites/*`) whose version is
      a `link:`, `file:` or `portal:` path other than a Yalc copy. The Docker
      build installs from the asset project's `package.json`, lockfile and
      `.yalc` copy alone, before it copies the rest.
    * A Yalc copy (`file:.yalc/…`). The build copies it in, so a deploy ships
      whatever the copy holds. A `-dev` Brando has no npm release, and its
      installer sets the admin up with one, so it is only listed then;
      otherwise it is a warning, with the npm release as the fix.

  A path is a warning, and an error in production (a production release, or
  `MIX_ENV=prod`). The doctor has no deploy mode, so from a development shell
  it stays a warning, which `mix brando.doctor --strict` fails on. A release
  has no `package.json` to read, so there only Brando's own source is
  checked.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.Doctor.Source

  @asset_projects ["assets/backend", "assets/frontend", "assets/sites/*"]
  @dependency_keys ["dependencies", "devDependencies", "optionalDependencies"]

  @type package :: %{dir: String.t(), name: String.t(), spec: String.t(), kind: :path | :yalc}

  @impl true
  def id, do: "dependency_sources"

  @impl true
  def label, do: dgettext("doctor", "Dependency sources")

  @impl true
  def run(%Context{} = context) do
    packages = if context.source?, do: local_packages(context.root), else: []

    evaluate(Source.current(), packages,
      prod?: Brando.env() == :prod,
      dev?: Brando.version() |> Version.parse!() |> Map.get(:pre) |> Enum.member?("dev")
    )
  end

  @doc """
  The `@brandocms` packages the asset projects under `root` take from a local
  path (`kind: :path`) or a Yalc copy (`kind: :yalc`), by asset project and
  name.
  """
  @spec local_packages(Path.t()) :: [package()]
  def local_packages(root) do
    for pattern <- @asset_projects,
        dir <- root |> Path.join(pattern) |> Path.wildcard() |> Enum.sort(),
        json = read_package(Path.join(dir, "package.json")),
        json != nil,
        key <- @dependency_keys,
        {name, spec} <- Enum.sort(dependencies(json, key)),
        String.starts_with?(name, "@brandocms/"),
        kind = kind(spec),
        kind != nil,
        do: %{dir: Path.relative_to(dir, root), name: name, spec: spec, kind: kind}
  end

  defp read_package(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, %{} = json} <- Jason.decode(contents) do
      json
    else
      _ -> nil
    end
  end

  defp dependencies(json, key) do
    case json[key] do
      %{} = deps -> for {name, spec} <- deps, is_binary(spec), do: {name, spec}
      _ -> []
    end
  end

  # `yalc add` writes `file:.yalc/…`, `yalc link` `link:.yalc/…`.
  defp kind(spec) do
    case Regex.run(~r/^(?:link|file|portal):(.*)$/, spec) do
      [_, ".yalc/" <> _] -> :yalc
      [_, "./.yalc/" <> _] -> :yalc
      [_, _path] -> :path
      nil -> nil
    end
  end

  @doc """
  The result for Brando's `source` (`Brando.Doctor.Source.t()`) and the asset
  projects' local `packages` (`local_packages/1`).

    * `:prod?` — whether this is for production (`MIX_ENV=prod` or a
      release), where a path is an error.
    * `:dev?` — whether Brando is a `-dev` version, without an npm release.
  """
  @spec evaluate(Source.t(), [package()], keyword()) :: Brando.Doctor.Result.t()
  def evaluate(source, packages, opts) do
    # Brando itself, as a path dependency, counts as one more local package
    brando = for %{type: :path, path: path} <- [source], do: %{dir: nil, name: "brando", spec: path, kind: :path}
    {paths, yalc} = Enum.split_with(brando ++ packages, &(&1.kind == :path))
    # A -dev Brando has no npm release to switch to
    flagged_yalc = if Keyword.fetch!(opts, :dev?), do: [], else: yalc
    items = Enum.map(brando ++ packages, &item/1)
    details = [fix: fix(brando, paths -- brando, flagged_yalc), items: items]

    cond do
      paths == [] and flagged_yalc == [] -> ok(ok_summary(source, yalc), items: items)
      paths == [] -> warning(dgettext("doctor", "from a Yalc copy: %{names}", names: names(yalc)), details)
      Keyword.fetch!(opts, :prod?) -> error(path_summary(paths), details)
      true -> warning(path_summary(paths), details)
    end
  end

  defp path_summary(paths), do: dgettext("doctor", "from a local checkout: %{names}", names: names(paths))

  defp names(packages), do: packages |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.join(", ")

  defp ok_summary(source, []) do
    case Source.describe(source) do
      nil -> dgettext("doctor", "no local checkouts")
      described -> dgettext("doctor", "Brando from %{source}, no local checkouts", source: described)
    end
  end

  defp ok_summary(_source, yalc) do
    dgettext("doctor", "from a Yalc copy, as a development Brando has no npm release: %{names}", names: names(yalc))
  end

  defp item(%{dir: nil, spec: path}), do: dgettext("doctor", "brando in mix.exs: path %{path}", path: path)
  defp item(%{dir: dir, name: name, spec: spec}), do: "#{dir}/package.json: #{name} #{spec}"

  defp fix(brando, paths, yalc) do
    [brando != [] && brando_fix(), paths != [] && path_fix(), yalc != [] && yalc_fix()]
    |> Enum.filter(& &1)
    |> Enum.join("; ")
  end

  defp brando_fix do
    dgettext(
      "doctor",
      "give :brando a git ref or a Hex version in mix.exs before deploying: the release build sees only the project, and a path dependency recompiles every dependency when its checkout moves"
    )
  end

  defp path_fix do
    dgettext(
      "doctor",
      "give the @brandocms packages an npm version in package.json, or a Yalc copy for a development Brando (mix brando.assets.setup --npm or --local for BrandoJS), then pnpm install: the release build installs from package.json, the lockfile and the Yalc copy alone"
    )
  end

  defp yalc_fix do
    dgettext(
      "doctor",
      "a deploy ships whatever the Yalc copy holds: switch to the npm release with mix brando.assets.setup --npm, or give the package its npm version in package.json and run pnpm install"
    )
  end
end
