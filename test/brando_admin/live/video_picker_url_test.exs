defmodule BrandoAdmin.VideoPickerURLTest do
  @moduledoc """
  "Create video" from a pasted YouTube or Vimeo URL in the video picker. The
  oEmbed lookup is a call to a third party: it must not hold up the editor,
  and its failure must not take it down.
  """
  use Brando.LiveCase

  alias Brando.Videos.Video
  alias BrandoAdmin.Components.VideoPicker

  # Stands in for the video field that opened the picker: records the video
  # the picker hands back.
  defmodule Field do
    @moduledoc false
    use Phoenix.LiveComponent

    def render(assigns), do: ~H"<div id={@id}></div>"

    def update(%{event: "video_created_from_url", video_data: %{id: id}}, socket) do
      send(socket.assigns.test_pid, {:video_created, id})
      {:ok, socket}
    end

    def update(assigns, socket), do: {:ok, assign(socket, assigns)}
  end

  defmodule Host do
    @moduledoc false
    use Phoenix.LiveView

    def mount(_params, %{"test_pid" => test_pid, "user" => user}, socket) do
      {:ok, assign(socket, test_pid: test_pid, current_user: user)}
    end

    def render(assigns) do
      ~H"""
      <.live_component module={Field} id="video-field" test_pid={@test_pid} />
      <.live_component module={VideoPicker} id="video-picker" current_user={@current_user} />
      """
    end
  end

  @url "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  @params %{"width" => 1280, "height" => 720, "source" => "youtube", "remoteId" => "dQw4w9WgXcQ", "url" => @url}

  setup do
    put_test_env(Brando.OEmbed, req_options: [plug: {Req.Test, Brando.OEmbed}])
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    :ok
  end

  test "creates the video with the provider's title", %{conn: conn, current_user: user} do
    Req.Test.stub(Brando.OEmbed, &Req.Test.json(&1, %{"title" => "Never gonna", "description" => "A classic"}))

    view = paste_url(conn, user)
    render_async(view)

    assert %{id: id, title: "Never gonna", caption: "A classic", type: :youtube} = Brando.Repo.one!(Video)
    assert_received {:video_created, ^id}
  end

  test "a provider that cannot be reached is asked once, and the video is still created",
       %{conn: conn, current_user: user} do
    test_pid = self()

    Req.Test.stub(Brando.OEmbed, fn conn ->
      send(test_pid, :oembed_request)
      Req.Test.transport_error(conn, :econnrefused)
    end)

    view = paste_url(conn, user)
    render_async(view)

    assert_received :oembed_request
    refute_received :oembed_request
    assert %{id: id, title: "Youtube Video", type: :youtube} = Brando.Repo.one!(Video)
    assert_received {:video_created, ^id}
  end

  test "the lookup runs off the editor's process", %{conn: conn, current_user: user} do
    test_pid = self()

    Req.Test.stub(Brando.OEmbed, fn conn ->
      send(test_pid, {:oembed_waiting, self()})

      receive do
        :answer -> Req.Test.json(conn, %{"title" => "Slow provider"})
      end
    end)

    view = paste_url(conn, user)

    # The provider has not answered, yet the editor renders.
    assert_receive {:oembed_waiting, provider}, 1000
    assert render(view) =~ "Creating..."
    assert has_element?(view, ".video-picker-analyzing:not(.hidden)")
    assert Brando.Repo.aggregate(Video, :count) == 0

    send(provider, :answer)
    render_async(view)

    assert %{id: id, title: "Slow provider"} = Brando.Repo.one!(Video)
    assert_received {:video_created, ^id}
  end

  defp paste_url(conn, user) do
    {:ok, view, _html} = live_isolated(conn, Host, session: %{"test_pid" => self(), "user" => user})

    Phoenix.LiveView.send_update(view.pid, VideoPicker,
      id: "video-picker",
      config_target: nil,
      event_target: %Phoenix.LiveComponent.CID{cid: cid_of(view, "#video-field")},
      multi: false,
      show_url_input: true,
      selected_videos: []
    )

    view |> with_target(cid_of(view, "#video-picker")) |> render_hook("url", @params)
    view
  end
end
