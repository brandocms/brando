defmodule Brando.Worker.VideoMetadata do
  @moduledoc """
  Looks up one video's thumbnail, title, duration and size at its source and
  fills in what the video lacks (see `Brando.Videos.fetch_metadata/2`).

  A source that cannot be read, or a video that is gone, is not retried.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:tenant_prefix, :video_id], states: :incomplete]

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Videos.Video

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"video_id" => video_id, "user_id" => user_id}}) do
    with %Video{deleted_at: nil} = video <- Brando.Repo.get(Video, video_id),
         %Brando.Users.User{} = user <- Brando.Repo.get(Brando.Users.User, user_id) do
      case Brando.Videos.fetch_metadata(video, user) do
        {:ok, _} -> :ok
        {:error, :unsupported} -> {:cancel, :unsupported}
        {:error, {:http, status}} when status in 400..499 -> {:cancel, {:http, status}}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:cancel, :gone}
    end
  end
end
