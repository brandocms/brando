defmodule Brando.Doctor.Checks.TestDependencies do
  @moduledoc """
  Test libraries the application ships in its release. A dependency without
  `only: :test` is compiled for production and its application starts with
  the release. Brando's installers before 0.55 added `{:ex_machina, "~> 2.3"}`
  that way, with the factory under `lib/`.

  From the terminal it reads the application's `mix.exs` dependencies; in the
  admin of a production release, the applications the release loaded. The
  admin of a development server cannot tell what a release would ship, so it
  skips.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context

  # Libraries a site only uses in its tests. LazyHTML is left out: it is an
  # HTML parser a site may also use at runtime.
  @test_only [:ex_machina, :mox, :bypass, :mimic, :wallaby, :excoveralls]

  @doc "The libraries this check looks for."
  def test_only, do: @test_only

  @impl true
  def id, do: "test_dependencies"

  @impl true
  def label, do: dgettext("doctor", "Test dependencies")

  # In a release (its admin or a remote shell, which has the default :mix
  # mode) there is no mix.exs to read, so the loaded applications answer. The
  # dependency list is the one mix.exs gives for the current environment, and
  # under :test it can hold entries a `Mix.env()` condition adds for tests only.
  @impl true
  def run(%Context{mode: :mix, source?: true}) do
    if Mix.env() == :test,
      do: skipped(dgettext("doctor", "checked outside MIX_ENV=test, whose dependencies can differ")),
      else: evaluate(from_deps(Mix.Project.config()[:deps] || []))
  end

  def run(_context), do: from_release()

  defp from_release do
    if Brando.env() == :prod,
      do: evaluate(Enum.filter(@test_only, &Application.spec(&1, :vsn))),
      else: skipped(dgettext("doctor", "checked in a production release, or with mix brando.doctor in the source tree"))
  end

  @doc """
  The test libraries among `deps` (a `mix.exs` dependency list) that reach a
  production build: no `:only`, or an `:only` that includes `:prod`, and not
  `runtime: false`.
  """
  def from_deps(deps) do
    for dep <- deps, {name, opts} = name_and_opts(dep), name in @test_only, in_release?(opts), do: name
  end

  defp name_and_opts({name, opts}) when is_list(opts), do: {name, opts}
  defp name_and_opts({name, _requirement, opts}) when is_list(opts), do: {name, opts}
  defp name_and_opts(dep), do: {elem(dep, 0), []}

  defp in_release?(opts) do
    Keyword.get(opts, :runtime, true) != false and
      case Keyword.fetch(opts, :only) do
        {:ok, only} -> :prod in List.wrap(only)
        :error -> true
      end
  end

  @doc "`apps` are the test libraries the release would ship."
  def evaluate([]), do: ok(dgettext("doctor", "none in the release"))

  def evaluate(apps) do
    names = Enum.map_join(apps, ", ", &inspect/1)

    warning(dgettext("doctor", "the release ships %{apps}", apps: names),
      fix:
        dgettext(
          "doctor",
          "limit them in mix.exs to the environments the tests run in, such as only: :test or only: [:test, :e2e]. A factory under lib/ that uses ExMachina moves to test/support, which elixirc_paths compiles for those environments"
        )
    )
  end
end
