if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.AgentFiles do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    # Gives coding agents in the application what Brando ships for them:
    #
    #   * the site-building skills in Brando's `usage-rules/skills/`, copied to
    #     `.claude/skills/`. A skill file that already exists is left alone, so
    #     reruns and upgrades keep the application's edits;
    #   * a link to `deps/brando/usage-rules.md` in AGENTS.md, inside the
    #     markers the `usage_rules` package maintains, so `mix usage_rules.sync`
    #     can later take the section over.

    @skills_source "usage-rules/skills"
    @skills_target ".claude/skills"
    @agents "AGENTS.md"
    @section_start "<!-- brando-start -->"
    @section """
    <!-- brando-start -->
    ## brando usage
    [brando usage rules](deps/brando/usage-rules.md): the core rules for building a site. The file ends
    with an index of topic rules in `deps/brando/usage-rules/` (`brando:<topic>`); load one before working
    in its area. The guides they summarize are in `deps/brando/guides/`.
    <!-- brando-end -->\
    """

    def plan(igniter) do
      igniter
      |> skills()
      |> agents_md()
    end

    @doc "The skill files Brando ships, as `{target_path, contents}`."
    def skill_files(root \\ package_root()) do
      source = Path.join(root, @skills_source)

      source
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()
      |> Enum.map(&{Path.join(@skills_target, Path.relative_to(&1, source)), File.read!(&1)})
    end

    defp skills(igniter) do
      Enum.reduce(skill_files(), igniter, fn {path, contents}, igniter ->
        Igniter.create_new_file(igniter, path, contents, on_exists: :skip)
      end)
    end

    defp agents_md(igniter) do
      if Igniter.exists?(igniter, @agents) do
        Igniter.update_file(igniter, @agents, &link_rules/1)
      else
        Igniter.create_new_file(igniter, @agents, add_section(""))
      end
    end

    defp link_rules(source) do
      content = Rewrite.Source.get(source, :content)

      if String.contains?(content, @section_start),
        do: source,
        else: Rewrite.Source.update(source, :content, add_section(content))
    end

    # Phoenix 1.8 writes its own rules between usage-rules markers; join them.
    defp add_section(content) do
      case String.split(content, "<!-- usage-rules-end -->", parts: 2) do
        [before, rest] ->
          String.trim_trailing(before) <> "\n\n" <> @section <> "\n\n<!-- usage-rules-end -->" <> rest

        [_content] ->
          prefix = if String.trim(content) == "", do: "", else: String.trim_trailing(content) <> "\n\n"
          prefix <> "<!-- usage-rules-start -->\n" <> @section <> "\n<!-- usage-rules-end -->\n"
      end
    end

    # The Brando package's root: deps/brando in an application, the checkout
    # itself when Brando's own tests run the installer.
    defp package_root do
      Mix.Project.deps_paths()[:brando] || Path.expand("../../../..", __DIR__)
    end
  end
else
  defmodule Mix.Brando.Igniter.AgentFiles do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
