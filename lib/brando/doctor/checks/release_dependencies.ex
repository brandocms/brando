defmodule Brando.Doctor.Checks.ReleaseDependencies do
  @moduledoc """
  Libraries for development or tests that the application ships in its
  release. A dependency whose `only:` is missing or includes `:prod` is
  compiled for production and its application starts with the release.

    * Tidewave, the coding agents' MCP server, evaluates code and runs SQL in
      the application it is plugged into while Mix runs there. A release
      without Mix does not start its MCP server, but a plugged Tidewave still
      removes `X-Frame-Options` and the CSP `frame-ancestors` from every
      response, and its toolbar, on by default, fails HTML responses. Its own
      instructions add it with `only: :dev` and plug it inside
      `if Mix.env() == :dev`. Loaded in a production release it is an error:
      the check cannot tell whether the endpoint plugs it.
    * Test libraries (ExMachina, Mox, Bypass, Mimic, Wallaby, ExCoveralls).
      Brando's installers before 0.55 added `{:ex_machina, "~> 2.3"}` to every
      environment, with the factory under `lib/`.

  From the terminal it reads the application's `mix.exs` dependencies; in a
  production release (its admin or a remote shell), the applications the
  release loaded. The admin of a development server cannot tell what a release
  would ship, so it skips.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context

  @dev_only [:tidewave]

  # Libraries a site only uses in its tests. LazyHTML is left out: it is an
  # HTML parser a site may also use at runtime.
  @test_only [:ex_machina, :mox, :bypass, :mimic, :wallaby, :excoveralls]

  @doc "The libraries this check looks for."
  def libraries, do: @dev_only ++ @test_only

  @impl true
  def id, do: "release_dependencies"

  @impl true
  def label, do: dgettext("doctor", "Release dependencies")

  # In a release (its admin or a remote shell, which has the default :mix
  # mode) there is no mix.exs to read, so the loaded applications answer. The
  # dependency list is the one mix.exs gives for the current environment, and
  # under :test it can hold entries a `Mix.env()` condition adds for tests only.
  @impl true
  def run(%Context{mode: :mix, source?: true}) do
    if Mix.env() == :test,
      do: skipped(dgettext("doctor", "checked outside MIX_ENV=test, whose dependencies can differ")),
      else: evaluate(from_deps(Mix.Project.config()[:deps] || []), :mix_exs)
  end

  def run(_context), do: from_release()

  defp from_release do
    if Brando.env() == :prod,
      do: evaluate(Enum.filter(libraries(), &Application.spec(&1, :vsn)), :release),
      else: skipped(dgettext("doctor", "checked in a production release, or with mix brando.doctor in the source tree"))
  end

  @doc """
  The libraries among `deps` (a `mix.exs` dependency list) that reach a
  production build: no `:only`, or an `:only` that includes `:prod`, and not
  `runtime: false`.
  """
  def from_deps(deps) do
    for dep <- deps, {name, opts} = name_and_opts(dep), name in libraries(), in_release?(opts), do: name
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

  @doc """
  `apps` are the libraries the release ships or would ship: `:mix_exs` when
  read from the dependencies, `:release` when loaded in a production release.
  """
  def evaluate(apps, from \\ :mix_exs)

  def evaluate([], _from), do: ok(dgettext("doctor", "none in the release"))

  def evaluate(apps, from) do
    summary = dgettext("doctor", "the release ships %{apps}", apps: Enum.map_join(apps, ", ", &inspect/1))
    fix = apps |> fixes() |> Enum.join("; ")

    if from == :release and Enum.any?(apps, &(&1 in @dev_only)),
      do: error(summary, fix: fix),
      else: warning(summary, fix: fix)
  end

  defp fixes(apps) do
    [
      Enum.any?(apps, &(&1 in @dev_only)) &&
        dgettext(
          "doctor",
          "Tidewave is for development: give it only: :dev in mix.exs and plug it inside if Mix.env() == :dev in the endpoint"
        ),
      Enum.any?(apps, &(&1 in @test_only)) &&
        dgettext(
          "doctor",
          "limit test libraries in mix.exs to the environments the tests run in, such as only: :test or only: [:test, :e2e], and move a factory under lib/ that uses ExMachina to test/support, which elixirc_paths compiles for those environments"
        )
    ]
    |> Enum.filter(& &1)
  end
end
