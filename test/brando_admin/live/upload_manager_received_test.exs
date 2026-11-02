defmodule BrandoAdmin.UploadManagerReceivedTest do
  @moduledoc """
  The manager judges the entry that arrived, not the event that announced it:
  a crafted client can declare one file at intake and send another.
  """
  use Brando.LiveCase

  alias Brando.Tenant.Storage

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)
  @queue_form "form#brando-upload-manager-queue-form"
  @upload_path "upload_manager_received"

  setup %{current_user: user} do
    original = Application.get_env(:brando, Brando.Images, [])

    put_test_env(
      Brando.Images,
      Keyword.put(original, :default_config, %{
        upload_path: @upload_path,
        allowed_mimetypes: ["image/jpeg", "image/svg+xml"],
        random_filename: false,
        size_limit: 1_000_000,
        sizes: %{"thumb" => %{"size" => "150x150", "quality" => 70, "crop" => true}}
      })
    )

    dir = Path.join(Storage.current_media_root(), @upload_path)
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, page: Factory.insert(:page, creator: user), dir: dir}
  end

  test "declared small, arrived over the limit: refused, and nothing is written", %{conn: conn, page: page, dir: dir} do
    manager = mount_manager(conn, page)
    ref = intake(manager, "small.jpg", 1_000, "image/jpeg")

    transfer(manager, ref, "small.jpg", File.read!(@fixture) <> :binary.copy(<<0>>, 1_100_000), "image/jpeg")

    assert %{status: :error, error: error} = items(manager)[ref]
    assert is_binary(error)
    assert stored(dir) == []
    assert entries(manager) == []
  end

  test "declared one name, arrived as another: refused, and nothing is written", %{conn: conn, page: page, dir: dir} do
    manager = mount_manager(conn, page)
    ref = intake(manager, "photo.jpg", 1_000, "image/jpeg")

    transfer(manager, ref, "orphan.html", "<html></html>", "image/jpeg")

    assert %{status: :error} = items(manager)[ref]
    assert stored(dir) == []
  end

  test "declared one type, arrived as another: refused, and nothing is written", %{conn: conn, page: page, dir: dir} do
    manager = mount_manager(conn, page)
    ref = intake(manager, "photo.jpg", 1_000, "image/jpeg")

    transfer(manager, ref, "photo.jpg", File.read!(@fixture), "image/svg+xml")

    assert %{status: :error} = items(manager)[ref]
    assert stored(dir) == []
  end

  test "an item refused at intake takes no bytes", %{conn: conn, page: page, dir: dir} do
    manager = mount_manager(conn, page)
    ref = intake(manager, "photo.jpg", 2_000_000, "image/jpeg")
    assert %{status: :error} = items(manager)[ref]

    transfer(manager, ref, "photo.jpg", File.read!(@fixture), "image/jpeg")

    assert %{status: :error} = items(manager)[ref]
    assert stored(dir) == []
  end

  test "a second transfer under a finished ref stores nothing more", %{conn: conn, page: page, dir: dir} do
    manager = mount_manager(conn, page)
    body = File.read!(@fixture)
    ref = intake(manager, "photo.jpg", byte_size(body), "image/jpeg")

    transfer(manager, ref, "photo.jpg", body, "image/jpeg")
    assert %{status: status} = items(manager)[ref]
    assert status in [:processing, :done]
    assert [_] = stored(dir)

    transfer(manager, ref, "photo.jpg", body, "image/jpeg")
    assert [_] = stored(dir)
  end

  describe "progress events" do
    test "a progress event does not reopen a finished server upload", %{conn: conn, page: page, dir: dir} do
      manager = mount_manager(conn, page)
      body = File.read!(@fixture)
      ref = intake(manager, "photo.jpg", byte_size(body), "image/jpeg")

      transfer(manager, ref, "photo.jpg", body, "image/jpeg")
      assert %{status: finished} = items(manager)[ref]
      assert finished in [:processing, :done]

      for event <- ["direct_progress", "external_progress"] do
        render_hook(manager, event, %{"ref" => ref, "progress" => 10})
        assert %{status: ^finished, progress: 100} = items(manager)[ref]
      end

      images = Repo.aggregate(Brando.Images.Image, :count)
      Phoenix.PubSub.subscribe(Brando.pubsub(), items(manager)[ref].target["deliver_topic"])

      transfer(manager, ref, "photo.jpg", body, "image/jpeg")

      assert [_] = stored(dir)
      assert Repo.aggregate(Brando.Images.Image, :count) == images
      refute_receive {:asset_ready, _target, _asset}, 100
    end

    test "a progress event does not move a queued server upload", %{conn: conn, page: page} do
      manager = mount_manager(conn, page)
      ref = intake(manager, "photo.jpg", 1_000, "image/jpeg")

      render_hook(manager, "direct_progress", %{"ref" => ref, "progress" => 10})
      render_hook(manager, "external_progress", %{"ref" => ref, "progress" => 10})

      assert %{status: :queued, progress: 0} = items(manager)[ref]
    end

    test "a provider's progress reaches its item, until it finishes", %{conn: conn, page: page} do
      manager = mount_manager(conn, page)
      ref = Ecto.UUID.generate()
      render_hook(manager, "external_track", %{"ref" => ref, "filename" => "clip.mp4", "size" => 10})

      render_hook(manager, "external_progress", %{"ref" => ref, "progress" => 40})
      assert %{status: :uploading, progress: 40} = items(manager)[ref]

      render_hook(manager, "direct_progress", %{"ref" => ref, "progress" => 60})
      assert %{status: :uploading, progress: 40} = items(manager)[ref]

      render_hook(manager, "external_complete", %{"ref" => ref})
      render_hook(manager, "external_progress", %{"ref" => ref, "progress" => 50})
      assert %{status: :done, progress: 100} = items(manager)[ref]
    end

    test "a direct transfer's progress reaches its item, until it fails", %{conn: conn, page: page} do
      original = Application.get_env(:brando, Brando.Images, [])

      put_test_env(
        Brando.Images,
        Keyword.put(original, :default_config, %{
          upload_path: @upload_path,
          allowed_mimetypes: ["image/jpeg"],
          random_filename: false,
          size_limit: 1_000_000,
          sizes: %{"thumb" => %{"size" => "150x150", "quality" => 70, "crop" => true}},
          cdn: %{
            enabled: true,
            direct: true,
            bucket: "testbucket",
            media_url: "https://testbucket.ams3.digitaloceanspaces.com",
            s3: %Brando.CDN.S3Config{
              access_key_id: "TESTKEY",
              secret_access_key: "TESTSECRET",
              scheme: "https://",
              host: "ams3.digitaloceanspaces.com",
              region: "ams3"
            },
            keep_local_copy: false
          }
        })
      )

      manager = mount_manager(conn, page)
      ref = intake(manager, "photo.jpg", 1_000, "image/jpeg")
      assert %{transport: :direct, status: :queued} = items(manager)[ref]

      render_hook(manager, "direct_progress", %{"ref" => ref, "progress" => 40})
      assert %{status: :uploading, progress: 40} = items(manager)[ref]

      render_hook(manager, "external_progress", %{"ref" => ref, "progress" => 60})
      assert %{status: :uploading, progress: 40} = items(manager)[ref]

      render_hook(manager, "direct_error", %{"ref" => ref, "message" => "failed"})
      render_hook(manager, "direct_progress", %{"ref" => ref, "progress" => 50})
      assert %{status: :error, progress: 40} = items(manager)[ref]
    end
  end

  # The image editor's "save as new copy" is the one upload the form owns
  describe "image editor copy" do
    # The size is the editor's own export, which can pass the limit its source met
    test "over the config's limit still saves", %{conn: conn, page: page, dir: dir} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      body = File.read!(@fixture) <> :binary.copy(<<0>>, 1_100_000)
      image = Factory.insert(:image)

      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
        id: "page_form",
        action: :update_edit_image,
        edit_image: %{id: image.id, path: [], field: :meta_image, relation_field: nil, image: image}
      )

      view
      |> with_target(cid_of(view, "#page_form-el"))
      |> render_hook("image_editor_save", %{"mode" => "new_copy", "focal_x" => 40, "focal_y" => 60})

      view
      |> file_input("#page_form_form", :image_editor_upload, [%{name: "copy.jpg", content: body, type: "image/jpeg"}])
      |> render_upload("copy.jpg")

      assert stored(dir) == ["copy.jpg"]
    end

    test "a name outside the image list: refused, and the editor is told", %{conn: conn, page: page, dir: dir} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      images = Repo.aggregate(Brando.Images.Image, :count)
      body = File.read!(@fixture)

      view
      |> file_input("#page_form_form", :image_editor_upload, [%{name: "copy.html", content: body, type: "image/jpeg"}])
      |> render_upload("copy.html")

      assert_push_event(view, "b:alert", %{type: "error", message: "Unsupported image type" <> _}, 2_000)
      assert Repo.aggregate(Brando.Images.Image, :count) == images
      assert stored(dir) == []
    end

    test "a type the config does not allow: refused, and the editor is told", %{conn: conn, page: page, dir: dir} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      images = Repo.aggregate(Brando.Images.Image, :count)
      body = File.read!(Path.expand("../../fixtures/sample.png", __DIR__))

      view
      |> file_input("#page_form_form", :image_editor_upload, [%{name: "copy.png", content: body, type: "image/png"}])
      |> render_upload("copy.png")

      assert_push_event(view, "b:alert", %{type: "error", message: message}, 2_000)
      assert message =~ "image/png"
      assert Repo.aggregate(Brando.Images.Image, :count) == images
      assert stored(dir) == []
    end
  end

  test "an honest upload still lands, with the real size", %{conn: conn, page: page, dir: dir} do
    manager = mount_manager(conn, page)
    body = File.read!(@fixture)
    ref = intake(manager, "photo.jpg", byte_size(body), "image/jpeg")

    transfer(manager, ref, "photo.jpg", body, "image/jpeg")

    assert %{status: status, error: nil} = items(manager)[ref]
    assert status in [:processing, :done]
    assert stored(dir) == ["photo.jpg"]
  end

  defp mount_manager(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    find_live_child(view, "brando-upload-manager-lv")
  end

  defp intake(manager, filename, size, type) do
    before = manager |> items() |> Map.keys() |> MapSet.new()

    render_hook(manager, "intake", %{
      "files" => [%{"index" => 0, "name" => filename, "size" => size, "type" => type}],
      "target" => %{
        "kind" => "entry_field",
        "field" => "meta_image",
        "asset_type" => "image",
        "config_target" => "default",
        "deliver_topic" => "form:#{Ecto.UUID.generate()}"
      }
    })

    [ref] = manager |> items() |> Map.keys() |> Enum.reject(&MapSet.member?(before, &1))
    ref
  end

  defp transfer(manager, ref, name, content, type) do
    tagged = "#{ref}::#{name}"
    upload = file_input(manager, @queue_form, :queue, [%{name: tagged, content: content, type: type}])
    render_upload(upload, tagged)
  end

  defp stored(dir) do
    case File.ls(dir) do
      {:ok, files} -> Enum.reject(files, &File.dir?(Path.join(dir, &1)))
      _ -> []
    end
  end

  defp items(manager), do: :sys.get_state(manager.pid).socket.assigns.items
  defp entries(manager), do: :sys.get_state(manager.pid).socket.assigns.uploads.queue.entries
end
