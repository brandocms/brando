defmodule Brando.Uploads.DirectFinalizeTest do
  @moduledoc """
  The test D1 could not write.

  Phase 2 shipped the pending-intent machinery that lets a `direct_complete`
  arriving after the sticky UploadManager remounted still reach
  `Brando.Uploads.finalize_direct/3`, and said so honestly in the plan: *"no test
  drives a **successful** finalize, because there is no S3 mock boundary in the
  repo"*. `Brando.CDN.Client` is that boundary, and this is the coverage it was
  for — everything past the `HEAD` is real code creating a real row.

  What this pins that nothing else could: the server trusts **only** its own
  key and resolved target plus what the bucket reports, never the numbers the
  client sent. A browser that claims a 4-byte PDF while the object is 12MB, or
  claims `application/pdf` over a `text/html` object, must be rejected — that is
  the whole reason `finalize_direct/3` does a `HEAD` at all instead of believing
  `direct_complete`.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Mox

  alias Brando.CDN.Client
  alias Brando.Factory
  alias Brando.Uploads

  @s3_config %Brando.CDN.S3Config{
    access_key_id: "TESTKEY",
    secret_access_key: "TESTSECRET",
    scheme: "https://",
    host: "ams3.digitaloceanspaces.com",
    region: "ams3"
  }

  @key "files/direct/report.pdf"

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:brando, Brando.Files)

    Application.put_env(:brando, Brando.Files,
      cdn: [enabled: true],
      default_config: %{
        upload_path: Path.join(["files", "direct"]),
        allowed_mimetypes: ["application/pdf"],
        random_filename: false,
        cdn: %{
          enabled: true,
          direct: true,
          bucket: "testbucket",
          media_url: "https://testbucket.ams3.digitaloceanspaces.com",
          s3: @s3_config
        }
      }
    )

    on_exit(fn -> Application.put_env(:brando, Brando.Files, original) end)

    {:ok, user: Factory.insert(:random_user)}
  end

  defp head_response(size, mime_type) do
    %{
      status_code: 200,
      headers: [{"content-length", to_string(size)}, {"content-type", mime_type}]
    }
  end

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        key: @key,
        resolved_target: "default",
        title: "report.pdf",
        mime_type: "application/pdf",
        filesize: 1234
      },
      overrides
    )
  end

  test "a completed direct upload becomes a real File row", ctx do
    expect(Client.Mock, :head_object, fn bucket, key, s3_config ->
      # The bucket and key come from the server's own resolved config and the
      # intent, never from the completion message.
      assert bucket == "testbucket"
      assert key == @key
      assert s3_config[:access_key_id] == "TESTKEY"
      {:ok, head_response(1234, "application/pdf")}
    end)

    assert {:ok, file} = Uploads.finalize_direct(:file, params(), ctx.user)

    assert file.id
    assert file.filename == "report.pdf"
    assert file.filesize == 1234
    assert file.mime_type == "application/pdf"
    # `cdn: true` is what tells every URL helper to serve this from the bucket
    # rather than from local media — a direct upload never touched the server's
    # disk, so getting this wrong yields a 404 for a file that uploaded fine.
    assert file.cdn == true
    assert Brando.Repo.get(Brando.Files.File, file.id)
  end

  test "a size the bucket disagrees with is rejected", ctx do
    expect(Client.Mock, :head_object, fn _, _, _ ->
      {:ok, head_response(12_000_000, "application/pdf")}
    end)

    assert {:error, message} = Uploads.finalize_direct(:file, params(), ctx.user)
    assert message =~ "size"
    assert Brando.Repo.all(Brando.Files.File) == []
  end

  test "a mime type the bucket disagrees with is rejected", ctx do
    expect(Client.Mock, :head_object, fn _, _, _ ->
      {:ok, head_response(1234, "text/html")}
    end)

    assert {:error, message} = Uploads.finalize_direct(:file, params(), ctx.user)
    assert message =~ "type"
    assert Brando.Repo.all(Brando.Files.File) == []
  end

  # The transfer failed, or the browser lied about finishing. Either way there is
  # nothing to make a row out of, and the message has to name the key so an
  # operator can find the gap between the intent and the bucket.
  test "a key that is not in the bucket is rejected", ctx do
    expect(Client.Mock, :head_object, fn _, _, _ -> {:error, :not_found} end)

    assert {:error, message} = Uploads.finalize_direct(:file, params(), ctx.user)
    assert message =~ @key
    assert Brando.Repo.all(Brando.Files.File) == []
  end
end
