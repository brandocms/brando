defmodule Brando.Doctor.Checks.AdminAssets do
  @moduledoc """
  The admin's BrandoJS against Brando: the version of `@brandocms/brandojs`
  the admin installs, from npm into `node_modules` or from a local source
  (`assets/backend/.yalc` or the checkout it links to), should be Brando's own. An older publish gives an admin whose JavaScript
  does not match the server.

  Reads the source tree, so it is skipped in a release.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context

  @package "@brandocms/brandojs"

  @impl true
  def id, do: "admin_assets"

  @impl true
  def label, do: dgettext("doctor", "Admin assets")

  @impl true
  def needs_source?, do: true

  @impl true
  def run(%Context{root: root}), do: evaluate(Path.join(root, "assets/backend"), Brando.version())

  @doc "Checks the admin consumer in `backend` against Brando `version`."
  def evaluate(backend, version) do
    case read_json(Path.join(backend, "package.json")) do
      nil ->
        skipped(dgettext("doctor", "no assets/backend/package.json"))

      package ->
        result =
          backend
          |> installed(dependency(package))
          |> report(version)

        if result.status != :ok and not pnpm?(backend, package),
          do: %{result | fix: upgrade_fix(version)},
          else: result
    end
  end

  # The admin is built with pnpm since 0.55; a yarn or npm `assets/backend`
  # needs the template's package.json and lockfile before any install.
  defp pnpm?(backend, package) do
    File.regular?(Path.join(backend, "pnpm-lock.yaml")) or
      String.starts_with?(to_string(package["packageManager"]), "pnpm@")
  end

  defp upgrade_fix(version) do
    dgettext(
      "doctor",
      "expected %{version}; assets/backend is not a pnpm project yet: run mix brando.gen.backend --upgrade, then mix brando.assets.setup --backend-only",
      version: version
    )
  end

  defp dependency(package) do
    get_in(package, ["dependencies", @package]) || get_in(package, ["devDependencies", @package])
  end

  defp installed(_backend, nil), do: :missing

  # `yalc add` writes `file:.yalc/…` (or `link:.yalc/…`); anything else is a
  # checkout linked by path
  defp installed(backend, "link:" <> path), do: local(backend, path)
  defp installed(backend, "file:" <> path), do: local(backend, path)

  # An npm version: what pnpm installed. A .yalc copy left from an earlier
  # local setup is not what the admin builds from.
  defp installed(backend, _spec) do
    node_modules = Path.join([backend, "node_modules", @package])
    if File.dir?(node_modules), do: {:node_modules, read_version(node_modules)}, else: :not_installed
  end

  defp local(backend, path) do
    version = read_version(Path.expand(path, backend))
    if String.starts_with?(path, ".yalc/"), do: {:yalc, version}, else: {:link, path, version}
  end

  defp report(:missing, _version) do
    error(dgettext("doctor", "brandojs is not a dependency of assets/backend"),
      fix: dgettext("doctor", "run mix brando.assets.setup --backend-only")
    )
  end

  defp report(:not_installed, _version) do
    error(dgettext("doctor", "brandojs not installed"),
      fix: dgettext("doctor", "run mix brando.assets.setup --backend-only")
    )
  end

  defp report({:link, path, installed}, version) do
    summary = dgettext("doctor", "linked to %{path}, brandojs %{version}", path: path, version: installed || "-")
    compare(summary, installed, version, dgettext("doctor", "check out the BrandoJS revision that matches Brando"))
  end

  defp report({:yalc, installed}, version) do
    summary = dgettext("doctor", ".yalc brandojs %{version}", version: installed || "-")

    compare(
      summary,
      installed,
      version,
      dgettext(
        "doctor",
        "expected %{version}, run npx yalc publish in Brando's assets, then npx yalc update %{package} and pnpm install in assets/backend (or mix brando.assets.setup --backend-only)",
        version: version,
        package: @package
      )
    )
  end

  defp report({:node_modules, installed}, version) do
    summary = dgettext("doctor", "brandojs %{version}", version: installed || "-")

    compare(
      summary,
      installed,
      version,
      dgettext("doctor", "expected %{version}, run mix brando.assets.setup --npm --backend-only", version: version)
    )
  end

  defp compare(summary, installed, version, fix) do
    if installed == version, do: ok(summary), else: warning(summary, fix: fix)
  end

  defp read_version(dir), do: get_in(read_json(Path.join(dir, "package.json")) || %{}, ["version"])

  defp read_json(path) do
    with {:ok, body} <- File.read(path),
         {:ok, json} <- Jason.decode(body) do
      json
    else
      _ -> nil
    end
  end
end
