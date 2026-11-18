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
    #   * a link to Brando's `usage-rules.md` in AGENTS.md, inside the
    #     markers the `usage_rules` package maintains, so `mix usage_rules.sync`
    #     can later take the section over;
    #   * a site section in AGENTS.md, before those markers so a sync never
    #     rewrites it: the application owns it once written;
    #   * CLAUDE.md importing AGENTS.md, so both agents read one file.
    #
    # The section and the skills name Brando's files by where the application
    # has the dependency (`package_link/2`): `deps/brando` for a Hex or Git
    # dependency, the checkout for a `path:` one. The rules files themselves
    # ship with the package and link relative to their own location.

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
    @section_end "<!-- brando-end -->"
    # What earlier versions wrote, replaced by a rerun while unedited: with a
    # `path:` dependency its links lead nowhere.
    @legacy_section """
    <!-- brando-start -->
    ## brando usage
    [brando usage rules](deps/brando/usage-rules.md): the core rules for building a site. The file ends
    with an index of topic rules in `deps/brando/usage-rules/` (`brando:<topic>`); load one before working
    in its area. The guides they summarize are in `deps/brando/guides/`.
    <!-- brando-end -->\
    """
    @package_placeholder "deps/brando"

    @doc """
    Plans the agent files. Existing files are kept unless `refresh: true`,
    which replaces existing skill files with the shipped versions (CLAUDE.md
    and AGENTS.md are always kept).
    """
    def plan(igniter, opts \\ []) do
      link = package_link(igniter)

      igniter
      |> skills(link, Keyword.get(opts, :refresh, false))
      |> claude_md()
      |> agents_md(link)
    end

    @doc """
    The skill files Brando ships, as `{target_path, contents}`, with their
    paths into the package (`deps/brando/...` in the source) under `link`.
    """
    def skill_files(link \\ @package_placeholder, root \\ package_root()) do
      source = Path.join(root, @skills_source)

      source
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()
      |> Enum.map(&{Path.join(@skills_target, Path.relative_to(&1, source)), &1 |> File.read!() |> relink(link)})
    end

    @doc """
    Where the application's agent files find Brando's package: the path of
    the `:brando` dependency, relative to the application when the two share
    a directory below the filesystem root (`deps/brando`, `../brando`), else
    absolute. `deps/brando` when the application has no `:brando` dependency,
    as in Brando's own repository. An `:brando_package_link` assign takes
    precedence, for tests.
    """
    def package_link(%Igniter{} = igniter) do
      case igniter.assigns[:brando_package_link] do
        nil -> package_link(Mix.Project.deps_paths()[:brando], app_root())
        link -> link
      end
    end

    def package_link(nil, _app), do: @package_placeholder

    def package_link(brando, app) do
      brando = Path.expand(brando)
      app = Path.expand(app)

      if Enum.take(Path.split(brando), 2) == Enum.take(Path.split(app), 2),
        do: Path.relative_to(brando, app, force: true),
        else: brando
    end

    @doc "The `brando` section of AGENTS.md, naming Brando's files under `link`."
    def section(link) do
      """
      <!-- brando-start -->
      ## brando usage
      [brando usage rules](#{link}/usage-rules.md): the core rules for building a site. The file ends
      with an index of topic rules in `#{link}/usage-rules/` (`brando:<topic>`); load one before working
      in its area. The guides they summarize are in `#{link}/guides/`. Links inside those files are
      relative to the file they are in.
      <!-- brando-end -->\
      """
    end

    defp app_root do
      case Mix.Project.project_file() do
        nil -> File.cwd!()
        file -> Path.dirname(file)
      end
    end

    defp relink(contents, @package_placeholder), do: contents
    defp relink(contents, link), do: String.replace(contents, @package_placeholder <> "/", link <> "/")

    # Not `create_new_file(..., on_exists: :skip)`: Igniter reads a file that
    # exists on disk but no task has loaded yet, and adds it with the new
    # contents, replacing it.
    defp skills(igniter, link, refresh?) do
      Enum.reduce(skill_files(link), igniter, fn {path, contents}, igniter ->
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

    defp agents_md(igniter, link) do
      if Igniter.exists?(igniter, @agents) do
        Igniter.update_file(igniter, @agents, &update_agents_md(&1, link))
      else
        Igniter.create_new_file(igniter, @agents, "" |> add_section(link) |> add_site_section())
      end
    end

    defp update_agents_md(source, link) do
      content = Rewrite.Source.get(source, :content)
      updated = content |> link_rules(link) |> add_site_section()

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

    # A section as Brando wrote it, for any package location, follows the
    # dependency; an edited one is the application's.
    defp link_rules(content, link) do
      case String.split(content, @section_start, parts: 2) do
        [_content] ->
          add_section(content, link)

        [before, rest] ->
          with [body, after_section] <- String.split(rest, @section_end, parts: 2),
               section = @section_start <> body <> @section_end,
               true <- generated_section?(section) do
            before <> section(link) <> after_section
          else
            _ -> content
          end
      end
    end

    defp generated_section?(section) do
      section == @legacy_section or
        section |> String.split("\n") |> Enum.at(2, "") |> section_link() |> then(&(&1 && section(&1) == section))
    end

    defp section_link(line) do
      case Regex.run(~r{^\[brando usage rules\]\((.+)/usage-rules\.md\):}, line) do
        [_, link] -> link
        nil -> nil
      end
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
    defp add_section(content, link) do
      case String.split(content, "<!-- usage-rules-end -->", parts: 2) do
        [before, rest] ->
          String.trim_trailing(before) <> "\n\n" <> section(link) <> "\n\n<!-- usage-rules-end -->" <> rest

        [_content] ->
          prefix = if String.trim(content) == "", do: "", else: String.trim_trailing(content) <> "\n\n"
          prefix <> "<!-- usage-rules-start -->\n" <> section(link) <> "\n<!-- usage-rules-end -->\n"
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
