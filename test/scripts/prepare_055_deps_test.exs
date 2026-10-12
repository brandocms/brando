defmodule Brando.Scripts.Prepare055DepsTest do
  # scripts/prepare_055_deps.exs runs with plain `elixir`, before the
  # application's dependencies resolve; these run it the same way.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("../../scripts/prepare_055_deps.exs", __DIR__)
  @guide Path.expand("../../guides/migrating_from_053.md", __DIR__)

  # Lett's mix.exs before its 0.55 upgrade, trimmed.
  @before_state """
  defmodule Lett.MixProject do
    use Mix.Project

    def project do
      [
        app: :lett,
        version: "2.4.2",
        elixir: "~> 1.11",
        elixirc_paths: elixirc_paths(Mix.env()),
        deps: deps()
      ]
    end

    defp deps do
      [
        {:phoenix, "~> 1.7.0"},
        {:ecto, "~> 3.10"},
        {:ecto_sql, "~> 3.10"},
        {:phoenix_html, "~> 3.0"},
        {:phoenix_live_reload, "~> 1.2", only: :dev},
        {:telemetry, "~> 1.0", override: true},
        # {:exsync, "~> 0.2", only: :dev},

        # live view
        {:phoenix_live_view, "~> 0.18"},
        {:floki, ">= 0.27.0", only: :test},

        # general deps
        {:postgrex, "~> 0.15"},
        {:gettext, "~> 0.11"},
        {:swoosh, "~> 1.0"},
        {:timex, "~> 3.0"},
        {:jason, "~> 1.0"},

        # newsletter
        {:ex_chimp, "~> 0.1.0"},

        # brando
        {:brando, github: "brandocms/brando"}
        # {:brando, path: "../../brando"}
      ]
    end
  end
  """

  # What commit 4830f06a in Lett made of it by hand.
  @after_state """
  defmodule Lett.MixProject do
    use Mix.Project

    def project do
      [
        app: :lett,
        version: "2.4.2",
        elixir: "~> 1.18",
        listeners: [Phoenix.CodeReloader],
        elixirc_paths: elixirc_paths(Mix.env()),
        deps: deps()
      ]
    end

    defp deps do
      [
        {:phoenix, "~> 1.8.15"},
        {:ecto, "~> 3.14"},
        {:ecto_sql, "~> 3.14"},
        {:phoenix_html, "~> 4.0"},
        {:phoenix_live_reload, "~> 1.2", only: :dev},
        {:telemetry, "~> 1.0", override: true},
        # {:exsync, "~> 0.2", only: :dev},

        # live view
        {:phoenix_live_view, "~> 1.2.0"},
        {:floki, "~> 0.32"},

        # general deps
        {:postgrex, "~> 0.20"},
        {:gettext, "~> 1.0"},
        {:swoosh, "~> 1.17"},
        {:jason, "~> 1.0"},

        # newsletter
        {:ex_chimp, "~> 0.2.0"},

        # brando
        {:brando, path: "/src/brando"},
        {:igniter, "~> 0.8", only: [:dev, :test]}
        # {:brando, path: "../../brando"}
      ]
    end
  end
  """

  @lock ~S"""
  %{
    "ex_aws": {:hex, :ex_aws, "2.5.0", "17", [:mix], [{:hackney, "~> 1.16", [hex: :hackney, repo: "hexpm", optional: true]}], "hexpm", "29"},
    "ex_chimp": {:hex, :ex_chimp, "0.1.0", "79", [:mix], [{:httpoison, "~> 0.10 or ~> 1.1", [hex: :httpoison, repo: "hexpm", optional: false]}], "hexpm", "4c"},
    "hackney": {:hex, :hackney, "1.20.1", "8d", [:rebar3], [], "hexpm", "fe"},
    "httpoison": {:hex, :httpoison, "1.8.0", "6b", [:mix], [{:hackney, "~> 1.17", [hex: :hackney, repo: "hexpm", optional: false]}], "hexpm", "28"},
    "mailchimp_extra": {:hex, :mailchimp_extra, "1.0.0", "aa", [:mix], [{:hackney, "~> 1.8", [hex: :hackney, repo: "hexpm", optional: false]}], "hexpm", "bb"},
    "tzdata": {:hex, :tzdata, "1.1.1", "20", [:mix], [{:hackney, "~> 1.17", [hex: :hackney, repo: "hexpm", optional: false]}], "hexpm", "a6"},
  }
  """

  defp app(dir, mix_exs, lib \\ "defmodule Lett do\n  def now, do: DateTime.utc_now()\nend\n") do
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "mix.exs"), mix_exs)
    File.write!(Path.join(dir, "mix.lock"), @lock)
    File.write!(Path.join(dir, "lib/lett.ex"), lib)
    dir
  end

  defp run_script(args, env \\ []) do
    {output, 0} = System.cmd(System.find_executable("elixir"), [@script | args], stderr_to_stdout: true, env: env)
    output
  end

  # A `node` on the PATH that prints `version`.
  defp node_on_path(dir, version) do
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)
    node = Path.join(bin, "node")
    File.write!(node, "#!/bin/sh\necho #{version}\n")
    File.chmod!(node, 0o755)
    [{"PATH", bin <> ":" <> System.get_env("PATH")}]
  end

  test "prints the running Node, and what to use instead of an odd release", %{tmp_dir: tmp_dir} do
    dir = app(Path.join(tmp_dir, "app"), @before_state)

    odd = run_script(["--dry-run", dir], node_on_path(Path.join(tmp_dir, "odd"), "v23.11.0"))

    assert odd =~
             "Node: v23.11.0. Node 23 is an odd release, which pnpm and yarn refuse for Vite 8 and the asset packages"

    assert odd =~ "use Node 22 (or another even LTS major ≥ 22)."

    even = run_script(["--dry-run", dir], node_on_path(Path.join(tmp_dir, "even"), "v22.15.0"))
    assert even =~ "Node: v22.15.0\n"
  end

  test "rewrites a Lett-shaped mix.exs as the upgrade did by hand", %{tmp_dir: tmp_dir} do
    dir = app(tmp_dir, @before_state)
    output = run_script(["--brando-path", "/src/brando", dir])

    assert File.read!(Path.join(dir, "mix.exs")) == @after_state
    assert output =~ ~s|{:floki, ">= 0.27.0", only: :test},  →  {:floki, "~> 0.32"},|
    assert output =~ ~s|{:timex, "~> 3.0"},  →  (removed)|
    assert output =~ "mix deps.unlock --all && mix deps.get"

    # The lock: what the application declares, then what comes in through others
    assert output =~ "ex_chimp 0.1.0 (httpoison ~> 0.10 or ~> 1.1): mix.exs now asks for ~> 0.2.0"
    assert output =~ "resolved again by deps.get: hackney 1.20.1, httpoison 1.8.0, mailchimp_extra 1.0.0, tzdata 1.1.1"
    refute output =~ "ex_aws 2.5.0"

    # A second run changes nothing
    assert run_script(["--brando-path", "/src/brando", dir]) =~ "nothing to change"
    assert File.read!(Path.join(dir, "mix.exs")) == @after_state
  end

  test "keeps timex while lib/ calls it, and names a declared hackney 1 package", %{tmp_dir: tmp_dir} do
    mix_exs =
      @before_state
      |> String.replace(~s({:jason, "~> 1.0"},), ~s({:jason, "~> 1.0"},\n      {:mailchimp_extra, "~> 1.0"},))

    dir = app(tmp_dir, mix_exs, "defmodule Lett do\n  def now, do: Timex.now()\nend\n")
    output = run_script(["--dry-run", dir])

    assert File.read!(Path.join(dir, "mix.exs")) == mix_exs
    assert output =~ "--dry-run: mix.exs not written."
    refute output =~ "(removed)"
    assert output =~ "timex kept"
    assert output =~ "lib/lett.ex:2"
    assert output =~ "{:brando, …} unchanged: point it at 0.55 with --brando-path or --brando-ref"
    assert output =~ "mailchimp_extra 1.0.0 (hackney ~> 1.8): declared in mix.exs: move to a release on hackney 4 or Req"
  end

  test "puts commas in front of a dependency line's comment", %{tmp_dir: tmp_dir} do
    mix_exs = """
    defmodule Commented.MixProject do
      use Mix.Project

      def project do
        [app: :commented, elixir: "~> 1.18", listeners: [Phoenix.CodeReloader], deps: deps()]
      end

      defp deps do
        [
          {:jason, "~> 1.0"}, # json
          {:brando, github: "brandocms/brando"} # the CMS
          , {:timex, "~> 3.7"} # dates
        ]
      end
    end
    """

    dir = app(tmp_dir, mix_exs)
    run_script(["--brando-ref", "abc123", dir])
    written = File.read!(Path.join(dir, "mix.exs"))

    assert {:ok, _} = Code.string_to_quoted(written), written
    refute written =~ "timex"
    assert written =~ ~s|{:igniter, "~> 0.8", only: [:dev, :test]}|
    assert written =~ "# the CMS"

    last = """
    defp deps do
        [
          {:jason, "~> 1.0"}, # json
          {:brando, github: "brandocms/brando"} # the CMS
        ]
      end
    """

    dir = app(Path.join(tmp_dir, "last"), String.replace(mix_exs, ~r/defp deps do.*?\n  end\n/s, last))
    run_script(["--brando-ref", "abc123", dir])
    written = File.read!(Path.join(dir, "mix.exs"))

    assert {:ok, _} = Code.string_to_quoted(written), written
    assert written =~ ~r/\{:brando, [^\n]*\},\s*# the CMS\n\s*\{:igniter/
  end

  test "the constraints are the guide's" do
    guide = File.read!(@guide)
    [_, section] = String.split(guide, "### Dependencies and toolchain", parts: 2)
    [block | _] = Regex.run(~r/```elixir\n# mix\.exs\n\{:phoenix,.*?```/s, section)

    guide_constraints =
      ~r/\{:(\w+), "([^"]+)"/
      |> Regex.scan(block)
      |> Enum.map(fn [_, name, requirement] -> {name, requirement} end)
      |> Enum.reject(&(elem(&1, 0) == "igniter"))
      |> Enum.sort()

    [script_block] = Regex.run(~r/@constraints \[(.*?)\]/s, File.read!(@script), capture: :all_but_first)

    script_constraints =
      ~r/(\w+): "([^"]+)"/
      |> Regex.scan(script_block)
      |> Enum.map(fn [_, name, requirement] -> {name, requirement} end)
      |> Enum.reject(&(elem(&1, 0) == "ex_chimp"))
      |> Enum.sort()

    assert script_constraints == guide_constraints
  end
end
