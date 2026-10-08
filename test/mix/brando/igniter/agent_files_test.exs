defmodule Mix.Brando.Igniter.AgentFilesTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.AgentFiles

  @phoenix_agents """
  This is a web application written using the Phoenix web framework.

  <!-- usage-rules-start -->

  <!-- phoenix:elixir-start -->
  ## Elixir guidelines
  <!-- phoenix:elixir-end -->

  <!-- usage-rules-end -->
  """

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => "import Config\nimport_config \"dev.exs\"\n",
            "config/dev.exs" => "import Config\n",
            "lib/studio_web/gettext.ex" => "defmodule StudioWeb.Gettext do\n use Gettext.Backend, otp_app: :studio\nend\n"
          },
          files
        )
    )
  end

  defp install(igniter), do: Igniter.compose_task(igniter, Mix.Tasks.Brando.Install, [])

  test "Brando ships site skills with a name and description that match their directory" do
    files = AgentFiles.skill_files()
    skills = for {path, _} <- files, Path.basename(path) == "SKILL.md", do: path

    assert length(skills) >= 5

    for path <- skills do
      name = path |> Path.dirname() |> Path.basename()
      contents = files |> List.keyfind(path, 0) |> elem(1)

      assert [_, frontmatter] = Regex.run(~r/\A---\n(.*?)\n---\n/s, contents), "#{path} has no frontmatter"
      assert frontmatter =~ ~r/^name: #{name}$/m
      assert frontmatter =~ ~r/^description: \S/m

      # Skills point at the guides in the dependency; every guide they name ships.
      for [_, guide] <- Regex.scan(~r{deps/brando/guides/([a-z0-9_]+\.md)}, contents) do
        assert File.exists?(Path.join("guides", guide)), "#{path} names a missing guide: #{guide}"
      end
    end
  end

  test "install adds the skills and links the usage rules from a new AGENTS.md" do
    igniter = install(project())
    assert igniter.issues == []

    for {path, contents} <- AgentFiles.skill_files() do
      Igniter.Test.assert_creates(igniter, path, contents)
    end

    agents = IgniterCase.source(igniter, "AGENTS.md")
    assert agents =~ "<!-- usage-rules-start -->\n<!-- brando-start -->"
    assert agents =~ "(deps/brando/usage-rules.md)"
    assert agents =~ "<!-- brando-end -->\n<!-- usage-rules-end -->"
  end

  test "install joins the usage-rules section Phoenix writes into AGENTS.md" do
    agents = project(%{"AGENTS.md" => @phoenix_agents}) |> install() |> IgniterCase.source("AGENTS.md")

    assert agents =~ "## Elixir guidelines\n<!-- phoenix:elixir-end -->\n\n<!-- brando-start -->"
    assert agents =~ "<!-- brando-end -->\n\n<!-- usage-rules-end -->"
    assert String.starts_with?(agents, "This is a web application")
    assert length(String.split(agents, "<!-- usage-rules-start -->")) == 2
  end

  test "edited skills and an existing Brando section are left alone on reruns" do
    [{skill, _} | _] = AgentFiles.skill_files()
    edited = "---\nname: mine\ndescription: Edited by the application.\n---\n"
    agents = @phoenix_agents <> "\n<!-- brando-start -->\nOur own notes.\n<!-- brando-end -->\n"

    igniter = project(%{skill => edited, "AGENTS.md" => agents}) |> install()

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, skill)
    Igniter.Test.assert_unchanged(igniter, "AGENTS.md")
  end

  test "a versioned upgrade adds missing skills without replacing edited ones" do
    installed = Application.spec(:brando, :vsn) |> to_string() |> Version.parse!()
    [{edited_skill, _}, {missing_skill, contents} | _] = AgentFiles.skill_files()

    result =
      project(%{edited_skill => "edited\n"})
      |> Igniter.compose_task(Mix.Tasks.Brando.Upgrade, ["0.54.0", to_string(installed)])

    assert result.issues == []
    Igniter.Test.assert_unchanged(result, edited_skill)
    Igniter.Test.assert_creates(result, missing_skill, contents)
    assert IgniterCase.source(result, "AGENTS.md") =~ "deps/brando/usage-rules.md"
  end
end
