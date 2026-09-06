defmodule Brando.Worker.PreviewPurger do
  @moduledoc """
  A Worker for purging previews
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Brando.Sites
  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"id" => id}}) do
    case Brando.Repo.get(Sites.Preview, id) do
      nil ->
        :ok

      preview ->
        now = DateTime.utc_now()
        remaining = DateTime.diff(preview.expires_at, now, :second)

        if DateTime.compare(preview.expires_at, now) == :gt do
          {:snooze, max(remaining, 1)}
        else
          case Sites.delete_preview(id, :system) do
            {:ok, _} -> :ok
            {:error, _} -> :ok
          end
        end
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
