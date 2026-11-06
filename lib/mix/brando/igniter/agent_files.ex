if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.AgentFiles do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    # Gives coding agents in the application what Brando ships for them:
    #
    #   * the site-building skills in Brando's `usage-rules/skills/`, copied to
    #     `.claude/skills/`. A skill file that already exists is left alone, so
    #     reruns and upgrades keep the application's edits; `refresh: true`
    #     (`mix brando.gen.agents --refresh`) replaces them with the shipped
    #     versions;
    #   * a link to `deps/brando/usage-rules.md` in AGENTS.md, inside the
    #     markers the `usage_rules` package maintains, so `mix usage_rules.sync`
    #     can later take the section over;
    #   * a site section in AGENTS.md, before those markers so a sync never
    #     rewrites it: the application owns it once written;
    #   * CLAUDE.md importing AGENTS.md, so both agents read one file.

    @skills_source "usage-rules/skills"
    @skills_target ".claude/skills"
    @agents "AGENTS.md"
    @claude "CLAUDE.md"
    @claude_import "@AGENTS.md"
    @usage_rules_start "<!-- usage-rules-start -->"
    @site_start "<!-- brando-site-start -->"
    @site_section """
    <!-- brando-site-start -->
    ## This site

    TODO: who the client is, what the site is for, and anything about its
    content an agent should know before changing it.

    ### Running it

    - `mix phx.server` serves the site and the admin (`/admin`). Its
      `Brando.Vite` watchers in `config/dev.exs` start the two Vite dev
      servers; without them, run `pnpm dev` in each bundle.
    - The bundles each have their own `pnpm install`: `assets/frontend` (the
      public site, port 3000) and `assets/backend` (the admin, port 3333).
      Both ports are strict, so a taken port fails. To move one, set
      `BRANDO_VITE_FRONTEND_PORT` or `BRANDO_VITE_ADMIN_PORT` in the
      environment both Vite and Phoenix read.
    - `pnpm build` in each bundle writes to `priv/static`.

    ### Frontend work

    - Read `.claude/skills/brando-frontend/SKILL.md` before writing CSS,
      module markup, Moonwalk attributes or JS for the public site, or admin
      module previews.
    - Read `.claude/skills/brando-europacss/SKILL.md` before writing EuropaCSS
      at-rules (`@space`, `@fontsize`, `@responsive`…), `theme()` or
      `europa.json5`.
    <!-- brando-site-end -->
    """
    @section_start "<!-- brando-start -->"
    @section """
    <!-- brando-start -->
    ## brando usage
    [brando usage rules](deps/brando/usage-rules.md): the core rules for building a site. The file ends
    with an index of topic rules in `deps/brando/usage-rules/` (`brando:<topic>`); load one before working
    in its area. The guides they summarize are in `deps/brando/guides/`.
    <!-- brando-end -->\
    """

    @doc """
    Plans the agent files. Existing files are kept unless `refresh: true`,
    which replaces existing skill files with the shipped versions (CLAUDE.md
    and AGENTS.md are always kept).
    """
    def plan(igniter, opts \\ []) do
      igniter
      |> skills(Keyword.get(opts, :refresh, false))
      |> claude_md()
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

    # Not `create_new_file(..., on_exists: :skip)`: Igniter reads a file that
    # exists on disk but no task has loaded yet, and adds it with the new
    # contents, replacing it.
    defp skills(igniter, refresh?) do
      Enum.reduce(skill_files(), igniter, fn {path, contents}, igniter ->
        cond do
          refresh? ->
            Igniter.create_or_update_file(igniter, path, contents, &Rewrite.Source.update(&1, :content, contents))

          Igniter.exists?(igniter, path) ->
            igniter

          true ->
            Igniter.create_new_file(igniter, path, contents)
        end
      end)
    end

    defp agents_md(igniter) do
      if Igniter.exists?(igniter, @agents) do
        Igniter.update_file(igniter, @agents, &update_agents_md/1)
      else
        Igniter.create_new_file(igniter, @agents, "" |> add_section() |> add_site_section())
      end
    end

    defp update_agents_md(source) do
      content = Rewrite.Source.get(source, :content)
      updated = content |> link_rules() |> add_site_section()

      if updated == content, do: source, else: Rewrite.Source.update(source, :content, updated)
    end

    defp claude_md(igniter) do
      cond do
        not Igniter.exists?(igniter, @claude) ->
          Igniter.create_new_file(igniter, @claude, @claude_import <> "\n")

        imports_agents?(igniter) ->
          igniter

        true ->
          Igniter.add_notice(
            igniter,
            "CLAUDE.md does not import AGENTS.md, so Claude Code misses Brando's rules and the site section. " <>
              "Move what it adds over to AGENTS.md and replace it with a line reading #{@claude_import}."
          )
      end
    end

    # An `@AGENTS.md` import outside code blocks (Claude Code ignores those),
    # or a symlink to AGENTS.md: replacing that as the notice says would
    # overwrite AGENTS.md through the link.
    defp imports_agents?(igniter) do
      code_blocks = ~r/^\s*```.*?^\s*```/ms
      claude = Regex.replace(code_blocks, content(igniter, @claude), "")

      claude =~ ~r{(^|\s)@(\./)?AGENTS\.md(\s|$)} or links_to_agents?(igniter)
    end

    # Test projects have no symlinks; their CLAUDE.md is not on disk.
    defp links_to_agents?(igniter) do
      with false <- Map.get(igniter.assigns, :test_mode?, false),
           {:ok, target} <- File.read_link(@claude) do
        Path.basename(target) == @agents
      else
        _ -> false
      end
    end

    defp content(igniter, path) do
      igniter
      |> Igniter.include_existing_file(path)
      |> Map.fetch!(:rewrite)
      |> Rewrite.source!(path)
      |> Rewrite.Source.get(:content)
    end

    defp link_rules(content) do
      if String.contains?(content, @section_start), do: content, else: add_section(content)
    end

    # Outside the usage-rules markers, which `mix usage_rules.sync` rewrites.
    defp add_site_section(content) do
      cond do
        String.contains?(content, @site_start) ->
          content

        String.contains?(content, @usage_rules_start) ->
          [before, rest] = String.split(content, @usage_rules_start, parts: 2)
          prefix = if String.trim(before) == "", do: "", else: String.trim_trailing(before) <> "\n\n"
          prefix <> @site_section <> "\n" <> @usage_rules_start <> rest

        true ->
          String.trim_trailing(content) <> "\n\n" <> @site_section
      end
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
