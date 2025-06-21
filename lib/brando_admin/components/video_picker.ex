defmodule BrandoAdmin.Components.VideoPicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  def mount(socket) do
    {:ok, assign_new(socket, :z_index, fn -> 1100 end)}
  end

  def update(
        %{config_target: config_target, event_target: event_target, multi: multi, selected_videos: selected_videos},
        socket
      ) do
    {:ok,
     socket
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_videos, selected_videos)
     |> assign_videos()}
  end

  def update(%{selected_videos: selected_videos}, socket) do
    {:ok, assign(socket, :selected_videos, selected_videos)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:multi, fn -> false end)
     |> assign_new(:videos, fn -> [] end)
     |> assign_new(:config_target, fn -> nil end)
     |> assign_new(:event_target, fn -> nil end)
     |> assign_new(:deselect_video, fn -> nil end)
     |> assign_new(:selected_videos, fn -> [] end)}
  end

  def assign_videos(socket) do
    {:ok, videos} =
      Brando.Videos.list_videos(%{
        select: [:id, :type, :title, :caption, :width, :height, :source_url, :remote_id, :config_target, :thumbnail_id],
        filter: %{config_target: socket.assigns.config_target},
        order: "desc id",
        preload: [:thumbnail]
      })

    assign(socket, :videos, videos)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Select video")} close={toggle_drawer("##{@id}")} z={@z_index} dark>
        <:info>
          <%= if @config_target do %>
            <div class="mb-2">
              {gettext("Select similarly typed video from library")}
            </div>
          <% end %>
        </:info>

        <div class="video-picker list" id={"video-picker-drawer-#{@id}"}>
          <%= for video <- @videos do %>
            <div
              class={["video-picker__video", video.id in @selected_videos && "selected"]}
              phx-click={
                if @multi,
                  do: JS.push("select_video", target: @event_target),
                  else: JS.push("select_video", target: @event_target) |> toggle_drawer("#video-picker")
              }
              phx-value-id={video.id}
              phx-value-selected={(video.id in @selected_videos && "true") || "false"}
            >
              <%= case video.type do %>
                <% :upload -> %>
                  <div class="img-placeholder">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100" height="100">
                      <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
                    </svg>
                  </div>
                <% type when type in [:vimeo, :youtube, :external_file] -> %>
                  <%= if video.thumbnail do %>
                    <Content.image image={video.thumbnail} size={:thumb} />
                  <% else %>
                    <div class="img-placeholder">
                      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100" height="100">
                        <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
                      </svg>
                    </div>
                  <% end %>
                <% _ -> %>
                  <div class="img-placeholder">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100" height="100">
                      <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
                    </svg>
                  </div>
              <% end %>
              <div class="video-picker__info">
                <div class="video-picker__title">{video.title || gettext("Untitled")}</div>
                <div class="video-picker__type">
                  Type..........: {video.type}
                </div>
                <%= if video.width && video.height do %>
                  <div class="video-picker__dims">
                    Dimensions....: {video.width}&times;{video.height}
                  </div>
                <% end %>
                <%= if video.source_url do %>
                  <div class="video-picker__source">
                    Source........: {video.source_url}
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </Content.drawer>
    </div>
    """
  end
end
