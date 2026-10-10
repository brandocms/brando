defmodule Brando.Worker.VideoMetadataSweep do
  @moduledoc """
  Queues a `Brando.Worker.VideoMetadata` lookup for every video missing its
  thumbnail or title (**Fetch details** in the video library).

  A job rather than a task of the library's LiveView: each lookup is its own
  insert, so a library of thousands takes a while, and an editor leaving the
  page must not cut it short. One waiting sweep per environment.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:tenant_prefix], states: [:available, :scheduled, :retryable], period: :infinity]

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Videos

  @doc "Queues a sweep for `user` in the current environment."
  @spec enqueue(map() | integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(user) do
    # Without tenancy there is no prefix to attach; a nil one gives the
    # uniqueness a key to compare all the same.
    %{"user_id" => user_id(user)}
    |> TenantJob.attach()
    |> Map.put_new("tenant_prefix", nil)
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}} = job) do
    TenantJob.run(job, fn ->
      {:ok, _count} = Videos.enqueue_metadata(Videos.list_video_ids_missing_metadata(), user_id)
      :ok
    end)
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_integer(id), do: id
end
