defmodule Brando.Doctor.Checks.AdminAssets do
  @moduledoc """
  The admin's BrandoJS against Brando: the version of `@brandocms/brandojs`
  in `assets/backend/.yalc` (or the checkout it links to, or `node_modules`)
  should be Brando's own. An older publish gives an admin whose JavaScript
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
        backend
        |> installed(dependency(package))
        |> report(version)
    end
  end

  defp dependency(package) do
    get_in(package, ["dependencies", @package]) || get_in(package, ["devDependencies", @package])
  end

  defp installed(_backend, nil), do: :missing

  # `yalc add` writes `file:.yalc/…` (or `link:.yalc/…`); anything else is a
  # checkout linked by path
  defp installed(backend, "link:" <> path), do: local(backend, path)
  defp installed(backend, "file:" <> path), do: local(backend, path)

  defp installed(backend, _spec) do
    yalc = Path.join([backend, ".yalc", @package])
    node_modules = Path.join([backend, "node_modules", @package])

    cond do
      File.dir?(yalc) -> {:yalc, read_version(yalc)}
      File.dir?(node_modules) -> {:node_modules, read_version(node_modules)}
      true -> :not_installed
    end
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
      dgettext("doctor", "expected %{version}, run npx yalc update %{package} and pnpm install in assets/backend",
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
      dgettext("doctor", "expected %{version}, run mix brando.assets.setup --backend-only", version: version)
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
