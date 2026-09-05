defmodule Brando.Files.ReplacementTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Mox

  alias Brando.Files
  alias Brando.Files.Replacement

  setup :verify_on_exit!

  setup do
    root = Path.join(System.tmp_dir!(), "brando-replacement-#{Ecto.UUID.generate()}")
    put_test_env(:media_path, root)

    put_test_env(Files,
      default_config: %{upload_path: "files/replacement", allowed_mimetypes: ["application/pdf"], size_limit: 100}
    )

    File.mkdir_p!(Path.join(root, "files/replacement"))
    on_exit(fn -> File.rm_rf!(root) end)
    user = Brando.Factory.insert(:random_user)

    folder =
      Brando.Repo.insert!(struct(Brando.Media.Folder, scope: "files/replacement", name: "Reports", path: "Reports"))

    {:ok, file} =
      Files.create_file(
        %{
          filename: "report.pdf",
          title: "Annual report",
          filesize: 8,
          mime_type: "application/pdf",
          config_target: "default",
          folder_id: folder.id
        },
        user
      )

    original = Path.join(root, "files/replacement/report.pdf")
    File.write!(original, "original")
    source = Path.join(root, "replacement.pdf")
    File.write!(source, "replacement contents")
    entry = %{client_name: "revised-report.pdf", client_type: "application/pdf", client_size: 1}
    {:ok, asset: file, user: user, original: original, source: source, entry: entry}
  end

  test "replaces bytes without changing the URL, row, metadata or references", ctx do
    var = Brando.Repo.insert!(struct(Brando.Content.Var, key: "download", type: :file, file_id: ctx.asset.id))
    url = Brando.Utils.media_url(ctx.asset)
    count = Brando.Repo.aggregate(Brando.Files.File, :count)
    cached_query = %{matches: %{id: ctx.asset.id}, cache: {:ttl, :infinite}}
    assert {:ok, %{filesize: 8}} = Files.get_file(cached_query)

    assert {:ok, updated} = Replacement.store(ctx.asset.id, %{path: ctx.source}, ctx.entry, ctx.user)
    assert File.read!(ctx.original) == "replacement contents"
    assert updated.id == ctx.asset.id
    assert updated.title == "Annual report"
    assert updated.creator_id == ctx.asset.creator_id
    assert updated.folder_id == ctx.asset.folder_id
    assert updated.config_target == "default"
    assert updated.filesize == byte_size("replacement contents")
    assert {:ok, %{filesize: 20}} = Files.get_file(cached_query)
    assert Brando.Utils.media_url(updated) == url
    assert Brando.Repo.get!(Brando.Content.Var, var.id).file_id == ctx.asset.id
    assert Brando.Repo.aggregate(Brando.Files.File, :count) == count
    assert Path.wildcard(ctx.original <> ".replacement-*") == []
  end

  test "rejects wrong extensions, MIME types and oversized uploads before transfer", ctx do
    meta = %{name: "revised.pdf", size: 20, type: "application/pdf"}
    assert {:ok, :server} = Replacement.initiate(ctx.asset.id, meta)

    assert {:error, "Choose a file with the same extension" <> _} =
             Replacement.initiate(ctx.asset.id, %{meta | name: "report.txt"})

    assert {:error, "Rejected file type" <> _} = Replacement.initiate(ctx.asset.id, %{meta | type: "text/plain"})
    assert {:error, "File is too large" <> _} = Replacement.initiate(ctx.asset.id, %{meta | size: 101})
    assert File.read!(ctx.original) == "original"
  end

  test "checks the actual transferred size and preserves the original on rejection", ctx do
    File.write!(ctx.source, String.duplicate("x", 101))
    assert {:error, "File is too large" <> _} = Replacement.store(ctx.asset.id, %{path: ctx.source}, ctx.entry, ctx.user)
    assert File.read!(ctx.original) == "original"
    assert Files.get_file!(ctx.asset.id).filesize == 8
  end

  test "missing configuration is reported before transfer", ctx do
    {:ok, _} = Files.update_file(ctx.asset, %{config_target: "removed-config"}, ctx.user)

    assert {:error, "The file's upload configuration is unavailable"} =
             Replacement.initiate(ctx.asset.id, %{name: "revised.pdf", size: 20, type: "application/pdf"})

    assert File.read!(ctx.original) == "original"
  end

  test "missing and deleted files cannot be replaced", ctx do
    assert {:ok, _} = Files.delete_file(ctx.asset.id, ctx.user)
    assert {:error, _} = Replacement.initiate(ctx.asset.id, %{name: "revised.pdf", size: 20, type: "application/pdf"})
    assert {:error, _} = Replacement.store(ctx.asset.id, %{path: ctx.source}, ctx.entry, ctx.user)
    assert {:error, _} = Replacement.store(-1, %{path: ctx.source}, ctx.entry, ctx.user)
    assert File.read!(ctx.original) == "original"
  end

  test "a storage failure rolls back metadata", ctx do
    File.rm!(ctx.original)
    File.mkdir!(ctx.original)
    File.write!(Path.join(ctx.original, "sentinel"), "untouched")
    assert {:error, _} = Replacement.store(ctx.asset.id, %{path: ctx.source}, ctx.entry, ctx.user)
    assert Files.get_file!(ctx.asset.id).filesize == 8
    assert File.read!(Path.join(ctx.original, "sentinel")) == "untouched"
    assert Path.wildcard(ctx.original <> ".replacement-*") == []
  end

  test "the manager rejects multiple replacements and validates the persisted file's config", ctx do
    socket =
      Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, current_user: ctx.user, items: %{}, order: [], open?: false)

    target = %{
      "kind" => "file_replace",
      "asset_type" => "file",
      "file_id" => ctx.asset.id,
      "config_target" => "default",
      "deliver_topic" => "form:#{Ecto.UUID.generate()}"
    }

    upload = %{"index" => 0, "name" => "revised.pdf", "size" => 101, "type" => "application/pdf"}

    assert {:reply, %{decisions: [%{error: "File is too large" <> _}]}, _} =
             BrandoAdmin.UploadManager.handle_event("intake", %{"files" => [upload], "target" => target}, socket)

    upload = %{upload | "size" => 20}

    assert {:reply, %{decisions: [%{transport: "server"}]}, _} =
             BrandoAdmin.UploadManager.handle_event("intake", %{"files" => [upload], "target" => target}, socket)

    assert {:reply, %{decisions: decisions}, _} =
             BrandoAdmin.UploadManager.handle_event("intake", %{"files" => [upload, upload], "target" => target}, socket)

    assert Enum.all?(decisions, &(&1.error == "Choose one replacement file at a time"))
    assert File.read!(ctx.original) == "original"
  end

  describe "CDN files" do
    setup ctx do
      put_test_env(:cdn_client, Brando.CDN.Client.Mock)

      put_test_env(Files,
        default_config: %{
          upload_path: "files/replacement",
          allowed_mimetypes: ["application/pdf"],
          content_disposition: :attachment,
          cdn: %Brando.CDN.Config{
            enabled: true,
            direct: true,
            bucket: "replacement-bucket",
            media_url: "https://files.example.com",
            keep_local_copy: true,
            s3: %Brando.CDN.S3Config{access_key_id: "TESTKEY", secret_access_key: "TESTSECRET"}
          }
        }
      )

      {:ok, file} = Files.update_file(ctx.asset, %{cdn: true}, ctx.user)
      {:ok, asset: file}
    end

    test "uploads to the existing bucket key and keeps the CDN URL", ctx do
      url = Brando.Utils.media_url(ctx.asset)

      expect(Brando.CDN.Client.Mock, :replace_file, fn bucket, key, path, opts, _cfg ->
        assert bucket == "replacement-bucket"
        assert key == "media/files/replacement/report.pdf"
        assert File.read!(path) == "replacement contents"
        assert opts[:content_type] == "application/pdf"
        assert opts[:content_disposition] == ~s(attachment; filename="report.pdf")
        {:ok, %{status_code: 200}}
      end)

      assert {:ok, updated} = Replacement.store(ctx.asset.id, %{path: ctx.source}, ctx.entry, ctx.user)
      assert updated.cdn
      assert Brando.Utils.media_url(updated) == url
      assert File.read!(ctx.original) == "replacement contents"
    end

    test "a CDN failure keeps the previous record and local copy", ctx do
      expect(Brando.CDN.Client.Mock, :replace_file, fn _, _, _, _, _ -> {:error, :unavailable} end)

      assert {:error, "Could not replace the file on the CDN"} =
               Replacement.store(ctx.asset.id, %{path: ctx.source}, ctx.entry, ctx.user)

      assert File.read!(ctx.original) == "original"
      assert Files.get_file!(ctx.asset.id).filesize == 8
      assert Files.get_file!(ctx.asset.id).cdn
    end
  end
end
