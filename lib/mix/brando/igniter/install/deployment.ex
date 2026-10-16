if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Deployment do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.Config
    alias Mix.Brando.Install.Hosts
    alias Mix.Brando.Install.Templates
    alias Rewrite.Source

    @envrc [prod: ".envrc.prod", staging: ".envrc.staging"]
    # dev.exs turns the check off for development; it does not apply to a release.
    @origin_configs ~w(config/config.exs config/prod.exs config/runtime.exs)
    @ignore_patterns ~w(.envrc* /.envrc* .envrc.* /.envrc.*)

    @doc """
    Reads what the application already has: the `.envrc.<flavor>` files and any
    `check_origin` in its base, prod or runtime configuration. Existing files and
    settings are never replaced.
    """
    def existing(igniter) do
      {igniter, check_origin?} =
        Enum.reduce(@origin_configs, {igniter, false}, fn path, {igniter, found?} ->
          {igniter, in_file?} = check_origin?(igniter, path)
          {igniter, found? or in_file?}
        end)

      envrc = Map.new(@envrc, fn {flavor, path} -> {flavor, Igniter.exists?(igniter, path)} end)
      {igniter, %{check_origin?: check_origin?, envrc: envrc}}
    end

    @doc "Whether anything is left to generate, so whether guided questions are worth asking."
    def pending?(existing), do: not existing.check_origin? or not Enum.all?(Map.values(existing.envrc))

    @doc """
    Adds `check_origin` to the production endpoint config and creates the prod
    and staging `.envrc` files, ignored by Git. Staging runs the prod release
    with its own `.envrc`, so the staging host is a trusted origin of the prod
    config.
    """
    def plan(igniter, project, hosts, existing) do
      created = for {flavor, path} <- @envrc, !existing.envrc[flavor], do: {flavor, path}

      igniter
      |> check_origin(project, hosts, existing.check_origin?)
      |> envrc(project, hosts, created)
      |> kept_envrc_notice(hosts, existing)
      |> gitignore(Enum.map(created, &elem(&1, 1)))
      |> placeholder_notice(hosts, project, pending?(existing))
    end

    defp host(hosts, :prod), do: hosts.domain
    defp host(hosts, :staging), do: hosts.staging

    defp check_origin(igniter, project, hosts, true) do
      if hosts.explicit? do
        Igniter.add_notice(igniter, """
        The application already configures check_origin; it was left unchanged.
        Add the origins you need to #{inspect(project.endpoint)} yourself:
          #{Hosts.check_origin(hosts) |> Enum.map_join(", ", &inspect/1)}
        """)
      else
        igniter
      end
    end

    defp check_origin(igniter, project, hosts, false) do
      Config.configure_new(
        igniter,
        "prod.exs",
        project.otp_app,
        [project.endpoint, :check_origin],
        Hosts.check_origin(hosts)
      )
    end

    defp envrc(igniter, project, hosts, created) do
      Enum.reduce(created, igniter, fn {flavor, path}, igniter ->
        binding = Mix.Brando.Igniter.Install.template_binding(project) ++ [host: host(hosts, flavor)]
        Igniter.create_new_file(igniter, path, EEx.eval_string(Templates.contents(:eex, path), binding, file: path))
      end)
    end

    defp kept_envrc_notice(igniter, hosts, existing) do
      kept =
        for {flavor, path} <- @envrc, existing.envrc[flavor], do: "#{path} (asked for PHX_HOST #{host(hosts, flavor)})"

      if hosts.explicit? and kept != [] do
        Igniter.add_notice(igniter, """
        Existing environment files were left unchanged: #{Enum.join(kept, ", ")}.
        Set their host yourself if it should change.
        """)
      else
        igniter
      end
    end

    defp gitignore(igniter, []), do: igniter

    defp gitignore(igniter, paths) do
      lines = Enum.map(paths, &"/#{&1}")

      Igniter.create_or_update_file(igniter, ".gitignore", String.trim_leading(missing_block(lines)), fn source ->
        content = Source.get(source, :content)
        ignored = content |> String.split("\n") |> MapSet.new(&String.trim/1)
        missing = Enum.reject(lines, &(MapSet.member?(ignored, &1) or covered?(ignored, &1)))

        if missing == [],
          do: source,
          else: Source.update(source, :content, String.trim_trailing(content) <> "\n" <> missing_block(missing))
      end)
    end

    defp covered?(ignored, "/" <> path),
      do: MapSet.member?(ignored, path) or Enum.any?(@ignore_patterns, &MapSet.member?(ignored, &1))

    defp missing_block(lines),
      do: "\n# Runtime environments with secrets, uploaded by Florist\n" <> Enum.join(lines, "\n") <> "\n"

    defp placeholder_notice(igniter, %{placeholder?: true} = hosts, project, true) do
      Igniter.add_notice(igniter, """
      Deployment hosts use the placeholder #{hosts.domain} (staging: #{hosts.staging}).
      Replace it in #{inspect(project.endpoint)}'s check_origin in config/prod.exs and in
      PHX_HOST in .envrc.prod and .envrc.staging, or pass --domain on a fresh install.
      """)
    end

    defp placeholder_notice(igniter, _hosts, _project, _pending?), do: igniter

    # Any check_origin key counts, whichever endpoint or condition it is under:
    # the application's own choice is kept rather than second-guessed.
    defp check_origin?(igniter, path) do
      if Igniter.exists?(igniter, path) do
        igniter = Igniter.include_existing_file(igniter, path)
        quoted = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:quoted)

        {_, found?} =
          Macro.prewalk(quoted, false, fn
            {:__block__, _, [:check_origin]} = node, _found -> {node, true}
            :check_origin = node, _found -> {node, true}
            node, found -> {node, found}
          end)

        {igniter, found?}
      else
        {igniter, false}
      end
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Deployment do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
