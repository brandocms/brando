if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.Release do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Project.MixProject
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Files
    alias Mix.Brando.Igniter.Template

    @doc """
    Plans what Florist's deploy needs from the release: `<App>.ReleaseTasks`,
    whose `migrate/0` Florist runs with `bin/<app> eval`, and a Mix release for
    the application that also writes the tarball Florist copies out of the
    Docker image (`steps: [:assemble, :tar]`).

    A missing release definition is added; an existing one is kept, with a
    notice when it does not write the tarball. With `existing: :keep`
    (`brando.install`), an existing ReleaseTasks module is kept whatever it
    holds; otherwise (`brando.gen.release`) a ReleaseTasks file that differs
    from the template is an issue.
    """
    def plan(igniter, project, opts \\ []) do
      igniter
      |> release_tasks(project, Keyword.get(opts, :existing, :issue))
      |> release(project)
    end

    defp release_tasks(igniter, project, :keep) do
      module = Module.concat(project.app_module, ReleaseTasks)

      case ProjectModule.find_module(igniter, module) do
        {:ok, {igniter, _source, zipper}} -> migrate_notice(igniter, project, zipper)
        {:error, igniter} -> release_tasks(igniter, project, :issue)
      end
    end

    defp release_tasks(igniter, project, :issue) do
      binding = [application_name: to_string(project.otp_app), application_module: inspect(project.app_module)]
      path = "lib/#{Macro.underscore(Module.concat(project.app_module, ReleaseTasks))}.ex"

      case Template.render(igniter, "brando.install", "lib/application_name/release_tasks.ex", binding) do
        {:ok, igniter, contents} -> Files.create(igniter, path, contents)
        {:error, message} -> Igniter.add_issue(igniter, message)
      end
    end

    defp migrate_notice(igniter, project, zipper) do
      case Igniter.Code.Function.move_to_def(zipper, :migrate, 0) do
        {:ok, _} ->
          igniter

        :error ->
          Igniter.add_notice(igniter, """
          #{inspect(project.app_module)}.ReleaseTasks has no migrate/0. Florist migrates the database with
            bin/#{project.otp_app} eval "#{inspect(project.app_module)}.ReleaseTasks.migrate"
          """)
      end
    end

    defp release(igniter, project) do
      {igniter, steps} = existing_steps(igniter, project.otp_app)

      igniter
      |> MixProject.update(:project, [:releases, project.otp_app], fn
        nil -> {:ok, {:code, quote(do: [include_executables_for: [:unix], steps: [:assemble, :tar]])}}
        zipper -> {:ok, zipper}
      end)
      |> tar_notice(project, steps)
    end

    defp tar_notice(igniter, project, :without_tar) do
      Igniter.add_notice(igniter, """
      The #{project.otp_app} release in mix.exs does not write a tarball. Florist deploys
      _build/prod/#{project.otp_app}-<version>.tar.gz from the Docker image; add :tar to its steps:
        steps: [:assemble, :tar]
      """)
    end

    defp tar_notice(igniter, _project, _steps), do: igniter

    # :without_tar for a literal release definition without :tar in its steps;
    # :ok otherwise, including definitions this cannot read.
    defp existing_steps(igniter, app) do
      igniter = Igniter.include_existing_file(igniter, "mix.exs")
      contents = igniter.rewrite |> Rewrite.source!("mix.exs") |> Rewrite.Source.get(:content)
      {igniter, steps(contents, app)}
    end

    defp steps(contents, app) do
      with {:ok, quoted} <- Code.string_to_quoted(contents),
           releases when is_list(releases) <- project_keyword(quoted, :releases),
           true <- Keyword.keyword?(releases),
           release when is_list(release) <- Keyword.get(releases, app),
           true <- Keyword.keyword?(release) do
        release |> Keyword.get(:steps, [:assemble]) |> tarball()
      else
        _ -> :ok
      end
    end

    defp tarball(steps) when is_list(steps), do: if(:tar in steps, do: :ok, else: :without_tar)
    defp tarball(_computed), do: :ok

    defp project_keyword(quoted, key) do
      {_, found} =
        Macro.prewalk(quoted, nil, fn
          {:def, _, [{:project, _, args}, [do: body]]} = node, nil when args in [nil, []] ->
            {node, if(Keyword.keyword?(body), do: Keyword.get(body, key))}

          node, found ->
            {node, found}
        end)

      found
    end
  end
else
  defmodule Mix.Brando.Igniter.Release do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
