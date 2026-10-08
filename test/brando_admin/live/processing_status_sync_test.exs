defmodule BrandoAdmin.ProcessingStatusSyncTest do
  # Two editors with one entry open. An image still processing shows
  # "Processing image…" in every field, ref and var that holds it, and each
  # editor's view must leave that state when processing finishes, not only
  # the view of the editor who uploaded it.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Content.Block
  alias Brando.Images.Processing
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures

  # A fixture original `test_helper.exs` copies into the media path, so the
  # real `ImageProcessor` job can process it (Oban runs inline in tests).
  @original "images/avatars/27i97a.jpeg"

  setup %{current_user: user} do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    {:ok, other_conn: log_in_user(Phoenix.ConnTest.build_conn(), other), me: user}
  end

  describe "an entry image field" do
    test "leaves processing in the other editor's form when the job finishes", c do
      image = unprocessed_image(c.me)
      page = Factory.insert(:page, creator: c.me, meta_image_id: image.id)

      {a, _html} = live_form(c.conn, "/admin/pages/update/#{page.id}")
      {b, _html} = live_form(c.other_conn, "/admin/pages/update/#{page.id}")

      for view <- [a, b], do: assert(processing?(view, image))

      {:ok, _job} = Processing.queue_processing(image, c.me)

      for view <- [a, b] do
        await(fn -> processed?(view, image) end)
        assert has_element?(view, "#page_meta_image-media img")
      end
    end

    test "an upload by one editor leaves processing in the other's form too", c do
      image = unprocessed_image(c.me)
      page = Factory.insert(:page, creator: c.me)

      {a, _html} = live_form(c.conn, "/admin/pages/update/#{page.id}")
      {b, _html} = live_form(c.other_conn, "/admin/pages/update/#{page.id}")

      # What the UploadManager sends the uploading form once the file is stored.
      send(a.pid, {:asset_ready, %{"kind" => "entry_field", "field" => "meta_image"}, image})
      await(fn -> processing?(a, image) end)
      await(fn -> processing?(b, image) end)

      {:ok, _job} = Processing.queue_processing(image, c.me)

      for view <- [a, b], do: await(fn -> processed?(view, image) end)
    end

    test "a field that no longer shows the image stops following it", c do
      image = unprocessed_image(c.me)
      other = Factory.insert(:image, creator: c.me, status: :processed, focal: %Brando.Images.Focal{x: 50, y: 50})
      page = Factory.insert(:page, creator: c.me, meta_image_id: image.id)

      {b, _html} = live_form(c.other_conn, "/admin/pages/update/#{page.id}")
      assert processing?(b, image)
      assert topic_subscribers(image) == [b.pid]

      Phoenix.LiveView.send_update(b.pid, BrandoAdmin.Components.Form,
        id: "page_form",
        event: "entry_field_upload_complete",
        asset_type: :image,
        field: :meta_image,
        path: [],
        asset: other
      )

      await(fn -> has_element?(b, ~s([data-asset-id="#{other.id}"])) end)
      await(fn -> topic_subscribers(image) == [] end)
    end
  end

  describe "a block's picture ref and image var" do
    setup %{me: user} do
      image = unprocessed_image(user)
      %{page: page, ref_uid: ref_uid} = page_with_picture_and_image_var(user, image)
      {:ok, image: image, page: page, ref_uid: ref_uid}
    end

    test "leave processing in both editors' block editors when the job finishes", c do
      a = open(c.conn, c.page)
      b = open(c.other_conn, c.page)

      # The ref, its settings modal's copy, and the var.
      for view <- [a, b] do
        assert has_element?(view, ~s(#block-#{c.ref_uid}-upload[data-processing-image="true"]))
        assert has_element?(view, ~s([id$="-image-media"][data-processing-image="true"]))
        assert count(view, c.image, "true") == 3
      end

      {:ok, _job} = Processing.queue_processing(c.image, c.me)

      for view <- [a, b] do
        await(fn -> count(view, c.image, "true") == 0 end)
        assert has_element?(view, ~s(#block-#{c.ref_uid}-upload[data-processing-image="false"] img))
        assert has_element?(view, ~s([id$="-image-media"][data-processing-image="false"]))
        assert count(view, c.image, "false") == 3
      end
    end
  end

  defp unprocessed_image(user) do
    Factory.insert(:image,
      creator: user,
      path: @original,
      status: :unprocessed,
      focal: %Brando.Images.Focal{x: 50, y: 50}
    )
  end

  defp processing?(view, image), do: count(view, image, "true") > 0
  defp processed?(view, image), do: count(view, image, "true") == 0 and count(view, image, "false") > 0

  # Media fields showing `image`, processing or not.
  defp count(view, image, processing) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s([data-asset-id="#{image.id}"][data-processing-image="#{processing}"]))
    |> length()
  end

  defp topic_subscribers(image),
    do: Registry.lookup(Brando.pubsub(), Brando.Assets.ProcessingStatus.topic(:image, image.id)) |> Enum.map(&elem(&1, 0))

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp page_with_picture_and_image_var(user, image) do
    module =
      ProposalFixtures.module!(user, "Photo", ~s(<div>{% ref refs.cover %}{{ photo }}</div>),
        refs: [ProposalFixtures.ref("cover", %{type: "picture", data: %{}})],
        vars: [%{type: "image", key: "photo", label: "Photo"}]
      )

    page = Factory.insert(:page, creator: user, title: "Photos", uri: "photos")
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
              "name" => "cover",
              "sequence" => 0,
              "data" => %{"type" => "picture", "data" => %{}},
              "image_id" => image.id
            }
          ],
          "vars" => [
            %{"type" => "image", "key" => "photo", "label" => "Photo", "sequence" => 0, "image_id" => image.id}
          ]
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    %{page: page, ref_uid: ref_uid}
  end
end
