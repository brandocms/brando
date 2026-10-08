defmodule Brando.Assets.ProcessingStatus do
  @moduledoc """
  Tells every open editor that shows an image or a video when its processing
  has moved on.

  Images are processed by the image processing job, after an upload and
  when their sizes are recreated. Videos are processed by their provider (Mux,
  Bunny, Cloudflare, Vimeo), which reports through
  `Brando.Videos.Uploaders.ProviderUpdate`. Both broadcast here, on a topic per
  asset, so that any form showing the asset can follow it, not only the form
  that uploaded it.

  The older `"brando:image:<id>"` and `"brando:video:<id>"` topics carry the
  uploading form's own delivery: they hold the field path it queued the job
  with, and the form that uploaded subscribes to them. This topic carries only
  the asset, and a form subscribes to it while one of its fields, refs or vars
  shows the asset in processing (`BrandoAdmin.LiveView.Form.ProcessingWatch`).

  Messages are `{:asset_processing, kind, asset, state}`, where `state` is

    * `:progress` - the asset changed, and more is coming (a provider moved
      a video from uploading to processing)
    * `:done` - processing is over: an image is processed, a video is ready
      or failed for good
    * `:failed` - an image's processing failed for good; nothing more will
      come, and the asset is as it was
  """

  alias Phoenix.PubSub

  @type kind :: :image | :video
  @type state :: :progress | :done | :failed

  @doc "The topic for one asset, scoped to the current tenant."
  @spec topic(kind, integer | binary) :: binary
  def topic(kind, id) when kind in [:image, :video],
    do: Brando.Tenant.Topic.scoped("brando:asset_processing:#{kind}:#{id}")

  @doc "Subscribes the calling process to `asset`'s processing reports."
  @spec subscribe(kind, integer | binary) :: :ok | {:error, term}
  def subscribe(kind, id), do: PubSub.subscribe(Brando.pubsub(), topic(kind, id))

  @doc "Unsubscribes the calling process."
  @spec unsubscribe(kind, integer | binary) :: :ok
  def unsubscribe(kind, id), do: PubSub.unsubscribe(Brando.pubsub(), topic(kind, id))

  @doc "Reports `asset`'s processing state to every process following it."
  @spec broadcast(kind, map, state) :: :ok | {:error, term}
  def broadcast(kind, %{id: id} = asset, state) when state in [:progress, :done, :failed] do
    PubSub.broadcast(Brando.pubsub(), topic(kind, id), {:asset_processing, kind, asset, state})
  end

  @doc """
  Is `asset` still being processed? An image is until it is processed, a video
  while it is uploading to or processing at its provider.
  """
  @spec processing?(kind, map | nil) :: boolean
  def processing?(:image, %{id: id, status: status}) when not is_nil(id), do: status != :processed
  def processing?(:video, %{id: id, status: status}) when not is_nil(id), do: status in [:uploading, :processing]
  def processing?(_kind, _asset), do: false

  @doc "The state a provider's report on `video` amounts to."
  @spec video_state(map) :: state
  def video_state(%{status: status}) when status in [:uploading, :processing], do: :progress
  def video_state(_video), do: :done
end
