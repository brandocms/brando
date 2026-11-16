defmodule Brando.Doctor.Checks.SoftDeleteRepo do
  @moduledoc """
  Whether the application's repo has Brando's soft-delete functions
  (`use Brando.SoftDelete.Repo`). Every delete and restore, from the admin or
  from code, calls them: without them nothing can be deleted. The
  application refuses to boot without them too (`Brando.System`), so this
  reports what a running node would find if they went missing.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  @impl true
  def id, do: "soft_delete_repo"

  @impl true
  def label, do: dgettext("doctor", "Soft delete")

  @impl true
  def run(_context), do: evaluate(Brando.repo())

  @doc "The result for `repo`."
  def evaluate(repo) do
    if Brando.SoftDelete.Repo.used_by?(repo) do
      ok(dgettext("doctor", "%{repo} has Brando's soft-delete functions", repo: inspect(repo)))
    else
      error(
        dgettext("doctor", "%{repo} lacks Brando's soft-delete functions, so nothing can be deleted",
          repo: inspect(repo)
        ),
        fix: dgettext("doctor", "add use Brando.SoftDelete.Repo to %{repo}, after use Ecto.Repo", repo: inspect(repo))
      )
    end
  end
end
