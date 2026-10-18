if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Deployment do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Config
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Install.Hosts
    alias Mix.Brando.Install.Templates
    alias Rewrite.Source

    @envrc [prod: ".envrc.prod", staging: ".envrc.staging"]
    # dev.exs turns the check off for development; it does not apply to a release.
    # Files these import with a literal path are read too.
    @origin_configs ~w(config/config.exs config/prod.exs config/runtime.exs)
    @release_env "rel/env.sh.eex"
    @release_paths [media_path: "./media", log_dir: "./log"]
    # What a Brando application builds, uploads or downloads in its working
    # folder, beyond what phx.new ignores. priv/static is build output only:
    # Vite builds the admin and the site there, copying their public/ folders,
    # mix brando.digest adds digested copies and the cache manifest, and the
    # installer moves phx.new's own files out (PhoenixStatic). Florist writes
    # release-archives/ and sql/.
    @brando_ignores ~w(
      /assets/backend/node_modules/
      /assets/frontend/node_modules/
      /assets/backend/.yalc/
      /assets/backend/yalc.lock
      /assets/frontend/.yalc/
      /assets/frontend/yalc.lock
      /priv/static/
      /media/
      /log/
      /release-archives/
      /sql/
    )

    @doc """
    Reads what the application already has: the `.envrc.<flavor>` files and the
    hosts they set, any `check_origin` in its base, prod or runtime configuration
    (or a file those import), and its release environment script. Existing files
    and settings are never replaced.
    """
    def existing(igniter) do
      {igniter, check_origin?} = check_origin?(igniter, @origin_configs, MapSet.new())

      {igniter, envrc, unfilled} =
        Enum.reduce(@envrc, {igniter, %{}, []}, fn {flavor, path}, {igniter, envrc, unfilled} ->
          {igniter, contents} = contents(igniter, path)
          unfilled = if contents && contents =~ "__BRANDO_", do: unfilled ++ [path], else: unfilled
          {igniter, Map.put(envrc, flavor, contents && envrc_host(contents)), unfilled}
        end)

      {igniter, release_env} = contents(igniter, @release_env)

      {igniter,
       %{
         check_origin?: check_origin?,
         envrc: Map.new(envrc, fn {flavor, host} -> {flavor, host != nil} end),
         envrc_hosts: envrc |> Map.values() |> Enum.reject(&(&1 in [nil, ""])),
         unfilled_envrc: unfilled,
         release_env: release_env
       }}
    end

    @doc """
    Which guided host questions are worth asking: none when nothing is left to
    generate, only the domain and staging host when only environment files are
    missing, all of them when `check_origin` is.
    """
    def guided(existing) do
      cond do
        not existing.check_origin? -> :all
        not Enum.all?(Map.values(existing.envrc)) -> :hosts
        true -> :none
      end
    end

    @doc """
    Adds `check_origin` to the production endpoint config when a domain was
    given, creates the prod and staging `.envrc` files, ignored by Git, and the
    release script that sources them on the server. Staging runs the prod
    release with its own `.envrc`, so the staging host is a trusted origin of
    the prod config.
    """
    def plan(igniter, project, hosts, existing) do
      created = for {flavor, path} <- @envrc, !existing.envrc[flavor], do: {flavor, path}

      igniter
      |> check_origin(project, hosts, existing)
      |> envrc(project, hosts, created)
      |> fill_secrets(existing.unfilled_envrc)
      |> release_env(project, existing.release_env)
      |> kept_envrc_notice(hosts, existing)
      |> release_paths()
      |> gitignore([
        {"Runtime environments with secrets, uploaded by Florist", Enum.map(created, &"/#{elem(&1, 1)}")},
        {"Brando: asset dependencies and builds, uploads, logs, Florist's archives and dumps", @brando_ignores}
      ])
      |> placeholder_notice(hosts, existing, created)
    end

    # A release evaluates config/prod.exs when it is built, in the Docker
    # image, so Path.expand there would name the image's /opt/app. Relative
    # paths resolve in the release's working directory, where Florist links
    # the persistent media directory.
    defp release_paths(igniter) do
      Enum.reduce(@release_paths, igniter, fn {key, path}, igniter ->
        if own_path?(igniter, key),
          do: igniter,
          else: Config.configure_new(igniter, "prod.exs", :brando, [key], path)
      end)
    end

    # A literal path in the base configuration, or one set at runtime, is the
    # application's own choice.
    defp own_path?(igniter, key) do
      Config.configures_key?(igniter, "runtime.exs", :brando, [key]) or
        match?({:ok, _igniter, path} when is_binary(path), Configuration.read(igniter, key))
    end

    defp host(hosts, :prod), do: hosts.domain
    defp host(hosts, :staging), do: hosts.staging

    defp check_origin(igniter, project, hosts, %{check_origin?: true}) do
      if hosts.explicit? and not hosts.placeholder? do
        Igniter.add_notice(igniter, """
        The application already configures check_origin; it was left unchanged.
        Add the origins you need to #{inspect(project.endpoint)} yourself:
          #{Hosts.check_origin(hosts) |> Enum.map_join(", ", &inspect/1)}
        """)
      else
        igniter
      end
    end

    # Without a real domain, Phoenix's default (the endpoint's URL host, from
    # PHX_HOST) is the only safe check: a placeholder list would reject the
    # application's actual host.
    defp check_origin(igniter, _project, %{placeholder?: true}, _existing), do: igniter

    defp check_origin(igniter, project, hosts, existing) do
      # Hosts the existing environment files serve stay trusted on a rerun.
      placeholder = Hosts.placeholder(project.otp_app)

      served =
        Enum.reject(
          existing.envrc_hosts,
          &(&1 in [placeholder, "localhost"] or String.ends_with?(&1, "." <> placeholder))
        )

      origins = Hosts.check_origin(hosts) ++ Enum.map(served, &"//#{&1}")

      igniter
      |> Config.configure_new("prod.exs", project.otp_app, [project.endpoint, :check_origin], Enum.uniq(origins))
      |> Igniter.add_notice("""
      check_origin for #{inspect(project.endpoint)} in config/prod.exs replaces Phoenix's check
      against the endpoint's URL host. Add any other host the application serves to it.
      """)
    end

    # The files are planned with markers in place of the secrets, so no diff or
    # --dry-run shows them; brando.install.secrets fills them in after accepting.
    defp envrc(igniter, _project, _hosts, []), do: igniter

    defp envrc(igniter, project, hosts, created) do
      created
      |> Enum.reduce(igniter, fn {flavor, path}, igniter ->
        binding = Mix.Brando.Igniter.Install.template_binding(project) ++ [host: host(hosts, flavor)]
        Igniter.create_new_file(igniter, path, EEx.eval_string(Templates.contents(:eex, path), binding, file: path))
      end)
      |> Igniter.add_task("brando.install.secrets", Enum.map(created, &elem(&1, 1)))
    end

    # An earlier run whose secrets task never ran (a failed deps.get, an
    # interrupted install) left the markers in place; fill them in now.
    defp fill_secrets(igniter, []), do: igniter
    defp fill_secrets(igniter, paths), do: Igniter.add_task(igniter, "brando.install.secrets", paths)

    defp release_env(igniter, project, nil),
      do: Mix.Brando.Igniter.Install.copy(igniter, {:eex, @release_env, @release_env}, project)

    defp release_env(igniter, _project, contents) do
      cond do
        not String.contains?(contents, ".envrc.runtime") ->
          release_env_notice(igniter)

        not Regex.match?(~r/RELEASE_DISTRIBUTION=["']?name/, contents) ->
          Igniter.add_notice(igniter, """
          #{@release_env} sources .envrc.runtime but keeps the default short node names, while
          the environment files default RELEASE_NODE to a long name (<app>_prod@127.0.0.1).
          Add `export RELEASE_DISTRIBUTION=name` to it, or the release will not start.
          """)

        true ->
          igniter
      end
    end

    defp release_env_notice(igniter) do
      Igniter.add_notice(igniter, """
      #{@release_env} does not source .envrc.runtime, the environment file Florist copies
      into each release, so .envrc.prod and .envrc.staging do not reach the application.
      Source "$RELEASE_ROOT/.envrc.runtime" in it, before any RELEASE_NODE default.
      """)
    end

    defp kept_envrc_notice(igniter, hosts, existing) do
      kept =
        for {flavor, path} <- @envrc, existing.envrc[flavor], do: "#{path} (asked for PHX_HOST #{host(hosts, flavor)})"

      if hosts.explicit? and not hosts.placeholder? and kept != [] do
        Igniter.add_notice(igniter, """
        Existing environment files were left unchanged: #{Enum.join(kept, ", ")}.
        Set their host yourself if it should change.
        """)
      else
        igniter
      end
    end

    # Each group's lines that .gitignore does not cover yet, under the group's
    # heading.
    defp gitignore(igniter, groups) do
      {igniter, content} = contents(igniter, ".gitignore")
      content = content || ""
      # Git keeps leading spaces and drops unescaped trailing ones.
      lines = content |> String.split("\n") |> Enum.map(&String.trim_trailing/1)
      rules = lines |> Enum.map(&gitignore_rule/1) |> Enum.reject(&is_nil/1)
      exceptions = for "!" <> pattern <- lines, do: pattern

      groups = for {heading, lines} <- groups, do: {heading, Enum.reject(lines, &ignored?(rules, &1))}
      shadowing = for {_heading, lines} <- groups, line <- lines, shadows?(line, exceptions), do: line

      blocks =
        Enum.map_join(groups, fn {heading, lines} ->
          case lines -- shadowing do
            [] -> ""
            missing -> "\n# #{heading}\n" <> Enum.join(missing, "\n") <> "\n"
          end
        end)

      igniter
      |> write_gitignore(blocks)
      |> shadowing_notice(shadowing)
    end

    defp write_gitignore(igniter, ""), do: igniter

    defp write_gitignore(igniter, blocks) do
      Igniter.create_or_update_file(igniter, ".gitignore", String.trim_leading(blocks), fn source ->
        Source.update(source, :content, &(String.trim_trailing(&1) <> "\n" <> blocks))
      end)
    end

    defp shadowing_notice(igniter, []), do: igniter

    defp shadowing_notice(igniter, lines) do
      Igniter.add_notice(igniter, """
      .gitignore has exceptions (`!` lines) inside these directories, and Git cannot re-include a
      file in an ignored directory, so they were not added. Make sure Git ignores what the builds
      write there:
      #{Enum.map_join(lines, "\n", &"  #{&1}")}
      """)
    end

    # Whether a directory line would cancel an exception anchored inside the
    # directory, such as `!/priv/static/.well-known/`. The line still wins over
    # an exception for the directory itself, being last, and a name without a
    # slash (`!.gitkeep`) is not counted: it matches at any depth.
    defp shadows?(line, exceptions) do
      inside = String.trim(line, "/") <> "/"

      String.ends_with?(line, "/") and
        Enum.any?(exceptions, &(&1 |> String.trim("/") |> String.starts_with?(inside)))
    end

    # Git's rule: the last pattern that matches a path decides, a leading !
    # un-ignores, and nothing in an ignored directory can be un-ignored.
    # `line` is the rule this would add, "/path" for a file and "/path/" for a
    # directory. Patterns this does not understand never count as ignoring, so
    # the explicit line gets added.
    defp ignored?(rules, line) do
      dir? = String.ends_with?(line, "/")
      segments = line |> String.trim("/") |> String.split("/")
      depth = length(segments)

      # The path and each directory above it, with its name.
      segments
      |> Enum.scan({"", nil}, fn name, {parent, _name} -> {Path.join(parent, name), name} end)
      |> Enum.with_index(1)
      |> Enum.any?(fn {{path, name}, level} -> ignored_path?(rules, path, name, dir? or level < depth) end)
    end

    defp ignored_path?(rules, path, name, dir?) do
      last_match = rules |> Enum.reverse() |> Enum.find(&rule_matches?(&1, path, name, dir?))
      match?({false, _anchored?, _dir_only?, _regex}, last_match)
    end

    defp rule_matches?({_negated?, anchored?, dir_only?, regex}, path, name, dir?) do
      (dir? or not dir_only?) and Regex.match?(regex, if(anchored?, do: path, else: name))
    end

    defp gitignore_rule(""), do: nil
    defp gitignore_rule("#" <> _), do: nil
    # A negation this matcher cannot read might un-ignore the path, so it
    # counts as matching it: the explicit ignore line gets added.
    defp gitignore_rule("!" <> pattern) do
      case gitignore_rule(pattern) do
        {_, anchored?, dir_only?, regex} -> {true, anchored?, dir_only?, regex}
        nil -> {true, false, false, ~r/.*/}
      end
    end

    # A slash before the end anchors a pattern to the repository root; without
    # one it matches a name at any depth. A trailing slash matches directories
    # only. Character classes and escapes are not read: such a rule never
    # counts as ignoring.
    defp gitignore_rule(pattern) do
      dir_only? = String.ends_with?(pattern, "/")
      pattern = String.trim_trailing(pattern, "/")
      anchored? = String.contains?(pattern, "/")
      pattern = String.trim_leading(pattern, "/")

      if pattern == "" or String.contains?(pattern, ["[", "\\"]) do
        nil
      else
        glob =
          pattern
          |> Regex.escape()
          |> String.replace("\\*\\*/", "(.*/)?")
          |> String.replace("/\\*\\*", "(/.*)?")
          |> String.replace("\\*", "[^/]*")
          |> String.replace("\\?", "[^/]")

        {false, anchored?, dir_only?, Regex.compile!("^#{glob}$")}
      end
    end

    # Only when this run creates environment files: a rerun has nothing to replace.
    defp placeholder_notice(igniter, %{placeholder?: true} = hosts, existing, [_ | _] = created) do
      origin =
        if !existing.check_origin? do
          """
          check_origin was not written, so Phoenix checks WebSocket origins against the
          endpoint's URL host, PHX_HOST. Pass --domain to write it to config/prod.exs.
          """
        end

      envrc = """
      No --domain was given. #{Enum.map_join(created, " and ", &elem(&1, 1))} set PHX_HOST to the
      placeholder #{hosts.domain} (staging: #{hosts.staging}); replace it before deploying.
      """

      Igniter.add_notice(igniter, envrc <> (origin || ""))
    end

    # --origin or --staging-domain without --domain write nothing: a list
    # without the real host would block it.
    defp placeholder_notice(igniter, %{placeholder?: true, explicit?: true}, _existing, []) do
      Igniter.add_notice(igniter, """
      Origins or a staging host take effect only with a domain (--domain, or the domain
      question with --interactive): without the real host, check_origin would block it, so
      nothing was written.
      """)
    end

    defp placeholder_notice(igniter, _hosts, _existing, _created), do: igniter

    defp contents(igniter, path) do
      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        {igniter, igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)}
      else
        {igniter, nil}
      end
    end

    defp envrc_host(contents) do
      case Regex.run(~r/^\s*(?:export\s+)?(?:PHX_HOST|BRANDO_URL_HOST)=["']?([A-Za-z0-9.-]*)/m, contents) do
        [_, host] -> String.downcase(host)
        nil -> ""
      end
    end

    # Any check_origin key counts, whichever endpoint or condition it is under:
    # the application's own choice is kept rather than second-guessed.
    defp check_origin?(igniter, [], _seen), do: {igniter, false}

    defp check_origin?(igniter, [path | paths], seen) do
      if path in seen or not Igniter.exists?(igniter, path) do
        check_origin?(igniter, paths, MapSet.put(seen, path))
      else
        igniter = Igniter.include_existing_file(igniter, path)
        quoted = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:quoted)

        {_, {found?, imports}} =
          Macro.prewalk(quoted, {false, []}, fn
            {:__block__, _, [:check_origin]} = node, {_, imports} -> {node, {true, imports}}
            :check_origin = node, {_, imports} -> {node, {true, imports}}
            {:import_config, _, [import]} = node, {found?, imports} -> {node, {found?, imported(path, import, imports)}}
            node, acc -> {node, acc}
          end)

        if found?,
          do: {igniter, true},
          else: check_origin?(igniter, paths ++ Enum.reverse(imports), MapSet.put(seen, path))
      end
    end

    # Literal paths only: phx.new's import_config "#{config_env()}.exs" is
    # config/prod.exs for a release, which is read anyway.
    defp imported(path, {:__block__, _, [import]}, imports) when is_binary(import) do
      file = import |> Path.expand(Path.dirname(Path.expand(path))) |> Path.relative_to_cwd()
      [file | imports]
    end

    defp imported(_path, _import, imports), do: imports
  end
else
  defmodule Mix.Brando.Igniter.Install.Deployment do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
