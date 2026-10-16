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
      # Names standing for every .envrc* file: none, dotted, backup and
      # arbitrary suffixes. Exact names such as .envrc.prod leave the rest out.
      {".envrc*", [".envrc", ".envrc.prod", ".envrc.staging", ".envrc.prod.bak", ".envrc~", ".envrc-x9q"]}
    ]

    @doc """
    Writes Brando's Dockerfile and `.dockerignore` when the application has
    none. Florist builds the release with `docker build -f Dockerfile .` and
    copies `/opt/app/_build/prod/<app>-<version>.tar.gz` out of the image.

    An existing Dockerfile is kept, with a notice naming what Brando's build
    needs that it lacks. An existing `.dockerignore` gets the exclusions it is
    missing (dependencies, build output, uploads, Florist's archives and
    database dumps, and the environment files with secrets) appended. An
    appended line comes last and so overrides any `!` exception matching a path
    it covers: the exclusions such an exception could touch are named in a
    notice instead.
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
        exceptions = for {true, _regex, segments} <- rules, do: segments
        {conflicting, appendable} = Enum.split_with(missing, &conflicts?(exceptions, &1))

        igniter
        |> append(appendable)
        |> dockerignore_notice(conflicting)
      else
        Files.create(igniter, ".dockerignore", Templates.contents(:copy, "dockerignore"))
      end
    end

    defp append(igniter, []), do: igniter
    defp append(igniter, missing), do: Igniter.update_file(igniter, ".dockerignore", &append_lines(&1, missing))

    defp append_lines(source, missing) do
      Source.update(source, :content, fn content ->
        String.trim_trailing(content) <>
          "\n\n# Kept out of the Docker build context by Brando\n" <> Enum.join(missing, "\n") <> "\n"
      end)
    end

    defp dockerignore_notice(igniter, []), do: igniter

    defp dockerignore_notice(igniter, missing) do
      Igniter.add_notice(igniter, """
      .dockerignore has exceptions (`!` lines) that an appended exclusion would override, so these
      were not added. Make sure it keeps them out of the Docker build context, which Florist sends
      to the Docker daemon on every build:
      #{Enum.map_join(missing, "\n", &"  #{&1}")}
      """)
    end

    # Whether an exception could re-include a path the line excludes: one
    # pattern matches a path that is, or is inside, a path the other matches.
    defp conflicts?(exceptions, line) do
      line = segments(line)
      Enum.any?(exceptions, &(&1 == :any or overlap?(&1, line)))
    end

    defp overlap?([], _), do: true
    defp overlap?(_, []), do: true
    defp overlap?(["**" | rest] = a, [_ | b_rest] = b), do: overlap?(rest, b) or overlap?(a, b_rest)
    defp overlap?([_ | a_rest] = a, ["**" | rest] = b), do: overlap?(a, rest) or overlap?(a_rest, b)

    defp overlap?([a | a_rest], [b | b_rest]),
      do: intersect?(String.graphemes(a), String.graphemes(b)) and overlap?(a_rest, b_rest)

    # Whether two single-segment globs (`*`, `?` and literal characters) match
    # a common name.
    defp intersect?([], []), do: true
    defp intersect?(["*" | rest] = a, b), do: intersect?(rest, b) or (b != [] and intersect?(a, tl(b)))
    defp intersect?(a, ["*" | rest] = b), do: intersect?(a, rest) or (a != [] and intersect?(tl(a), b))
    defp intersect?([], _), do: false
    defp intersect?(_, []), do: false
    defp intersect?([a | a_rest], [b | b_rest]), do: (a == b or "?" in [a, b]) and intersect?(a_rest, b_rest)

    # Docker's rule: patterns are matched from the context root, a pattern
    # that matches a directory excludes what is in it, and the last pattern
    # matching a path or one of its parents decides, a leading ! re-including.
    defp excluded?(rules, path) do
      paths = path |> Path.split() |> Enum.scan(&Path.join(&2, &1))

      Enum.reduce(rules, false, fn {negated?, regex, _segments}, excluded? ->
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
        String.contains?(pattern, ["[", "\\"]) -> if negated?, do: [{true, ~r/.*/, :any}], else: []
        pattern == "" -> []
        true -> [{negated?, Regex.compile!("^" <> glob(pattern) <> "$"), segments(pattern)}]
      end
    end

    # A `**` within a segment crosses directories like a whole `**` segment.
    defp segments(pattern) do
      pattern
      |> String.split("/", trim: true)
      |> Enum.map(&if(String.contains?(&1, "**"), do: "**", else: &1))
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
