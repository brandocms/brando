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
