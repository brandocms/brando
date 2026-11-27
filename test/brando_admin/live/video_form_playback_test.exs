defmodule BrandoAdmin.VideoFormPlaybackTest do
  # The Edit video form gives each playback setting the drawer's three states:
  # Default leaves it empty, for the page's or Brando's default. Its switches
  # stored `false` for every setting left off on any save, which made a lazy
  # video eager and stopped a loop from looping.
  use Brando.LiveCase

  alias Brando.Videos.Video
  alias BrandoAdmin.Components.Form

  @settings ~w(autoplay preload loop controls muted)

  defp open(conn, video) do
    tab = %{"brando_tab" => "video", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/assets/videos/update/#{video.id}", "video_form")
    await_editing_tab(view)
    view
  end

  defp await_editing_tab(view, tries \\ 100) do
    cond do
      form_assigns(view).tab_editing? -> :ok
      tries == 0 -> flunk("the tab never came to edit")
      true -> Process.sleep(20) && await_editing_tab(view, tries - 1)
    end
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "video_form")).assigns
  end

  defp save(view, changes) do
    params = view |> render() |> form_params("#video_form_form")
    params = update_in(params["video"], &Map.merge(&1, changes))
    view |> element("#video_form_form") |> render_submit(params)
  end

  defp saved(video, field, expected, tries \\ 100) do
    case Map.fetch!(Repo.reload!(video), field) do
      ^expected -> expected
      other when tries == 0 -> other
      _other -> Process.sleep(20) && saved(video, field, expected, tries - 1)
    end
  end

  test "saving a video whose playback settings are empty leaves them empty", %{conn: conn} do
    video = Factory.insert(:video, title: "Tour")
    view = open(conn, video)

    save(view, %{"title" => "Saved"})

    assert saved(video, :title, "Saved") == "Saved"
    reloaded = Repo.reload!(video)
    for setting <- @settings, do: assert(Map.fetch!(reloaded, String.to_atom(setting)) == nil, setting)
  end

  test "On and Off store true and false, and Default clears them", %{conn: conn} do
    video = Factory.insert(:video, title: "Tour", loop: true)
    view = open(conn, video)

    save(view, %{"preload" => "false", "autoplay" => "true", "loop" => ""})

    assert saved(video, :preload, false) == false
    assert %Video{autoplay: true, loop: nil} = Repo.reload!(video)
  end
end
