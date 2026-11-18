defmodule BrandoAdmin.LockedGalleryVarTest do
  # A gallery variable writes its gallery as it is edited, before any entry
  # save. In a synchronized translation the variable holds the source's
  # gallery (media in blocks follows the source), so the save's check never
  # sees those writes. Each event that writes the gallery is refused in the
  # translation, and the source's gallery stays as it was; the same events
  # from the source's form still write it.
  use Brando.LiveCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Galleries.{Gallery, GalleryObject}
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias BrandoAdmin.Components.Form.Input.RenderVar

  # Where the block keeps its gallery variable: its content, its settings
  # dialog, or a table row (each rendered by `Block.Render`)
  @placements [:content, :config, :table_row]

  defp block_attrs(:table_row, gallery) do
    %{"table_rows" => [%{"vars" => [Map.put(album_var(:content), "gallery_id", gallery.id)]}]}
  end

  defp block_attrs(placement, gallery), do: %{"vars" => [Map.put(album_var(placement), "gallery_id", gallery.id)]}

  defp album_var(placement),
    do: %{"type" => "gallery", "key" => "album", "label" => %{"en" => "Album"}, "placement" => to_string(placement)}

  defp module_attrs(:table_row, _user) do
    template = Repo.insert!(%Brando.Content.TableTemplate{uid: Brando.Utils.generate_uid(), name: "Albums"})

    Repo.insert!(%Brando.Content.Var{
      type: :gallery,
      key: "album",
      label: %{"en" => "Album"},
      table_template_id: template.id
    })

    [vars: [], table_template_id: template.id]
  end

  defp module_attrs(placement, _user), do: [vars: [Map.put(album_var(placement), "sequence", 0)]]

  setup %{current_user: user, placement: placement} do
    [first, second, third] = for _ <- 1..3, do: Factory.insert(:image, creator: user, status: :processed)
    video = Factory.insert(:video)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(
          :module,
          [name: %{"en" => "Album"}, namespace: %{"en" => "Content"}, help_text: %{}, code: "<div></div>", refs: []] ++
            module_attrs(placement, user)
        ),
        user
      )

    gallery =
      Repo.insert!(%Gallery{
        config_target: "default",
        gallery_objects: [
          %GalleryObject{image_id: first.id, sequence: 0},
          %GalleryObject{image_id: second.id, sequence: 1}
        ]
      })

    {:ok, source} =
      SyncTest.create_article(%{title: "Album", slug: "album", language: "no", status: "published", year: 2020}, user)

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        Map.merge(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => module.id,
            "creator_id" => user.id,
            "source" => to_string(Article.Blocks)
          },
          block_attrs(placement, gallery)
        ),
        user
      )
      |> Repo.insert!()

    struct(Article.Blocks, %{entry_id: source.id, block_id: block.id, sequence: 0}) |> Repo.insert!()
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)

    # The translation starts with a copy of the gallery. The source's next save
    # points its variable at the source's own gallery, as media follows the
    # source; the translation's form opens with that pending version applied.
    Translations.source_saved(load(source.id))

    %{source: source, target: target, gallery: gallery, first: first, third: third, video: video}
  end

  defp load(id) do
    {:ok, entry} = SyncTest.get_article(%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(Article)})
    entry
  end

  # The first submit asks the browser for the form (`b:submit`), the second saves
  defp save(view) do
    view |> form("#article_form_form") |> render_submit(%{})
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit(%{})
    assert_redirect(view, 3_000)
  end

  defp stored_gallery_id(%{id: id}) do
    [%{block: block}] = load(id).entry_blocks
    [var] = block.vars ++ Enum.flat_map(block.table_rows, & &1.vars)
    var.gallery_id
  end

  defp media(%{id: id}) do
    Repo.all(
      from(o in GalleryObject,
        where: o.gallery_id == ^id,
        order_by: o.sequence,
        select: {o.image_id, o.video_id}
      )
    )
  end

  # A variable in the settings dialog renders while the dialog is open
  defp open(conn, id, placement) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{id}", "article_form")
    await_selector(view, "[data-block-uid]")

    if placement == :config do
      [%{block: %{uid: uid}}] = load(id).entry_blocks
      view |> element(~s(button.menu-item[phx-click="open_block_config"][phx-value-uid="#{uid}"])) |> render_click()
    end

    await_selector(view, ~s([id$="-gallery-media"]))
    view
  end

  # The gallery variable's component, as its own events reach it
  defp var_component(view), do: with_target(view, cid_of(view, ~s([id$="-gallery-media"])))

  defp var_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == RenderVar and &1.assigns[:type] == :gallery)).assigns
  end

  defp var_component_id(view), do: var_assigns(view).id

  # A delivery to the component (an upload, or a video from the picker), and
  # the render that follows it
  defp send_var(view, message) do
    Phoenix.LiveView.send_update(view.pid, RenderVar, [id: var_component_id(view)] ++ message)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  for placement <- @placements do
    describe "a gallery variable (#{placement}) in a synchronized translation" do
      @describetag placement: placement

      # The translation is saved with the source's changes, as an editor does:
      # from then on its variable stores the source's gallery.
      setup %{conn: conn, target: target, current_user: user, placement: placement} do
        view = open(conn, target.id, placement)
        await_selector(view, "input[name='translation_review[version_id]']")
        save(view)

        view = open(conn, target.id, placement)
        Brando.endpoint().subscribe("user:#{user.id}")
        %{view: view}
      end

      test "the gallery variable stores the source's gallery", c do
        assert stored_gallery_id(c.target) == c.gallery.id
        assert var_assigns(c.view).gallery_id == c.gallery.id
      end

      test "choosing an image leaves the source's gallery as it was", c do
        before = media(c.gallery)
        c.view |> var_component() |> render_click("select_image", %{"id" => to_string(c.third.id)})
        assert_receive %Phoenix.Socket.Broadcast{event: "toast"}, 2_000
        assert media(c.gallery) == before
      end

      test "choosing a video leaves the source's gallery as it was", c do
        before = media(c.gallery)
        c.view |> var_component() |> render_click("select_video", %{"id" => to_string(c.video.id)})
        assert media(c.gallery) == before
      end

      test "choosing an image again, to take it out, leaves the source's gallery as it was", c do
        before = media(c.gallery)
        c.view |> var_component() |> render_click("select_image", %{"id" => to_string(c.first.id)})
        assert media(c.gallery) == before
      end

      test "removing an item leaves the source's gallery as it was", c do
        before = media(c.gallery)
        [object | _] = Repo.preload(c.gallery, :gallery_objects, force: true).gallery_objects
        c.view |> var_component() |> render_click("remove_gallery_object", %{"id" => to_string(object.id)})
        assert media(c.gallery) == before
      end

      test "resetting and then choosing writes no gallery", c do
        before = media(c.gallery)
        count = Repo.aggregate(Gallery, :count)
        component = var_component(c.view)
        render_click(component, "reset_gallery", %{})
        render_click(component, "select_image", %{"id" => to_string(c.third.id)})
        assert media(c.gallery) == before
        assert Repo.aggregate(Gallery, :count) == count
      end

      test "an upload delivered to the variable leaves the source's gallery as it was", c do
        before = media(c.gallery)
        send_var(c.view, event: "upload_complete", asset_type: :image, asset: c.third, expected_asset_id: nil)
        assert media(c.gallery) == before
      end

      test "a video handed over by the picker leaves the source's gallery as it was", c do
        before = media(c.gallery)
        send_var(c.view, event: "select_video", id: c.video.id)
        send_var(c.view, event: "video_created_from_url", video_data: %{id: c.video.id})
        assert media(c.gallery) == before
      end

      test "the view stays up", c do
        c.view |> var_component() |> render_click("select_image", %{"id" => to_string(c.third.id)})
        assert Process.alive?(c.view.pid)
        assert render(c.view) =~ "is-source-locked"
      end
    end

    describe "a gallery variable (#{placement}) in the source" do
      @describetag placement: placement

      setup %{conn: conn, source: source, placement: placement} do
        %{view: open(conn, source.id, placement)}
      end

      test "choosing an image adds it to the gallery", c do
        c.view |> var_component() |> render_click("select_image", %{"id" => to_string(c.third.id)})
        assert {c.third.id, nil} in media(c.gallery)
      end

      test "removing an item takes it out of the gallery", c do
        [object | _] = Repo.preload(c.gallery, :gallery_objects, force: true).gallery_objects
        c.view |> var_component() |> render_click("remove_gallery_object", %{"id" => to_string(object.id)})
        refute {object.image_id, nil} in media(c.gallery)
      end

      test "an upload delivered to the variable is added to the gallery", c do
        send_var(c.view, event: "upload_complete", asset_type: :image, asset: c.third, expected_asset_id: nil)
        assert {c.third.id, nil} in media(c.gallery)
      end
    end
  end
end
