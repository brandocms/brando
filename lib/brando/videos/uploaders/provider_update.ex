defmodule Brando.Videos.Uploaders.ProviderUpdate do
  @moduledoc """
  Applies a provider's status report to a stored video.

  Each provider reports processing state in its own shape, but once the report
  is turned into video params the write, the ready callback and the broadcast to
  open admin forms are the same.
  """

  alias Brando.Videos

  @doc """
  Updates `video` with `params` as the system (the provider's report is not the
  creator's action, and their role may have changed since the upload), runs the
  creator's completed callback when
  the video has just become ready, and broadcasts the result to subscribers of
  `"brando:video:<id>"` and to the editors following it
  (`Brando.Assets.ProcessingStatus`). Returns `{:ok, video}` or the error from the update.
  """
  def update_video(video, params) do
    with {:ok, creator} <- Brando.Users.get_user(video.creator_id),
         {:ok, updated_video} <- Videos.update_video(video, params, :system) do
      Videos.run_completed_callback_on_ready(video, updated_video, creator)
      broadcast(updated_video)
      {:ok, updated_video}
    end
  end

  @doc """
  Puts `width`, `height` and `aspect_ratio` into `params` when `source` holds
  positive integer dimensions. Providers report 0×0, or nothing, until they have
  probed the source, so anything else leaves `params` unchanged.
  """
  def put_dimensions(params, %{"width" => width, "height" => height})
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    Map.merge(params, %{width: width, height: height, aspect_ratio: "#{width}/#{height}"})
  end

  def put_dimensions(params, _source), do: params

  @doc """
  Tells the open admin forms following `video` (`"brando:video:<id>"`) and
  its editors (`Brando.Assets.ProcessingStatus`) that it changed.
  """
  def broadcast(video) do
    Brando.Assets.ProcessingStatus.broadcast(:video, video, Brando.Assets.ProcessingStatus.video_state(video))

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:video:#{video.id}",
      {video, [:video, :updated]}
    )
  end
end
