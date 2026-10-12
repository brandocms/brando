defmodule Brando.Doctor.Checks.Node do
  @moduledoc """
  The Node.js on the PATH, which builds the admin and frontend assets,
  against what Brando is tested on (`Brando.Toolchain`): an odd release, or
  one older than the asset packages accept, fails their install with an
  engines error, or nothing checks it until then.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Toolchain

  @impl true
  def id, do: "node"

  @impl true
  def label, do: dgettext("doctor", "Node.js")

  # Assets are built where the source is, not on the server.
  @impl true
  def needs_source?, do: true

  @impl true
  def run(_context), do: evaluate(Toolchain.node_version())

  @doc "`version` is what `node --version` printed, or nil without a `node` on the PATH."
  def evaluate(nil),
    do:
      skipped(dgettext("doctor", "no node on the PATH"),
        fix: dgettext("doctor", "the admin and frontend assets build with %{advice}", advice: advice())
      )

  def evaluate(version) do
    case Toolchain.check_node(version) do
      :ok ->
        ok(version)

      {:odd, major} ->
        warning(dgettext("doctor", "%{version}: Node %{major} is an odd release", version: version, major: major),
          fix:
            dgettext(
              "doctor",
              "use %{advice}: odd releases are not LTS, and pnpm and yarn refuse them for Vite 8 and the asset packages",
              advice: advice()
            )
        )

      {:old, major} ->
        warning(
          dgettext("doctor", "%{version}: Node %{major} is older than Brando is tested on",
            version: version,
            major: major
          ),
          fix: dgettext("doctor", "use %{advice}", advice: advice())
        )

      {:below_minimum, minimum} ->
        warning(
          dgettext("doctor", "%{version}: older than Vite 8 accepts (%{minimum})", version: version, minimum: minimum),
          fix: dgettext("doctor", "use %{advice}", advice: advice())
        )

      :unknown ->
        warning(dgettext("doctor", "node --version printed %{version}", version: inspect(version)),
          fix: dgettext("doctor", "use %{advice}", advice: advice())
        )
    end
  end

  defp advice do
    major = Toolchain.node_major()
    dgettext("doctor", "Node %{major} (or another even LTS major ≥ %{major})", major: major)
  end
end
