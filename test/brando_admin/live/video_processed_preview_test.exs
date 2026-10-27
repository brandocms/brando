defmodule BrandoAdmin.VideoProcessedPreviewTest do
  @moduledoc """
  A block's video ref and video var hold a Bunny video that is still
  encoding. When Bunny reports it ready, the live preview shows the player
  without a reload of the editor, as the cards do. Before, the cards turned
  ready and the preview kept rendering the video as unready (nothing), from
  the struct preloaded when the entry opened, until the next change to the
  video or a reload.

  The report is not an edit: the block's state in the edit session stays as
  it was, so nothing is marked changed, shipped or saved.
  """
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Content.Block
  alias Brando.EditSession
  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Videos.Uploaders.Bunny

  @cdn "vz-1.b-cdn.net"

  setup %{current_user: user} do
    put_test_env(Bunny,
      api_key: "key",
      library_id: "77",
      cdn_hostname: @cdn,
      webhook_secret: "whsec",
      req_options: [plug: {Req.Test, Bunny}]
    )

    ref_video = processing_video(user, "Ref clip")
    var_video = processing_video(user, "Var clip")
    config_video = processing_video(user, "Config clip")
    videos = %{ref_video: ref_video, var_video: var_video, config_video: config_video}
    {:ok, Map.merge(page_with(user, videos), videos)}
  end

  test "the preview shows a ref's and a var's video once the provider reports them ready", c do
    view = open(c)
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    flush_preview_updates()

    assert {:ok, document} = LivePreview.get_cache(key)
    refute document =~ player(c.ref_video)
    refute document =~ player(c.var_video)
    before = session(c.page)

    report(c.ref_video, %{status: :ready, width: 1280, height: 720})
    assert_preview_shows(key, player(c.ref_video))

    report(c.var_video, %{status: :ready, width: 1280, height: 720})
    assert_preview_shows(key, player(c.var_video))
    assert {:ok, document} = LivePreview.get_cache(key)
    assert document =~ player(c.ref_video)

    # Not an edit: the session holds the same state at the same revision.
    assert session(c.page) == before
    assert Repo.get_by!(Brando.Content.Ref, uid: c.ref_uid).video_id == c.ref_video.id
  end

  # The editor's blocks still carry the video as it was when the entry opened.
  # Any later render (here an entry field's) reads the ready video.
  test "a later preview render reads the ready video, not the one the entry opened with", c do
    view = open(c)
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    flush_preview_updates()

    {:ok, _} = Brando.Videos.Uploaders.ProviderUpdate.update_video(c.ref_video, %{status: :ready})
    {:ok, _} = Brando.Videos.Uploaders.ProviderUpdate.update_video(c.var_video, %{status: :ready})
    flush_preview_updates()

    params =
      view
      |> render()
      |> form_params("#page_form_form")
      |> put_in(["page", "title"], "Typed")
      |> Map.put("_target", ["page", "title"])

    view |> element("#page_form_form") |> render_change(params)

    assert_receive %Phoenix.Socket.Broadcast{event: "update", payload: %{html: html}}, 3_000
    assert html =~ player(c.ref_video)
    assert html =~ player(c.var_video)
  end

  # A saved var in the block's settings is carried as hidden inputs while
  # they are closed: no var component shows it, so the block follows it.
  test "the preview shows a settings var's video once the provider reports it ready", c do
    view = open(c)
    refute has_element?(view, ~s([id$="-video-media"][data-asset-id="#{c.config_video.id}"]))
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    flush_preview_updates()
    before = session(c.page)

    report(c.config_video, %{status: :ready, width: 1280, height: 720})
    assert_preview_shows(key, player(c.config_video))
    assert session(c.page) == before
  end

  test "a report that the video is still processing does not reload the preview", c do
    view = open(c)
    key = open_preview(view)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    flush_preview_updates()

    report(c.ref_video, %{status: :processing})
    refute_receive %Phoenix.Socket.Broadcast{event: "reload"}, 300
  end

  defp assert_preview_shows(key, fragment) do
    assert_receive %Phoenix.Socket.Broadcast{event: "reload"}, 3_000
    await(fn -> match?({:ok, document} when is_binary(document), LivePreview.get_cache(key)) end)
    await(fn -> elem(LivePreview.get_cache(key), 1) =~ fragment end)
  end

  defp player(video), do: "https://#{@cdn}/#{video.meta["bunny"]["video_guid"]}/thumbnail.jpg"

  defp processing_video(user, title) do
    Factory.insert(:video,
      title: title,
      type: :bunny,
      remote_id: nil,
      source_url: nil,
      status: :processing,
      config_target: "default",
      creator_id: user.id,
      meta: %{"bunny" => %{"video_guid" => Ecto.UUID.generate()}}
    )
  end

  # The provider's webhook, as `Bunny.handle_webhook/1` applies it
  defp report(video, params) do
    {:ok, _video} =
      Brando.Videos.Uploaders.ProviderUpdate.update_video(Repo.get!(Brando.Videos.Video, video.id), params)
  end

  defp session(page) do
    pid = EditSession.whereis(EditSession.ref(Page, page.id, page.language))
    {:ok, %{rev: rev, state: state}} = EditSession.fetch(pid, :blocks)
    {rev, state}
  end

  defp open(%{conn: conn, page: page}) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp open_preview(view) do
    view |> element("button[phx-click=toggle_preview_targets]") |> render_click()
    view |> element("button.preview-choice", "Blocks") |> render_click()
    html = await_selector(view, "iframe[src*='__livepreview']")
    [key] = Regex.run(~r/__livepreview\?key=([A-Za-z0-9_-]+)/, html, capture: :all_but_first)
    Brando.endpoint().subscribe("live_preview:#{key}")
    key
  end

  defp flush_preview_updates do
    receive do
      %Phoenix.Socket.Broadcast{} -> flush_preview_updates()
    after
      1_200 -> :ok
    end
  end

  defp page_with(user, videos) do
    module =
      ProposalFixtures.module!(
        user,
        "Film",
        ~s(<div>{% ref refs.clip %}{% video film { autoplay: true } %}{% video backdrop { autoplay: true } %}</div>),
        refs: [ProposalFixtures.ref("clip", %{type: "video", data: %{}})],
        vars: [
          %{type: "video", key: "film", label: "Film"},
          %{type: "video", key: "backdrop", label: "Backdrop", placement: "config"}
        ]
      )

    page = Factory.insert(:page, creator: user, title: "Films", uri: "films")
    ref_uid = Brando.Utils.generate_uid()

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "sequence" => 0,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks),
          "refs" => [
            %{
              "uid" => ref_uid,
              "name" => "clip",
              "sequence" => 0,
              "video_id" => videos.ref_video.id,
              "data" => %{"type" => "video", "data" => %{}}
            }
          ],
          "vars" => [
            %{"type" => "video", "key" => "film", "label" => "Film", "sequence" => 0, "video_id" => videos.var_video.id},
            %{
              "type" => "video",
              "key" => "backdrop",
              "label" => "Backdrop",
              "placement" => "config",
              "sequence" => 1,
              "video_id" => videos.config_video.id
            }
          ]
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    %{page: page, ref_uid: ref_uid}
  end
end
