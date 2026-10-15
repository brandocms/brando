defmodule Brando.Doctor.Checks.AdminCss do
  @moduledoc """
  The admin's CSS compiler: `assets/backend` should build with the native
  EuropaCSS packages at the versions Brando's template pins
  (`Brando.EuropaCSS`), from npm, and have them installed. A backend on the
  legacy `@brandocms/europacss` PostCSS plugin, or on a Yalc copy of the Vite
  plugin, builds with something Brando's CSS was not checked against.

  Reads the source tree, so it is skipped in a release.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Brando.EuropaCSS

  @impl true
  def id, do: "admin_css"

  @impl true
  def label, do: dgettext("doctor", "Admin CSS compiler")

  @impl true
  def needs_source?, do: true

  @impl true
  def run(%Context{root: root}), do: evaluate(Path.join(root, "assets/backend"))

  @doc "Checks the admin consumer in `backend`."
  def evaluate(backend) do
    with {:ok, body} <- File.read(Path.join(backend, "package.json")),
         {:ok, %{} = package} <- Jason.decode(body) do
      case EuropaCSS.package_problems(package) do
        [] ->
          installed(backend)

        problems ->
          warn(
            problems,
            dgettext("doctor", "run mix brando.gen.backend --upgrade, then mix brando.assets.setup --backend-only")
          )
      end
    else
      _ -> skipped(dgettext("doctor", "no assets/backend/package.json"))
    end
  end

  defp installed(backend) do
    case EuropaCSS.install_problems(backend) do
      [] ->
        ok(dgettext("doctor", "EuropaCSS %{version}", version: EuropaCSS.pins()["@brandocms/europacss-cli"]))

      problems ->
        warn(problems, dgettext("doctor", "run pnpm install in assets/backend"))
    end
  end

  defp warn([first | _] = problems, fix) do
    warning(EuropaCSS.describe(first), fix: fix, items: Enum.map(problems, &EuropaCSS.describe/1))
  end
end
