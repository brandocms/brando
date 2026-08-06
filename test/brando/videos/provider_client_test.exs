defmodule Brando.Videos.ProviderClientTest do
  @moduledoc """
  Coverage for the Mux/Bunny/Cloudflare clients, stubbed at the transport.

  Phase 4 asked for "a behaviour + Mox boundary for the S3/Mux/Bunny clients".
  These three got a transport stub instead of a behaviour, deliberately:

    * they all speak HTTP through `Req`, which ships `Req.Test` for exactly this
      — a behaviour would be a second seam over one the library already gives us;
    * a behaviour mock can only assert *that* a client was called. The bugs these
      clients actually have are in **the request they build** — Mux's auth
      header, Bunny's library path, whether credentials are checked before or
      after the raise. Stubbing the transport is the only thing that can see
      that, and it is what these tests assert.

  The S3 seam is a behaviour for the opposite reason — see `Brando.CDN.Client`.

  Phase 2's D3 found that `Mux.api_request/3` **raises** on missing credentials
  rather than returning an error, which took the whole entry form process down
  with every unsaved change in it. That rescue is covered here from the client
  side, so it stays true if the client is refactored.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux

  defp with_config(module, config) do
    original = Application.fetch_env(:brando, module)
    Application.put_env(:brando, module, config)

    # Restoring "there was no config" means *deleting* the key, not storing
    # `nil` — the clients read `Application.get_env(:brando, __MODULE__, [])`,
    # and a stored `nil` beats that default, so `Keyword.get(nil, …)` raises a
    # FunctionClauseError instead of the credentials error the next test
    # expects. Cost one cross-file flake to find.
    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:brando, module, value)
        :error -> Application.delete_env(:brando, module)
      end
    end)
  end

  # `Req.Test.stub/2` is bound to the test process, and `plug:` routes the
  # request to it instead of over the network.
  defp stub_transport(module, config, fun) do
    stub_name = module
    Req.Test.stub(stub_name, fun)
    with_config(module, Keyword.put(config, :req_options, plug: {Req.Test, stub_name}))
  end

  describe "Mux" do
    test "initiating an upload sends basic auth and the asset settings, and stores the upload id" do
      stub_transport(
        Mux,
        [access_token_id: "id", access_token_secret: "secret"],
        fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/video/v1/uploads"

          assert ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
          assert Base.decode64!(encoded) == "id:secret"

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          decoded = Jason.decode!(body)
          assert decoded["cors_origin"] == "*"
          assert decoded["new_asset_settings"]["playback_policies"] == ["public"]

          Req.Test.json(conn, %{
            "data" => %{
              "id" => "upload-123",
              "url" => "https://storage.mux.com/upload-123",
              "timeout" => 3600
            }
          })
        end
      )

      user = Factory.insert(:random_user)

      assert {:ok, %{upload_url: url, video: video}} = Mux.initiate_upload("clip.mp4", user)

      assert url == "https://storage.mux.com/upload-123"
      # Mux keys the row on the *upload* id until a webhook swaps in the asset
      # id, so it lives in `meta`, not in `remote_id`.
      assert video.meta["mux"]["upload_id"] == "upload-123"
      # The row exists before a single byte moves, which is why
      # `VideoUploadReaper` has to exist — see `research/03-uploads.md:127`.
      assert video.status == :uploading
      assert Brando.Repo.get(Brando.Videos.Video, video.id)
    end

    # D3's finding, from the client side. The raise is real and deliberate
    # (a misconfigured site should be loud), so what has to hold is that it is a
    # raise and not a silent success — the *rescue* lives at the call site in
    # `form.ex`, and this pins the thing that rescue is for.
    test "raises rather than returning an error when credentials are missing" do
      with_config(Mux, [])

      assert_raise RuntimeError, ~r/Mux credentials not configured/, fn ->
        Mux.initiate_upload("clip.mp4", Factory.insert(:random_user))
      end
    end

    # A non-2xx is an ordinary error return, not a raise — the distinction is
    # exactly what D3 was about.
    test "an API rejection comes back as an error tuple" do
      stub_transport(
        Mux,
        [access_token_id: "id", access_token_secret: "secret"],
        fn conn ->
          conn
          |> Plug.Conn.put_status(422)
          |> Req.Test.json(%{"error" => %{"messages" => ["bad settings"]}})
        end
      )

      assert {:error, _} = Mux.initiate_upload("clip.mp4", Factory.insert(:random_user))
      assert Brando.Repo.all(Brando.Videos.Video) == []
    end
  end

  describe "Bunny" do
    test "initiating an upload targets the configured library and authenticates with AccessKey" do
      stub_transport(
        Bunny,
        [api_key: "bunny-key", library_id: "4242", cdn_hostname: "vz-test.b-cdn.net"],
        fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/library/4242/videos"
          assert Plug.Conn.get_req_header(conn, "accesskey") == ["bunny-key"]

          {:ok, body, conn} = Plug.Conn.read_body(conn)
          # Both providers humanize the filename before sending it as a title.
          assert Jason.decode!(body)["title"] == "Clip"

          Req.Test.json(conn, %{"guid" => "guid-123"})
        end
      )

      user = Factory.insert(:random_user)

      assert {:ok, %{video: video}} = Bunny.initiate_upload("clip.mp4", user)
      # Same shape as Mux: the provider's own id lives in `meta`, keyed by
      # provider, and `remote_id` is only set later.
      assert video.meta["bunny"]["video_guid"] == "guid-123"
      assert video.status == :uploading
    end

    test "raises rather than returning an error when credentials are missing" do
      with_config(Bunny, [])

      assert_raise RuntimeError, ~r/Bunny credentials not configured/, fn ->
        Bunny.initiate_upload("clip.mp4", Factory.insert(:random_user))
      end
    end

    # Req strips credentials across a redirect by deleting the `authorization`
    # header and the `:auth` option, and nothing else
    # (`remove_credentials_if_untrusted/3`, `req/steps.ex:1573-1582`). Bunny
    # authenticates with an `AccessKey` header, so it is covered by neither —
    # which made a 302 to any other host forward the library API key, on stock
    # defaults with no config involved. `redirect: false` in the built options
    # is the fix, and it is config-proof because built options outrank
    # configured ones.
    #
    # RED: remove `redirect: false` from `api_request/3` and the counter reaches
    # 2 with `accesskey` present on the second request. That mutation is the
    # defect itself, which is the strongest form this assertion can take.
    test "a redirect to another host does not forward the AccessKey credential" do
      test_pid = self()

      Req.Test.stub(Bunny, fn conn ->
        send(test_pid, {:request, conn.host, Plug.Conn.get_req_header(conn, "accesskey")})

        conn
        |> Plug.Conn.put_resp_header("location", "https://evil.example.com/library/4242/videos")
        |> Plug.Conn.send_resp(302, "")
      end)

      with_config(Bunny,
        api_key: "bunny-key",
        library_id: "4242",
        cdn_hostname: "vz-test.b-cdn.net",
        req_options: [plug: {Req.Test, Bunny}]
      )

      # The 302 is surfaced as an error rather than chased, so the upload fails
      # loudly instead of leaking quietly. Captured because that error path
      # logs, and the unit suite's stdout is a tracked baseline in this audit —
      # a test that adds a line to it every run makes the next phase's number
      # unreproducible.
      assert capture_log(fn ->
               assert {:error, _} =
                        Bunny.initiate_upload("clip.mp4", Factory.insert(:random_user))
             end) =~ "302"

      assert_received {:request, "video.bunnycdn.com", ["bunny-key"]}
      refute_received {:request, "evil.example.com", _}
    end
  end

  # All three providers put their configured `:req_options` *underneath* the
  # request they built, and that one line was byte-identical in all three — so
  # it is the line that could drift in one of them unnoticed. It now has a
  # single owner (`Brando.Videos.Uploaders.ReqOptions`), and this is what makes
  # the direction of that merge falsifiable.
  #
  # Nothing above can see it: the stub is installed through `:req_options`
  # (`plug:`), which does not collide with any key the providers build, so the
  # merge produces the same keyword list either way round. The collision has to
  # be deliberate, and the header is the one worth testing — the comment on the
  # rule says a config seam that can unset credentials is a config seam that
  # will.
  describe "req_options precedence" do
    test "a :req_options entry cannot replace the auth header the provider built" do
      Req.Test.stub(Mux, fn conn ->
        assert ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
        assert Base.decode64!(encoded) == "id:secret"

        Req.Test.json(conn, %{
          "data" => %{"id" => "upload-123", "url" => "https://storage.mux.com/x", "timeout" => 1}
        })
      end)

      with_config(Mux,
        access_token_id: "id",
        access_token_secret: "secret",
        req_options: [
          plug: {Req.Test, Mux},
          headers: [{"authorization", "Basic #{Base.encode64("hijacked:hijacked")}"}]
        ]
      )

      assert {:ok, _} = Mux.initiate_upload("clip.mp4", Factory.insert(:random_user))
    end

    # One owner, three call sites. The Mux test above covers the rule; these
    # two cover that Bunny and Cloudflare still *call* it — a re-inlined merge
    # in either would be invisible to everything else in this file, for the
    # same reason the Mux test had to be written in the first place.
    test "a :req_options entry cannot replace the AccessKey header Bunny built" do
      Req.Test.stub(Bunny, fn conn ->
        assert Plug.Conn.get_req_header(conn, "accesskey") == ["bunny-key"]

        Req.Test.json(conn, %{"guid" => "guid-123"})
      end)

      with_config(Bunny,
        api_key: "bunny-key",
        library_id: "4242",
        cdn_hostname: "vz-test.b-cdn.net",
        req_options: [
          plug: {Req.Test, Bunny},
          headers: [{"AccessKey", "hijacked"}]
        ]
      )

      assert {:ok, _} = Bunny.initiate_upload("clip.mp4", Factory.insert(:random_user))
    end

    test "a :req_options entry cannot replace the Bearer header Cloudflare built" do
      Req.Test.stub(Cloudflare, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer api-token"]

        conn
        |> Plug.Conn.put_resp_header("location", "https://upload.videodelivery.net/tus/cf-uid")
        |> Plug.Conn.put_resp_header("stream-media-id", "cf-uid")
        |> Plug.Conn.send_resp(201, "")
      end)

      with_config(Cloudflare,
        account_id: "account-id",
        api_token: "api-token",
        req_options: [
          plug: {Req.Test, Cloudflare},
          headers: [{"authorization", "Bearer hijacked"}]
        ]
      )

      assert {:ok, _} =
               Cloudflare.initiate_upload("clip.mp4", Factory.insert(:random_user),
                 file_meta: %{name: "clip.mp4", size: 12_345, type: "video/mp4"}
               )
    end
  end
end
