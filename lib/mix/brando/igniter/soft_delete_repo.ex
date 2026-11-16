if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SoftDeleteRepo do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.Install.Configuration
    alias Mix.Brando.Igniter.Project

    @doc """
    Adds `use Brando.SoftDelete.Repo` after `use Ecto.Repo` in Brando's repo
    when it has none: every soft delete and restore calls it.

    Brando's repo is `repo` when given (a module, or a `--repo` option's
    name), else the one `config :brando, repo_module:` names, else the
    application's one repo outside `test/`; other repos are left alone. When
    none of these names one, or the repo has no literal `use Ecto.Repo`, a
    notice gives the line to add and where.
    """
    def plan(igniter, repo \\ nil)

    def plan(igniter, nil) do
      case brando_repo(igniter) do
        {:ok, igniter, repo} -> plan(igniter, repo)
        {:error, igniter, why} -> Igniter.add_notice(igniter, unresolved_text(why))
      end
    end

    def plan(igniter, repo) when is_binary(repo), do: plan(igniter, Module.concat([repo]))

    def plan(igniter, repo) do
      case ProjectModule.find_module(igniter, repo) do
        {:ok, {igniter, _source, zipper}} ->
          if uses_soft_delete?(zipper),
            do: igniter,
            else: ProjectModule.find_and_update_module!(igniter, repo, &add_use(&1, repo))

        {:error, igniter} ->
          notice(igniter, repo)
      end
    end

    defp brando_repo(igniter) do
      case Configuration.read(igniter, :repo_module) do
        {:ok, igniter, repo} when is_atom(repo) and repo not in [nil, true, false] -> {:ok, igniter, repo}
        {:ok, igniter, nil} -> only_repo(igniter)
        {:ok, igniter, value} -> {:error, igniter, "config :brando, repo_module: is #{inspect(value)}, not a module"}
        {:error, message} -> {:error, igniter, message}
      end
    end

    defp only_repo(igniter) do
      {igniter, repos} = Igniter.Libs.Ecto.list_repos(igniter)

      case repos |> Project.source_modules(igniter) |> Enum.sort() do
        [repo] ->
          {:ok, igniter, repo}

        [] ->
          {:error, igniter, "no Ecto repo was found under lib/"}

        repos ->
          {:error, igniter,
           "config :brando, repo_module: is not set, and there are several repos (#{Enum.map_join(repos, ", ", &inspect/1)})"}
      end
    end

    defp unresolved_text(why) do
      """
      Could not tell which repo is Brando's: #{why}. Brando's repo needs Brando's soft-delete
      functions, and the application stops at boot without them. In that repo (the one
      config :brando, repo_module: names), add after its use Ecto.Repo:
          use Brando.SoftDelete.Repo
      """
    end

    defp uses_soft_delete?(zipper) do
      with {:ok, body} <- Common.move_to_do_block(zipper),
           {:ok, _use} <- CodeModule.move_to_use(body, Brando.SoftDelete.Repo) do
        true
      else
        _ -> false
      end
    end

    defp add_use(zipper, repo) do
      case CodeModule.move_to_use(zipper, Ecto.Repo) do
        {:ok, use_call} -> {:ok, Common.add_code(use_call, "use Brando.SoftDelete.Repo", placement: :after)}
        :error -> {:warning, notice_text(repo)}
      end
    end

    defp notice(igniter, repo), do: Igniter.add_notice(igniter, notice_text(repo))

    defp notice_text(repo) do
      """
      #{inspect(repo)} needs Brando's soft-delete functions, and the application stops at boot
      without them. Add, after its use Ecto.Repo:
          use Brando.SoftDelete.Repo
      """
    end
  end
else
  defmodule Mix.Brando.Igniter.SoftDeleteRepo do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
