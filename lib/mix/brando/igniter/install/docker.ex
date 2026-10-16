if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Install.Docker do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Install.Templates
    alias Rewrite.Source

    # What Brando's release build needs from a Dockerfile, each with the line
    # pattern that shows it is there.
    @dockerfile_parts [
      {~r/^\s*FROM\s.*\sAS\s+assets_backend\s*$/im,
       "an assets_backend stage that installs and builds assets/backend, the admin, with pnpm"},
      {~r/^\s*FROM\s.*\sAS\s+assets_frontend\s*$/im,
       "an assets_frontend stage that installs and builds the site's assets/frontend with pnpm"},
      {~r/\bmix\s+brando\.digest\b/, "`mix brando.digest` over the priv/static both builds write"},
      {~r/^\s*WORKDIR\s+\/opt\/app\/?\s*$/im,
       "the release built in /opt/app with `mix release` (Florist copies the tarball from there)"}
    ]

    # Kept out of the build context: Florist sends it to the Docker daemon,
    # which may be remote, on every build. Each line with the paths it must
    # exclude.
    @context_exclusions [
      {"_build", ["_build"]},
      {"deps", ["deps"]},
      {"assets/backend/node_modules", ["assets/backend/node_modules"]},
      {"assets/frontend/node_modules", ["assets/frontend/node_modules"]},
      {"media", ["media"]},
      {"release-archives", ["release-archives"]},
      {"sql", ["sql"]},
      {".envrc*", [".envrc", ".envrc.prod", ".envrc.staging"]}
    ]

    @doc """
    Writes Brando's Dockerfile and `.dockerignore` when the application has
    none. Florist builds the release with `docker build -f Dockerfile .` and
    copies `/opt/app/_build/prod/<app>-<version>.tar.gz` out of the image.

    An existing Dockerfile is kept, with a notice naming what Brando's build
    needs that it lacks. An existing `.dockerignore` gets the exclusions it is
    missing (dependencies, build output, uploads, Florist's archives and
    database dumps, and the environment files with secrets) appended; one with
    `!` exceptions, which an appended line could override, gets a notice
    instead.
    """
    def plan(igniter, project) do
      igniter
      |> dockerfile(project)
      |> dockerignore()
    end

    defp dockerfile(igniter, project) do
      if Igniter.exists?(igniter, "Dockerfile") do
        {igniter, contents} = contents(igniter, "Dockerfile")

        dockerfile_notice(
          igniter,
          project,
          for({pattern, part} <- @dockerfile_parts, not Regex.match?(pattern, contents), do: part)
        )
      else
        Files.create(igniter, "Dockerfile", Templates.contents(:copy, "Dockerfile"))
      end
    end

    defp dockerfile_notice(igniter, _project, []), do: igniter

    defp dockerfile_notice(igniter, project, missing) do
      Igniter.add_notice(igniter, """
      The existing Dockerfile was kept. Florist builds the release with `docker build -f Dockerfile .`
      and copies /opt/app/_build/prod/#{project.otp_app}-<version>.tar.gz out of the image, and Brando's
      build also needs what this Dockerfile lacks:
      #{Enum.map_join(missing, "\n", &"  * #{&1}")}
      Brando's template is deps/brando/priv/templates/brando.install/Dockerfile; to use it, move this
      Dockerfile aside and rerun mix brando.install.
      """)
    end

    defp dockerignore(igniter) do
      if Igniter.exists?(igniter, ".dockerignore") do
        {igniter, contents} = contents(igniter, ".dockerignore")
        rules = rules(contents)
        missing = for {line, paths} <- @context_exclusions, not Enum.all?(paths, &excluded?(rules, &1)), do: line
        exclude(igniter, missing, Enum.any?(rules, &match?({true, _}, &1)))
      else
        Files.create(igniter, ".dockerignore", Templates.contents(:copy, "dockerignore"))
      end
    end

    defp exclude(igniter, [], _exceptions?), do: igniter
    defp exclude(igniter, missing, true = _exceptions?), do: dockerignore_notice(igniter, missing)
    defp exclude(igniter, missing, false), do: Igniter.update_file(igniter, ".dockerignore", &append(&1, missing))

    defp append(source, missing) do
      Source.update(source, :content, fn content ->
        String.trim_trailing(content) <>
          "\n\n# Kept out of the Docker build context by Brando\n" <> Enum.join(missing, "\n") <> "\n"
      end)
    end

    defp dockerignore_notice(igniter, missing) do
      Igniter.add_notice(igniter, """
      .dockerignore has exceptions (`!` lines), so it was left unchanged. Make sure it keeps these
      out of the Docker build context, which Florist sends to the Docker daemon on every build:
      #{Enum.map_join(missing, "\n", &"  #{&1}")}
      """)
    end

    # Docker's rule: patterns are matched from the context root, a pattern
    # that matches a directory excludes what is in it, and the last pattern
    # matching a path or one of its parents decides, a leading ! re-including.
    defp excluded?(rules, path) do
      paths = path |> Path.split() |> Enum.scan(&Path.join(&2, &1))

      Enum.reduce(rules, false, fn {negated?, regex}, excluded? ->
        if Enum.any?(paths, &Regex.match?(regex, &1)), do: not negated?, else: excluded?
      end)
    end

    defp rules(contents) do
      contents
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(fn
        "" -> []
        "#" <> _ -> []
        "!" <> pattern -> rule(true, pattern)
        pattern -> rule(false, pattern)
      end)
    end

    # Character classes and escapes are not read: such an exclusion never
    # counts, and such an exception counts as re-including everything.
    defp rule(negated?, pattern) do
      pattern = pattern |> String.trim_leading("/") |> String.trim_leading("./") |> String.trim_trailing("/")

      cond do
        String.contains?(pattern, ["[", "\\"]) -> if negated?, do: [{true, ~r/.*/}], else: []
        pattern == "" -> []
        true -> [{negated?, Regex.compile!("^" <> glob(pattern) <> "$")}]
      end
    end

    defp glob(pattern) do
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*/", "(.*/)?")
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> String.replace("\\?", "[^/]")
    end

    defp contents(igniter, path) do
      igniter = Igniter.include_existing_file(igniter, path)
      {igniter, igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)}
    end
  end
else
  defmodule Mix.Brando.Igniter.Install.Docker do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
