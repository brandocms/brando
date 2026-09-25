defmodule BrandoAdmin.Components.VideoPlayer do
  @moduledoc """
  Plays a video in the admin: the provider's own player for Vimeo and YouTube,
  and a `<video>` element for files and streams. HLS streams go through the
  `Brando.VideoPlayer` hook, since only Safari plays them natively.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Videos.Video

  attr :video, Video, required: true

  def player(assigns) do
    assigns = assign(assigns, source: source(assigns.video), ratio: ratio(assigns.video))

    ~H"""
    <div class="video-player" style={"--video-ratio: #{@ratio}"}>
      <%= case @source do %>
        <% {:embed, url} -> %>
          <iframe
            src={url}
            title={@video.title || gettext("Video")}
            allow="autoplay; fullscreen; picture-in-picture"
            allowfullscreen
          ></iframe>
        <% {:file, url} -> %>
          <video
            id={"video-player-#{@video.id}"}
            phx-hook="Brando.VideoPlayer"
            data-src={url}
            controls
            autoplay
            playsinline
          ></video>
        <% :none -> %>
          <p class="video-player-unavailable">{gettext("This video cannot be played here.")}</p>
      <% end %>
    </div>
    """
  end

  defp source(%Video{type: :vimeo, remote_id: id}) when is_binary(id),
    do: {:embed, "https://player.vimeo.com/video/#{id}?autoplay=1"}

  defp source(%Video{type: :youtube, remote_id: id}) when is_binary(id),
    do: {:embed, "https://www.youtube.com/embed/#{id}?autoplay=1"}

  defp source(%Video{} = video) do
    case Brando.Videos.Helpers.get_playback_url(video) do
      {:ok, url} -> {:file, url}
      _ -> :none
    end
  end

  defp ratio(%Video{width: width, height: height}) when is_integer(width) and is_integer(height) and height > 0,
    do: Float.round(width / height, 4)

  defp ratio(_), do: Float.round(16 / 9, 4)
end
