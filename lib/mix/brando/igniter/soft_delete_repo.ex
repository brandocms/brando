if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SoftDeleteRepo do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false

    alias Igniter.Code.Common
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Project.Module, as: ProjectModule

    @doc """
    `plan/2` for the application's one Ecto repo. With none, or several, it
    changes nothing: `mix brando.install` and the upgrade hook name the repo.
    """
    def plan(igniter) do
      case Igniter.Libs.Ecto.list_repos(igniter) do
        {igniter, [repo]} -> plan(igniter, repo)
        {igniter, _none_or_several} -> igniter
      end
    end

    @doc """
    Adds `use Brando.SoftDelete.Repo` after `use Ecto.Repo` in `repo`, which
    has none: every soft delete and restore calls it. A repo without a
    literal `use Ecto.Repo` is left alone, with a notice naming the line.
    """
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
      #{inspect(repo)} needs Brando's soft-delete functions, or every delete fails. Add, after its use Ecto.Repo:
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
