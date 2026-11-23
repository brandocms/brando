defmodule Brando.TrashOnRead do
  @moduledoc """
  Trashes a video the moment a given process has first read it, for tests of
  a completion that reads the video twice (a provider upload's completion,
  then the field or var showing it).
  """
  import Ecto.Query, only: [from: 2]
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Brando.Repo

  @doc "Trashes video `video_id` once `pid` has read it; undone on test exit."
  def trash_video_after_first_read(pid, video_id) do
    id = make_ref()
    event = BrandoIntegration.Repo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(id, event, &__MODULE__.trash_on_read/4, {pid, video_id})
    on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def trash_on_read(_event, _measurements, %{source: "videos"}, {pid, video_id}) do
    if self() == pid and !Process.put(:trashed_on_read, true) do
      Repo.update_all(from(v in Brando.Videos.Video, where: v.id == ^video_id),
        set: [deleted_at: DateTime.truncate(DateTime.utc_now(), :second)]
      )
    end
  end

  def trash_on_read(_event, _measurements, _metadata, _config), do: :ok
end
