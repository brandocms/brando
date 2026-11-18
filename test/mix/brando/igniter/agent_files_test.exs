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

  @site_section "<!-- brando-site-start -->\n## Our studio\n<!-- brando-site-end -->\n"

  defp install(igniter), do: Igniter.compose_task(igniter, Mix.Tasks.Brando.Install, [])
  defp gen_agents(igniter, argv \\ []), do: Igniter.compose_task(igniter, Mix.Tasks.Brando.Gen.Agents, argv)

  # A file the application has on disk but no task has read yet: what a real
  # rerun sees, where the test project otherwise loads every file up front.
  defp unread(igniter, path), do: %{igniter | rewrite: Rewrite.drop(igniter.rewrite, [path])}

  defp count(string, pattern), do: length(String.split(string, pattern)) - 1

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
    agents = @site_section <> @phoenix_agents <> "\n<!-- brando-start -->\nOur own notes.\n<!-- brando-end -->\n"

    igniter = project(%{skill => edited, "AGENTS.md" => agents, "CLAUDE.md" => "@AGENTS.md\n"}) |> install()

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, skill)
    Igniter.Test.assert_unchanged(igniter, "AGENTS.md")
    Igniter.Test.assert_unchanged(igniter, "CLAUDE.md")
  end

  test "install creates a CLAUDE.md that imports AGENTS.md" do
    igniter = install(project())

    Igniter.Test.assert_creates(igniter, "CLAUDE.md", "@AGENTS.md\n")
  end

  test "an existing CLAUDE.md is untouched, with a notice when it does not import AGENTS.md" do
    copied = "# Old site notes\n\nRun yarn in assets/frontend.\n"

    # An import on its own line or inline.
    for claude <- ["# Notes\n\n@AGENTS.md\n", "Read @./AGENTS.md first.\n"] do
      importing = install(project(%{"CLAUDE.md" => claude, "AGENTS.md" => @phoenix_agents}))
      Igniter.Test.assert_unchanged(importing, "CLAUDE.md")
      refute Enum.any?(importing.notices, &(&1 =~ "CLAUDE.md")), claude
    end

    # An old copy, a copy of AGENTS.md (which then misses what install adds to
    # it), and an import shown only in a code block.
    fenced = "# Notes\n\nAdd this line:\n\n```\n@AGENTS.md\n```\n"

    for claude <- [copied, @phoenix_agents, fenced] do
      copy = install(project(%{"CLAUDE.md" => claude, "AGENTS.md" => @phoenix_agents}))
      assert copy.issues == []
      Igniter.Test.assert_unchanged(copy, "CLAUDE.md")
      assert Enum.any?(copy.notices, &(&1 =~ "CLAUDE.md does not import AGENTS.md")), claude
    end
  end

  test "the site section goes once before the usage-rules markers, and reruns leave it alone" do
    for existing <- [%{}, %{"AGENTS.md" => @phoenix_agents}] do
      agents = project(existing) |> install() |> IgniterCase.source("AGENTS.md")

      assert count(agents, "<!-- brando-site-start -->") == 1
      assert count(agents, "<!-- brando-site-end -->") == 1
      [site, rules] = String.split(agents, "<!-- usage-rules-start -->", parts: 2)
      assert site =~ ~r/<!-- brando-site-start -->.*<!-- brando-site-end -->\n\n\z/s
      refute rules =~ "brando-site"

      # The application's edits to the section, and the section, survive a rerun.
      edited = String.replace(agents, ~r/TODO: .*?\n\n/s, "A portfolio site for Studio.\n\n")
      rerun = project(%{"AGENTS.md" => edited, "CLAUDE.md" => "@AGENTS.md\n"}) |> install()
      Igniter.Test.assert_unchanged(rerun, "AGENTS.md")
    end

    phoenix = project(%{"AGENTS.md" => @phoenix_agents}) |> install() |> IgniterCase.source("AGENTS.md")
    assert String.starts_with?(phoenix, "This is a web application written using the Phoenix web framework.\n\n")
  end

  test "an AGENTS.md without usage-rules markers gets the site section once" do
    agents = "# Studio\n\n<!-- brando-start -->\nOur own notes.\n<!-- brando-end -->\n"
    result = project(%{"AGENTS.md" => agents}) |> install() |> IgniterCase.source("AGENTS.md")

    assert String.starts_with?(result, agents)
    assert count(result, "<!-- brando-site-start -->") == 1

    Igniter.Test.assert_unchanged(
      project(%{"AGENTS.md" => result, "CLAUDE.md" => "@AGENTS.md\n"}) |> install(),
      "AGENTS.md"
    )
  end

  test "mix brando.gen.agents adds the missing agent files and keeps existing ones" do
    [{edited_skill, _}, {missing_skill, contents} | _] = AgentFiles.skill_files()

    igniter = project(%{edited_skill => "edited\n", "AGENTS.md" => @phoenix_agents}) |> gen_agents()

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, edited_skill)
    Igniter.Test.assert_creates(igniter, missing_skill, contents)
    Igniter.Test.assert_creates(igniter, "CLAUDE.md", "@AGENTS.md\n")

    agents = IgniterCase.source(igniter, "AGENTS.md")
    assert agents =~ "(deps/brando/usage-rules.md)"
    assert count(agents, "<!-- brando-site-start -->") == 1

    # It touches nothing but the agent files.
    assert Enum.sort(Map.keys(igniter.rewrite.sources)) --
             ["AGENTS.md", "CLAUDE.md" | Enum.map(AgentFiles.skill_files(), &elem(&1, 0))] ==
             Enum.sort(Map.keys(project().rewrite.sources))
  end

  test "mix brando.gen.agents --refresh replaces edited skills and keeps AGENTS.md and CLAUDE.md" do
    [{edited_skill, shipped} | _] = AgentFiles.skill_files()
    own_skill = ".claude/skills/our-own/SKILL.md"
    agents = @site_section <> @phoenix_agents
    claude = "# Notes\n@AGENTS.md\n"

    igniter =
      project(%{edited_skill => "edited\n", own_skill => "ours\n", "AGENTS.md" => agents, "CLAUDE.md" => claude})
      |> gen_agents(["--refresh"])

    assert igniter.issues == []
    assert IgniterCase.source(igniter, edited_skill) == shipped
    Igniter.Test.assert_unchanged(igniter, own_skill)
    Igniter.Test.assert_unchanged(igniter, "CLAUDE.md")
    assert IgniterCase.source(igniter, "AGENTS.md") =~ "<!-- brando-site-start -->\n## Our studio\n"
  end

  test "a skill on disk that no task has read yet is kept by reruns and replaced by --refresh" do
    [{skill, shipped} | _] = AgentFiles.skill_files()
    project = fn -> project(%{skill => "edited\n"}) |> unread(skill) end

    kept? = fn igniter ->
      igniter.issues == [] and
        (not Rewrite.has_source?(igniter.rewrite, skill) or IgniterCase.source(igniter, skill) == "edited\n")
    end

    assert project.() |> gen_agents() |> kept?.()
    assert project.() |> install() |> kept?.()

    assert project.() |> gen_agents(["--refresh"]) |> IgniterCase.source(skill) == shipped
  end

  describe "links to Brando's files" do
    @repo Path.expand("../../../..", __DIR__)

    test "follow the dependency: relative to the application when they share a directory, else absolute" do
      assert AgentFiles.package_link("/home/me/sites/parrot/deps/brando", "/home/me/sites/parrot") == "deps/brando"
      assert AgentFiles.package_link("/home/me/dev/brando", "/home/me/sites/parrot") == "../../dev/brando"
      assert AgentFiles.package_link("/opt/brando", "/home/me/parrot") == "/opt/brando"
      assert AgentFiles.package_link(nil, "/home/me/parrot") == "deps/brando"
    end

    # The application's agent files from a real install, on disk with
    # Brando (this checkout) as a Hex dependency in deps/ and as a `path:`
    # dependency beside the application: every file they name resolves, and
    # so does every link in the rules files they lead to.
    @tag :tmp_dir
    test "resolve with Brando as a Hex and as a path dependency", %{tmp_dir: tmp} do
      for {layout, brando, link} <- [{"hex", "parrot/deps/brando", "deps/brando"}, {"path", "brando", "../brando"}] do
        app = Path.join([tmp, layout, "parrot"])
        brando = Path.join([tmp, layout, brando])
        File.mkdir_p!(Path.dirname(brando))
        File.mkdir_p!(app)
        File.ln_s!(@repo, brando)

        assert AgentFiles.package_link(brando, app) == link

        igniter = project() |> Igniter.assign(:brando_package_link, link) |> install()
        assert igniter.issues == []

        written = ["AGENTS.md" | Enum.map(AgentFiles.skill_files(), &elem(&1, 0))]
        named = Enum.flat_map(written, &named_paths(IgniterCase.source(igniter, &1), link))

        assert "#{link}/usage-rules.md" in named, layout

        for path <- named do
          assert File.exists?(Path.join(app, path)), "#{layout}: an agent file names #{path}, which does not exist"
        end

        rules = Path.wildcard(Path.join(brando, "usage-rules/*.md"))
        assert length(rules) > 10

        for file <- [Path.join(brando, "usage-rules.md") | rules] do
          contents = File.read!(file)

          refute prose(contents) =~ ~r{deps/brando/\w},
                 "#{file} names a file in deps/brando, which a path dependency lacks"

          for target <- markdown_links(contents) do
            assert File.exists?(Path.join(Path.dirname(file), target)),
                   "#{layout}: #{Path.relative_to(file, brando)} links to #{target}, which does not exist"
          end
        end
      end
    end

    test "a copied skill as Brando shipped it follows the dependency on a rerun, an edited one is kept" do
      [{shipped_skill, shipped} | _] =
        Enum.filter(AgentFiles.skill_files(), fn {_path, contents} -> contents =~ "deps/brando/" end)

      [{edited_skill, _} | _] = AgentFiles.skill_files() -- [{shipped_skill, shipped}]
      relinked = List.keyfind(AgentFiles.skill_files("../brando"), shipped_skill, 0)

      result =
        project(%{shipped_skill => shipped, edited_skill => "edited\n"})
        |> Igniter.assign(:brando_package_link, "../brando")
        |> gen_agents()

      assert result.issues == []
      assert IgniterCase.source(result, shipped_skill) == elem(relinked, 1)
      refute IgniterCase.source(result, shipped_skill) =~ "deps/brando/"
      Igniter.Test.assert_unchanged(result, edited_skill)
    end

    test "an unedited brando section follows the dependency on a rerun, an edited one is kept" do
      legacy = """
      <!-- brando-start -->
      ## brando usage
      [brando usage rules](deps/brando/usage-rules.md): the core rules for building a site. The file ends
      with an index of topic rules in `deps/brando/usage-rules/` (`brando:<topic>`); load one before working
      in its area. The guides they summarize are in `deps/brando/guides/`.
      <!-- brando-end -->\
      """

      for section <- [legacy, AgentFiles.section("deps/brando"), AgentFiles.section("/old/brando")] do
        agents =
          @site_section <>
            String.replace(@phoenix_agents, "<!-- usage-rules-end -->", section <> "\n<!-- usage-rules-end -->")

        result =
          project(%{"AGENTS.md" => agents, "CLAUDE.md" => "@AGENTS.md\n"})
          |> Igniter.assign(:brando_package_link, "../brando")
          |> gen_agents()

        updated = IgniterCase.source(result, "AGENTS.md")
        assert updated == String.replace(agents, section, AgentFiles.section("../brando"))
        assert count(updated, "<!-- brando-start -->") == 1
      end

      edited = String.replace(AgentFiles.section("deps/brando"), "the core rules", "our rules")
      agents = @phoenix_agents <> "\n" <> edited <> "\n" <> @site_section

      result =
        project(%{"AGENTS.md" => agents, "CLAUDE.md" => "@AGENTS.md\n"})
        |> Igniter.assign(:brando_package_link, "../brando")
        |> gen_agents()

      Igniter.Test.assert_unchanged(result, "AGENTS.md")
    end
  end

  # Paths into Brando's package an agent file names, as a link or in backticks.
  defp named_paths(contents, link) do
    links = markdown_links(contents)
    quoted = for [_, path] <- Regex.scan(~r/`([^`\s]+)`/, contents), do: path

    (links ++ quoted)
    |> Enum.filter(&(String.starts_with?(&1, link <> "/") or String.starts_with?(&1, "deps/brando")))
    |> Enum.uniq()
  end

  # Relative link targets, without anchors, outside code fences.
  defp markdown_links(contents) do
    for [_, target] <- Regex.scan(~r/\]\(([^)\s]+)\)/, prose(contents)),
        not String.match?(target, ~r/^([a-z]+:|#)/),
        uniq: true,
        do: target |> String.split("#") |> hd()
  end

  defp prose(contents), do: Regex.replace(~r/^\s*```.*?^\s*```/ms, contents, "")

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
