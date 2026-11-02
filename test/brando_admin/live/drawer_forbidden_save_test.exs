defmodule BrandoAdmin.DrawerForbiddenSaveTest do
  # With group authorization, a drawer save is an entry event: it passes the
  # event check with a grant to update the page, and the asset's context then
  # refuses an account with no grant to update the asset. The form says why
  # and keeps what was typed in the entry. A drawer its close button saved
  # closes, as for a refused event: the browser has hidden it, and the entry's
  # save waits for it.
  use Brando.LiveCase

  import Brando.Test.Users

  alias Brando.Content.Var
  alias Brando.Files.File
  alias Brando.Images.Image
  alias Brando.Videos.Video
  alias BrandoAdmin.Components.Form

  # The page is published: changing it takes the publish grant too
  @grants ~w(brando.pages.read brando.pages.update brando.pages.publish
             brando.images.read brando.files.read brando.videos.read)
  @refused "You do not have permission for this action."

  setup %{conn: conn} do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)

    {conn, user} = log_in_as(conn, permissions: @grants)
    Phoenix.PubSub.subscribe(Brando.pubsub(), "user:#{user.id}")

    thumbnail = Factory.insert(:image, status: :processed)

    assets = %{
      image: Factory.insert(:image, title: %{"en" => "Lobby"}, status: :processed, focal: %{x: 50, y: 50}),
      file: Repo.insert!(%File{title: "Rates", filename: "rates.pdf", filesize: 1, config_target: "default"}),
      video: Factory.insert(:video, title: "Tour", thumbnail_id: thumbnail.id)
    }

    {:ok, conn: conn, assets: assets, page: Factory.insert(:page, title: "Om oss")}
  end

  defp open(conn, page, kind, asset) do
    var = %Var{page_id: page.id, key: "hero", label: "Hero", type: kind, sequence: 0}
    Repo.insert!(Map.put(var, :"#{kind}_id", asset.id))
    # The tab that edits: another one only looks
    tab = %{"brando_tab" => "drawer", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/pages/update/#{page.id}")
    await_editing_tab(view)

    params = view |> render() |> form_params("#page_form_form") |> put_in(["page", "title"], "Typed")
    view |> element("#page_form_form") |> render_change(Map.put(params, "_target", ["page", "title"]))

    # As the field opens it: loaded, not as the factory built it
    asset = Repo.reload!(asset)
    edit = Map.put(%{id: asset.id, path: [:vars, 0], field: kind, relation_field: :"#{kind}_id"}, kind, asset)
    Phoenix.LiveView.send_update(view.pid, Form, id: "page_form", action: :"update_edit_#{kind}", "edit_#{kind}": edit)
    _ = :sys.get_state(view.pid)
    view
  end

  defp await_editing_tab(view, tries \\ 100) do
    cond do
      form_assigns(view).tab_editing? -> :ok
      tries == 0 -> flunk("the tab never came to edit")
      true -> Process.sleep(20) && await_editing_tab(view, tries - 1)
    end
  end

  defp form(view), do: with_target(view, cid_of(view, "#page_form-el"))

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "page_form")).assigns
  end

  defp shown_title(view), do: view |> render() |> form_params("#page_form_form") |> get_in(["page", "title"])

  defp assert_refused(view) do
    assert Process.alive?(view.pid)
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: @refused}}, 2_000
    assert shown_title(view) == "Typed"
  end

  # What the browser sends: the first submit asks for the form (`b:submit`),
  # the second saves.
  defp save(view) do
    params = view |> render() |> form_params("#page_form_form")
    view |> element("#page_form_form") |> render_submit(params)
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> element("#page_form_form") |> render_submit(params)
  end

  # The save runs once the blocks arrive, after the submit returns
  defp saved_title(page, title, tries \\ 100) do
    case Repo.get!(Brando.Pages.Page, page.id).title do
      ^title -> title
      other when tries == 0 -> other
      _ -> Process.sleep(20) && saved_title(page, title, tries - 1)
    end
  end

  for {kind, {params, schema}} <- [
        image: {%{"title" => %{"en" => "Changed"}}, Image},
        file: {%{"title" => "Changed"}, File},
        video: {%{"title" => "Changed"}, Video}
      ] do
    test "saving the #{kind} drawer without a grant on the #{kind}", %{conn: conn, page: page, assets: assets} do
      kind = unquote(kind)
      asset = Map.fetch!(assets, kind)
      view = open(conn, page, kind, asset)

      view |> form() |> render_hook("save_#{kind}", %{to_string(kind) => unquote(Macro.escape(params))})

      assert_refused(view)
      refute Map.fetch!(form_assigns(view), :"editing_#{kind}?")
      assert Repo.get!(unquote(schema), asset.id).title == asset.title

      save(view)
      assert saved_title(page, "Typed") == "Typed"
    end
  end

  # Closing a drawer submits it: one that only looked closes as usual
  for kind <- [:image, :file, :video] do
    test "closing the #{kind} drawer unchanged without a grant on the #{kind}", %{conn: conn, page: page} = c do
      kind = unquote(kind)
      view = open(conn, page, kind, Map.fetch!(c.assets, kind))

      params = view |> render() |> form_params("##{kind}-drawer-form")
      view |> form() |> render_hook("save_#{kind}", params)

      assert Process.alive?(view.pid)
      refute Map.fetch!(form_assigns(view), :"editing_#{kind}?")
      refute_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: @refused}}, 300
    end
  end

  # An image stored without a focal point shows the middle, 50/50
  test "closing an unchanged drawer on an image with no focal point", %{conn: conn, page: page} do
    image = Factory.insert(:image, title: %{"en" => "Lobby"}, status: :processed, focal: nil)
    view = open(conn, page, :image, image)

    params = view |> render() |> form_params("#image-drawer-form")
    view |> form() |> render_hook("save_image", params)

    assert Process.alive?(view.pid)
    refute_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: @refused}}, 300
  end

  test "resetting the video's thumbnail without a grant on the video", %{conn: conn, page: page, assets: assets} do
    view = open(conn, page, :video, assets.video)

    view |> form() |> render_hook("reset_video_thumbnail", %{})

    assert_refused(view)
    assert form_assigns(view).editing_video?
    assert Repo.get!(Video, assets.video.id).thumbnail_id == assets.video.thumbnail_id
  end

  test "moving the image's focal point without a grant on the image", %{conn: conn, page: page, assets: assets} do
    view = open(conn, page, :image, assets.image)

    view
    |> form()
    |> render_hook("image_editor_save", %{"mode" => "replace", "focal_x" => 10, "focal_y" => 20})

    assert_refused(view)
    assert form_assigns(view).editing_image?
    assert %{x: 50, y: 50} = Repo.get!(Image, assets.image.id).focal
  end
end
