defmodule Brando.MCP.MediaTest do
  # The media tools over the MCP endpoint: an image uploaded to a one-time
  # URL and finished into the library, or imported from an address through
  # the URL guard (from a local server), with its focal point and texts.
  # And what a leaked URL, another connection, an oversized, mislabelled or
  # slow body, or a private or redirecting address can do: nothing.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Images.Image
  alias Brando.MCP
  alias Brando.MCP.Uploads
  alias Brando.Media.Folder
  alias Brando.WebhookReceiver
  alias BrandoAdmin.Images.FolderBrowser

  # A server's connection as Bandit's behaves: each read is told to the test,
  # and the read after `Process.get(:raise_on_read)` reads raises, as
  # Bandit's read raises when the client goes away or stops sending
  defmodule DroppingAdapter do
    @moduledoc false
    @behaviour Plug.Conn.Adapter
    alias Plug.Adapters.Test.Conn, as: Test

    @impl true
    def read_req_body(payload, opts) do
      send(self(), {:read_body, opts})
      reads = Process.get(:reads, 0)
      Process.put(:reads, reads + 1)

      if reads >= Process.get(:raise_on_read, 0),
        do: raise("closed"),
        else: Test.read_req_body(payload, opts)
    end

    @impl true
    defdelegate send_resp(payload, status, headers, body), to: Test
    @impl true
    defdelegate send_file(payload, status, headers, path, offset, length), to: Test
    @impl true
    defdelegate send_chunked(payload, status, headers), to: Test
    @impl true
    defdelegate chunk(payload, body), to: Test
    @impl true
    defdelegate push(payload, path, headers), to: Test
    @impl true
    defdelegate inform(payload, status, headers), to: Test
    @impl true
    defdelegate upgrade(payload, protocol, opts), to: Test
    @impl true
    defdelegate get_peer_data(payload), to: Test
    @impl true
    defdelegate get_sock_data(payload), to: Test
    @impl true
    defdelegate get_ssl_data(payload), to: Test
    @impl true
    defdelegate get_http_protocol(payload), to: Test
  end

  @jpg File.read!(Path.expand("../../fixtures/sample.jpg", __DIR__))
  @png File.read!(Path.expand("../../fixtures/sample.png", __DIR__))
  @limit 10_240_000

  setup %{conn: conn, current_user: user} do
    setup_fetcher()
    dir = Path.join(System.tmp_dir!(), "brando-mcp-uploads-test-#{System.unique_integer([:positive])}")
    mcp_env(upload_dir: dir)
    on_exit(fn -> File.rm_rf(dir) end)

    enable_two_factor(user)
    tenant = MCP.tenant(nil, nil) |> switch!()
    tokens = connect!(conn, tenant)

    put_test_env(Brando.Webhooks, allow_localhost: true, resolver: {Brando.WebhookTestResolver, :resolve})

    root = Brando.Tenant.Storage.current_media_root()
    upload_root = FolderBrowser.upload_root(nil)

    on_exit(fn ->
      for folder <- ~w(uploads products) do
        File.rm_rf(Path.join(root, FolderBrowser.absolute_folder(folder, upload_root)))
      end
    end)

    %{tenant: tenant, token: tokens["access_token"], user: user, dir: dir, grant: Brando.Repo.one!(MCP.Grant)}
  end

  defp mcp_env(extra) do
    put_test_env(Brando.MCP, Keyword.merge([client_metadata_fetcher: {Brando.MCPHelpers, :fetch}], extra))
  end

  defp call(tenant, token, name, arguments) do
    tenant
    |> rpc(token, "tools/call", %{"name" => "brando_media_" <> name, "arguments" => arguments})
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp prepare!(tenant, token, args \\ %{}) do
    assert %{"structuredContent" => %{"upload_id" => id, "upload_url" => url}} =
             call(tenant, token, "prepare_upload", Map.merge(%{"kind" => "image", "filename" => "Photo.jpg"}, args))

    {id, url}
  end

  # A PUT as curl -T sends it: no Content-Type, no credentials but the URL.
  # (`Phoenix.ConnTest` wants a Content-Type with a body, so the endpoint is
  # called as the server would.)
  defp put_bytes(url, body, headers \\ [], method \\ :put, adapter \\ nil) do
    conn = %{Plug.Test.conn(method, URI.parse(url).path, body) | host: BrandoAdmin.AdminHost.endpoint_host()}
    conn = if adapter, do: %{conn | adapter: {adapter, elem(conn.adapter, 1)}}, else: conn

    headers
    |> Enum.reduce(conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
    |> Brando.endpoint().call(Brando.endpoint().init([]))
  end

  defp upload!(tenant, token, body, args \\ %{}) do
    {id, url} = prepare!(tenant, token)
    assert %{"upload_id" => ^id, "bytes" => size} = put_bytes(url, body) |> json_response(200)
    assert size == byte_size(body)
    call(tenant, token, "finish_upload", Map.merge(%{"upload_id" => id}, args))
  end

  defp images,
    do: Brando.Repo.all(from(i in Image, where: is_nil(i.deleted_at) and like(i.path, "%uploads/%"), order_by: :id))

  defp secret(url), do: Path.basename(URI.parse(url).path)

  # An upload past the time it is kept, as `upload_keep_minutes` long ago would make it
  defp expire!(id) do
    meta = Path.join([Uploads.root(), id, "meta.json"])
    File.write!(meta, meta |> File.read!() |> Jason.decode!() |> Map.put("keep_until", 0) |> Jason.encode!())
  end

  defp pending, do: if(File.exists?(Uploads.root()), do: File.ls!(Uploads.root()), else: [])

  test "the three tools are offered: the URL import reaches out, the upload does not",
       %{tenant: tenant, token: token} do
    %{"result" => %{"tools" => tools}} = rpc(tenant, token, "tools/list") |> json_response(200)
    by_name = Map.new(tools, &{&1["name"], &1["annotations"]})

    assert %{"readOnlyHint" => false, "openWorldHint" => false} = by_name["brando_media_prepare_upload"]
    assert %{"readOnlyHint" => false, "destructiveHint" => false} = by_name["brando_media_finish_upload"]
    assert %{"readOnlyHint" => false, "openWorldHint" => true} = by_name["brando_media_import_url"]
  end

  describe "prepare_upload" do
    test "gives a one-time URL under the endpoint, with its expiry, limit and types", %{tenant: tenant, token: token} do
      assert %{"structuredContent" => result} =
               call(tenant, token, "prepare_upload", %{"kind" => "image", "filename" => "photo.jpg"})

      assert %{"upload_id" => id, "upload_url" => url, "expires_at" => expires, "max_bytes" => @limit} = result
      assert url == MCP.resource(tenant) <> "/uploads/" <> id <> "/" <> secret(url)
      assert "image/jpeg" in result["types"]
      {:ok, expires, 0} = DateTime.from_iso8601(expires)
      assert DateTime.diff(expires, DateTime.utc_now()) in 590..600
    end

    test "refuses every kind but images, saying so", %{tenant: tenant, token: token} do
      for kind <- ["file", "video"] do
        assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
                 call(tenant, token, "prepare_upload", %{"kind" => kind, "filename" => "a.pdf"})

        assert error =~ "Only images can be uploaded so far"
      end

      assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
               call(tenant, token, "prepare_upload", %{"kind" => "sound", "filename" => "a.mp3"})

      assert error =~ "only images"

      assert %{"isError" => true, "structuredContent" => %{"error" => "filename is required."}} =
               call(tenant, token, "prepare_upload", %{"kind" => "image"})
    end

    test "a connection has at most so many uploads waiting", %{tenant: tenant, token: token} do
      mcp_env(upload_dir: Uploads.root(), upload_max_pending: 2)
      prepare!(tenant, token)
      prepare!(tenant, token)

      assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
               call(tenant, token, "prepare_upload", %{"kind" => "image", "filename" => "c.jpg"})

      assert error =~ "2 uploads waiting"
    end

    test "an upload that can no longer be used does not hold a place, and a failed finish removes it",
         %{tenant: tenant, token: token, dir: dir} do
      mcp_env(upload_dir: dir, upload_max_pending: 2)

      # Refused bytes: the URL is used up
      {refused, url} = prepare!(tenant, token)
      assert put_bytes(url, "not an image at all").status == 415
      prepare!(tenant, token)
      {third, _url} = prepare!(tenant, token)

      # Finishing the refused one says why and removes it
      assert %{"isError" => true, "structuredContent" => %{"error" => "The upload failed" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => refused})

      refute refused in pending()

      # A URL past its time that nothing was sent to
      Uploads.discard(third)
      mcp_env(upload_dir: dir, upload_max_pending: 2, upload_url_minutes: -1)
      {expired, _url} = prepare!(tenant, token)
      mcp_env(upload_dir: dir, upload_max_pending: 2)
      prepare!(tenant, token)

      assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
               call(tenant, token, "finish_upload", %{"upload_id" => expired})

      assert error =~ "expired"
      refute expired in pending()
    end

    test "uploads not finished in time are removed when the next is prepared, and nightly",
         %{tenant: tenant, token: token, dir: dir} do
      mcp_env(upload_dir: dir, upload_keep_minutes: -1)
      {first, _url} = prepare!(tenant, token)
      assert pending() == [first]

      {second, _url} = prepare!(tenant, token)
      assert pending() == [second]

      MCP.prune()
      assert pending() == []
    end

    test "a configured upload_dir is left as it is: the uploads wait in a directory of their own in it",
         %{tenant: tenant, token: token, dir: dir} do
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o755)
      # Something of the operator's, named like an upload, long expired
      theirs = Path.join(dir, String.duplicate("A", 22))
      File.mkdir_p!(theirs)
      File.touch!(theirs, 0)

      mcp_env(upload_dir: dir, upload_keep_minutes: -1)
      {id, _url} = prepare!(tenant, token)
      MCP.prune()

      assert File.dir?(theirs)
      assert File.stat!(dir).mode |> Bitwise.band(0o777) == 0o755
      assert Path.dirname(Uploads.root()) == dir
      assert File.stat!(Uploads.root()).mode |> Bitwise.band(0o777) == 0o700
      refute File.exists?(Path.join(dir, id))
    end

    test "the default directory is the application's own", %{tenant: tenant, token: token} do
      mcp_env(upload_dir: nil)
      assert Path.basename(Uploads.root()) == "brando-mcp-uploads-#{Brando.otp_app()}"
      assert Path.dirname(Uploads.root()) == System.tmp_dir!()
      {id, _url} = prepare!(tenant, token)
      Uploads.discard(id)
    end

    test "a directory the server cannot make its own is refused, by every step, and said once in the log",
         %{tenant: tenant, token: token, dir: dir} do
      {sent, url} = prepare!(tenant, token)
      {_unsent, unsent_url} = prepare!(tenant, token)
      assert put_bytes(url, @jpg).status == 200
      # Past its time only once sent: the second prepare sweeps
      expire!(sent)

      # The uploads directory is now a link to another's directory, which
      # holds what looks like an hour-old upload
      elsewhere = dir <> "-elsewhere"
      on_exit(fn -> File.rm_rf(elsewhere) end)
      File.rename!(Uploads.root(), elsewhere)
      File.ln_s!(elsewhere, Uploads.root())
      theirs = Path.join(elsewhere, String.duplicate("A", 22))
      File.mkdir_p!(theirs)
      File.touch!(theirs, 0)
      before = File.ls!(elsewhere) |> Enum.sort()

      log =
        Brando.Test.OwnLog.capture(fn ->
          assert %{"isError" => true, "structuredContent" => %{"error" => "The upload could not be prepared" <> _}} =
                   call(tenant, token, "prepare_upload", %{"kind" => "image", "filename" => "a.jpg"})

          MCP.prune()
          assert put_bytes(unsent_url, @jpg).status == 404

          assert %{"isError" => true, "structuredContent" => %{"error" => "There is no such upload" <> _}} =
                   call(tenant, token, "finish_upload", %{"upload_id" => sent})

          call(tenant, token, "prepare_upload", %{"kind" => "image", "filename" => "a.jpg"})
        end)

      assert File.ls!(elsewhere) |> Enum.sort() == before
      assert File.ls!(Path.join(elsewhere, sent)) |> Enum.sort() == ["bytes", "claimed", "meta.json", "received.json"]
      assert [_one] = Regex.scan(~r/is not a directory of the server's own/, log)
      assert log =~ Uploads.root()
    end

    test "upload_dir: nil, as the guide shows it, is the default directory, and pruning goes on",
         %{tenant: tenant, token: token, grant: grant} do
      mcp_env(upload_dir: nil)
      {id, _url} = prepare!(tenant, token)
      on_exit(fn -> Uploads.discard(id) end)
      assert String.starts_with?(Uploads.root(), System.tmp_dir!())
      assert File.dir?(Path.join(Uploads.root(), id))

      MCP.revoke_grant(grant, :system, "test")
      assert MCP.prune() > 0

      # A sweep that cannot run does not keep the tokens from going
      Brando.Repo.update_all(MCP.Token, set: [expires_at: DateTime.add(DateTime.utc_now(), -5, :second)])
      _ = connect_directly(Brando.Factory.insert(:random_user, role: :admin) |> enable_two_factor(), tenant)
      Brando.Repo.update_all(MCP.Token, set: [expires_at: DateTime.add(DateTime.utc_now(), -5, :second)])
      mcp_env(upload_dir: 42)
      assert MCP.prune() > 0
    end
  end

  describe "an upload" do
    test "is stored as an editor's upload, in the uploads folder, and found again by its bytes",
         %{tenant: tenant, token: token} do
      assert %{"structuredContent" => result} = upload!(tenant, token, @jpg)
      assert %{"asset" => %{"kind" => "image", "id" => id}, "reused" => false, "folder" => "uploads"} = result

      assert [%Image{id: ^id, path: path, folder_id: folder_id, content_hash: hash}] = images()
      assert path =~ ~r{/uploads/[^/]+\.jpg$}
      assert %Folder{name: "uploads"} = Brando.Repo.get!(Folder, folder_id)
      assert hash == Brando.Images.Intake.hash(Brando.Images.Utils.media_path(path))

      # The pending bytes are gone once finished
      assert pending() == []

      # The same bytes again: the image the library has
      assert %{"structuredContent" => %{"asset" => %{"id" => ^id}, "reused" => true}} = upload!(tenant, token, @jpg)
      assert length(images()) == 1
    end

    test "goes into the folder named, and takes its type from its bytes, not its name",
         %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token, %{"filename" => "not-really.jpg", "folder" => "../../products/./2026"})
      assert %{"type" => "image/png"} = put_bytes(url, @png, [{"content-type", "image/jpeg"}]) |> json_response(200)

      assert %{"structuredContent" => %{"folder" => "products/2026"}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})

      assert [%Image{path: path}] =
               Brando.Repo.all(from(i in Image, where: like(i.path, "%products/2026/%") and is_nil(i.deleted_at)))

      assert path =~ ~r{/default/products/2026/[^/]+\.png$}
    end

    test "is told on the connection's live page and written to Activity", %{tenant: tenant, token: token, grant: grant} do
      Brando.MCP.Watch.subscribe(grant.id)
      {id, url} = prepare!(tenant, token)

      assert_receive {Brando.MCP.Watch,
                      %{
                        state: :ok,
                        tool: "brando_media_prepare_upload",
                        details: %{"input" => %{"filename" => "Photo.jpg"}} = prepared
                      }}

      # The URL is a credential: never on the page or in Activity
      refute Jason.encode!(prepared) =~ secret(url)

      put_bytes(url, @jpg)
      call(tenant, token, "finish_upload", %{"upload_id" => id})
      [%Image{id: image_id}] = images()

      assert_receive {Brando.MCP.Watch,
                      %{state: :ok, tool: "brando_media_finish_upload", event_id: event_id, details: details}}

      assert %{"folder" => "uploads", "images" => [%{"id" => ^image_id, "reused" => false}]} = details
      assert %Event{source: :mcp, details: %{"tool" => "brando_media_finish_upload"}} = Brando.Repo.get!(Event, event_id)

      refute Brando.Repo.repo().exists?(
               from(e in Event, where: fragment("?::text LIKE ?", e.details, ^"%#{secret(url)}%"))
             )
    end

    test "sets the focal point, title and alt text given", %{tenant: tenant, token: token} do
      assert %{"structuredContent" => result} =
               upload!(tenant, token, @jpg, %{
                 "focal" => %{"x" => 20, "y" => 75.4, "mode" => "position"},
                 "title" => "Harbour",
                 "alt" => "Boats in a harbour"
               })

      assert %{"applied" => ["alt", "focal", "title"]} = result
      [image] = images()
      assert %{x: 20, y: 75, mode: :position} = image.focal
      assert Map.values(image.title) == ["Harbour"]
      assert Map.values(image.alt) == ["Boats in a harbour"]
    end

    # The default image config takes SVGs; the test config does not
    test "an SVG, uploaded or imported, gets the focal point, title and alt text given",
         %{tenant: tenant, token: token} do
      images_env = Application.get_env(:brando, Brando.Images, [])

      put_test_env(
        Brando.Images,
        Keyword.update!(
          images_env,
          :default_config,
          &Map.update!(&1, :allowed_mimetypes, fn types -> types ++ ["image/svg+xml"] end)
        )
      )

      attrs = %{"focal" => %{"x" => 20, "y" => 75, "mode" => "position"}, "title" => "Logo", "alt" => "The logo"}

      svg = fn color ->
        ~s(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="20"><rect width="10" height="20" fill="#{color}"/></svg>)
      end

      assert %{"structuredContent" => %{"applied" => ["alt", "focal", "title"]}} =
               upload!(tenant, token, svg.("red"), attrs)

      receiver = WebhookReceiver.start(fn _request -> {200, svg.("blue")} end)
      args = Map.put(attrs, "url", WebhookReceiver.url(receiver, "/logo.svg"))

      assert %{"structuredContent" => %{"applied" => ["alt", "focal", "title"], "reused" => false}} =
               call(tenant, token, "import_url", args)

      assert [_uploaded, _imported] = images = images()

      for image <- images do
        assert image.path =~ ~r/\.svg$/
        assert image.content_hash == Brando.Images.Intake.hash(Brando.Images.Utils.media_path(image.path))
        assert %{x: 20, y: 75, mode: :position} = image.focal
        assert Map.values(image.title) == ["Logo"]
        assert Map.values(image.alt) == ["The logo"]
      end
    end

    test "copies the focal point of the image it replaces", %{tenant: tenant, token: token} do
      %{"structuredContent" => %{"asset" => %{"id" => old}}} =
        upload!(tenant, token, @png, %{"focal" => %{"x" => 10, "y" => 90, "mode" => "position"}})

      assert %{"structuredContent" => %{"asset" => %{"id" => new}, "applied" => ["focal"]}} =
               upload!(tenant, token, @jpg, %{"focal" => %{"from" => %{"kind" => "image", "id" => old}}})

      assert %{focal: %{x: 10, y: 90, mode: :position}} = Brando.Repo.get!(Image, new)
    end

    test "a reused image keeps its own focal point and texts, and the result says so", %{tenant: tenant, token: token} do
      upload!(tenant, token, @jpg, %{"focal" => %{"x" => 30, "y" => 30}})

      assert %{"structuredContent" => %{"reused" => true, "not_applied" => [focal, title]}} =
               upload!(tenant, token, @jpg, %{"focal" => %{"x" => 90, "y" => 90}, "title" => "Other"})

      assert focal =~ "focal: the library already had this image"
      assert title =~ "title:"
      assert [%Image{focal: %{x: 30, y: 30, mode: :center}}] = images()
    end

    test "a reused image reports its own folder, and the folder asked for is not made",
         %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token, %{"folder" => "products"})
      put_bytes(url, @jpg)

      assert %{"structuredContent" => %{"folder" => "products"}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})

      {id, url} = prepare!(tenant, token, %{"folder" => "elsewhere"})
      put_bytes(url, @jpg)

      assert %{"structuredContent" => %{"reused" => true, "folder" => "products"}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})

      refute Brando.Repo.repo().exists?(from(f in Folder, where: f.name == "elsewhere"))
    end

    test "a bad focal point is refused before the upload is used", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      put_bytes(url, @jpg)

      for {focal, message} <- [
            {%{"x" => 120, "y" => 10}, "percentage"},
            {%{"x" => 10, "y" => 10, "mode" => "zoom"}, "mode"},
            {%{"from" => %{"kind" => "image", "id" => 999_999}}, "no image 999999"},
            {"middle", "focal is"}
          ] do
        assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
                 call(tenant, token, "finish_upload", %{"upload_id" => id, "focal" => focal})

        assert error =~ message
      end

      assert %{"structuredContent" => %{"asset" => %{"id" => _}}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})
    end

    test "is finished once", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      put_bytes(url, @jpg)
      assert %{"structuredContent" => %{"asset" => _}} = call(tenant, token, "finish_upload", %{"upload_id" => id})

      assert %{"isError" => true, "structuredContent" => %{"error" => "There is no such upload" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})
    end

    test "cannot be finished before its bytes have arrived", %{tenant: tenant, token: token} do
      {id, _url} = prepare!(tenant, token)

      assert %{"isError" => true, "structuredContent" => %{"error" => "Nothing has been sent" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})
    end
  end

  describe "the upload URL" do
    test "works once", %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)
      assert put_bytes(url, @jpg).status == 200
      assert %{"error" => "This upload URL has been used" <> _} = put_bytes(url, @png) |> json_response(409)
    end

    test "is refused after a failed attempt too: a second try needs a new URL", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      assert put_bytes(url, "not an image at all").status == 415
      assert put_bytes(url, @jpg).status == 409

      assert %{"isError" => true, "structuredContent" => %{"error" => "The upload failed: Not an image" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})
    end

    test "answers a wrong secret, an unknown id or a crafted path as an unknown upload", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      base = MCP.resource(tenant) <> "/uploads/"

      for bad <- [
            base <> id <> "/" <> String.duplicate("A", 43),
            base <> id <> "/",
            base <> String.duplicate("A", 22) <> "/" <> secret(url),
            base <> "..%2F..%2Fetc/x",
            base <> "%2E%2E/" <> secret(url)
          ] do
        assert {404, _headers, _body} = Plug.Test.sent_resp(put_bytes(bad, @jpg)), bad
      end

      # The real one still works
      assert put_bytes(url, @jpg).status == 200
    end

    test "expires", %{tenant: tenant, token: token, dir: dir} do
      mcp_env(upload_dir: dir, upload_url_minutes: -1)
      {_id, url} = prepare!(tenant, token)
      assert %{"error" => "This upload URL has expired" <> _} = put_bytes(url, @jpg) |> json_response(410)
    end

    # Phoenix logs the route's parameters at debug, the URL's path among them
    test "is kept out of the log, the route's parameters included", %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)

      # Above the test config's level for Phoenix's lines only, for this request
      Logger.put_module_level(Phoenix.Logger, :debug)
      on_exit(fn -> Logger.delete_module_level(Phoenix.Logger) end)

      log =
        Brando.Test.OwnLog.capture(fn ->
          assert put_bytes(url, @jpg).status == 200
          # A request to the same route without a token is logged as before
          put_bytes(MCP.resource(tenant) <> "/oauth/token", "")
        end)

      Logger.delete_module_level(Phoenix.Logger)

      assert log =~ "Processing with Brando.MCP.HTTP"
      refute log =~ secret(url)
    end

    test "only takes PUT", %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)
      conn = put_bytes(url, @jpg, [], :post)
      assert conn.status == 405
      assert get_resp_header(conn, "allow") == ["PUT"]
      # Not used up by the wrong method
      assert put_bytes(url, @jpg).status == 200
    end

    test "is refused once its connection is revoked", %{tenant: tenant, token: token, grant: grant, user: user} do
      {_id, url} = prepare!(tenant, token)
      :ok = MCP.revoke(grant.id, user)
      assert put_bytes(url, @jpg).status == 403
    end

    # At another site environment's path: Brando.MCP.TenancyTest
    test "is not reachable once the endpoint is off", %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)
      switch!(tenant, false)
      assert_not_found(put_bytes(url, @jpg))
    end

    test "a declared length over the size limit is refused before anything is read", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      conn = put_bytes(url, @jpg, [{"content-length", Integer.to_string(@limit + 1)}])
      assert %{"error" => "The image is larger than the site takes" <> _} = json_response(conn, 413)

      # Nothing was claimed: the URL still takes a right-sized file
      assert put_bytes(url, @jpg).status == 200
      assert %{"structuredContent" => %{"asset" => _}} = call(tenant, token, "finish_upload", %{"upload_id" => id})
    end

    test "an undeclared body is cut off as soon as it passes the size limit", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      body = @jpg <> :binary.copy(<<0>>, @limit)
      assert %{"error" => "The image is larger" <> _} = put_bytes(url, body) |> json_response(413)

      # No partial bytes are left behind
      refute File.exists?(Path.join([Uploads.root(), id, "bytes.part"]))
      refute File.exists?(Path.join([Uploads.root(), id, "bytes"]))

      assert %{"isError" => true, "structuredContent" => %{"error" => "The upload failed: The image is larger" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})
    end

    test "a body that is not an image is refused, whatever its Content-Type says", %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)

      assert %{"error" => "Not an image the site takes" <> _} =
               put_bytes(url, "<html><script>alert(1)</script></html>" <> String.duplicate(" ", 600), [
                 {"content-type", "image/jpeg"}
               ])
               |> json_response(415)

      {_id, url} = prepare!(tenant, token)
      assert put_bytes(url, "").status == 400
    end

    test "JSON and forms are refused, by the URL and by Brando.MCP.BodyLimit before the parsers",
         %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)

      for type <- [
            "application/json",
            "application/x-www-form-urlencoded",
            "multipart/form-data; boundary=x",
            "application/vnd.api+json"
          ] do
        path = URI.parse(url).path
        conn = Plug.Test.conn(:put, path, "{}") |> put_req_header("content-type", type)
        assert %{halted: true, status: 415} = Brando.MCP.BodyLimit.call(conn, [])
      end

      assert put_bytes(url, ~s({"a": 1}), [{"content-type", "application/json"}]).status == 415

      # BodyLimit leaves an upload's bytes, and the MCP endpoint's POST cap, as they were
      conn = Plug.Test.conn(:put, URI.parse(url).path, @jpg) |> put_req_header("content-type", "image/jpeg")
      assert %{halted: false} = Brando.MCP.BodyLimit.call(conn, [])
      conn = Plug.Test.conn(:post, "/mcp", "{}") |> put_req_header("content-length", "999999999")
      assert %{halted: true, status: 413} = Brando.MCP.BodyLimit.call(conn, [])
    end

    test "a body still arriving when its time is up is cut off", %{tenant: tenant, token: token, dir: dir} do
      mcp_env(upload_dir: dir, upload_transfer_minutes: -1)
      {id, url} = prepare!(tenant, token)
      assert %{"error" => "The upload took too long" <> _} = put_bytes(url, @jpg) |> json_response(408)
      refute File.exists?(Path.join([Uploads.root(), id, "bytes"]))
    end
  end

  describe "reading the bytes" do
    test "a connection that goes away mid-upload leaves no bytes, and the upload holds no place",
         %{tenant: tenant, token: token, dir: dir} do
      mcp_env(upload_dir: dir, upload_max_pending: 1)
      {id, url} = prepare!(tenant, token)
      Process.put(:raise_on_read, 0)

      assert_raise RuntimeError, "closed", fn -> put_bytes(url, @jpg, [], :put, DroppingAdapter) end

      refute File.exists?(Path.join([Uploads.root(), id, "bytes.part"]))
      refute File.exists?(Path.join([Uploads.root(), id, "bytes"]))
      assert {_id, _url} = prepare!(tenant, token)

      assert %{"isError" => true, "structuredContent" => %{"error" => "The upload failed" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})
    end

    # Over HTTP/2 Bandit kills the stream's process when the peer closes, and
    # a node can be killed mid-PUT: neither `rescue` nor `after` runs
    test "a PUT that died without a word holds no place once its time is up, and finishing it says it failed",
         %{tenant: tenant, token: token, dir: dir} do
      mcp_env(upload_dir: dir, upload_max_pending: 1)
      {id, _url} = prepare!(tenant, token)
      upload = Path.join(Uploads.root(), id)
      File.write!(Path.join(upload, "claimed"), "")
      File.write!(Path.join(upload, "bytes.part"), binary_part(@jpg, 0, 100))

      # Still within its transfer time: it may yet arrive
      assert %{"isError" => true, "structuredContent" => %{"error" => "This connection has 1 uploads" <> _}} =
               call(tenant, token, "prepare_upload", %{"kind" => "image", "filename" => "a.jpg"})

      assert %{"isError" => true, "structuredContent" => %{"error" => "The upload is still arriving" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})

      # Past it
      past = System.os_time(:second) - 11 * 60 - 60
      File.touch!(Path.join(upload, "claimed"), past)

      assert {_id, _url} = prepare!(tenant, token)

      assert %{"isError" => true, "structuredContent" => %{"error" => "The upload failed" <> _}} =
               call(tenant, token, "finish_upload", %{"upload_id" => id})

      refute id in pending()
    end

    # Bandit waits for a whole `read_length` within `read_timeout`, so a read
    # of 1 MB failed an upload sending less than 67 KB a second
    test "is read in pieces small enough for a slow connection", %{tenant: tenant, token: token} do
      {_id, url} = prepare!(tenant, token)
      Process.put(:raise_on_read, 1_000)
      assert put_bytes(url, @jpg, [], :put, DroppingAdapter).status == 200
      assert_received {:read_body, opts}
      assert opts[:read_length] <= 64_000
      assert opts[:length] <= 64_000
    end
  end

  describe "another connection" do
    test "cannot finish this connection's upload", %{tenant: tenant, token: token} do
      {id, url} = prepare!(tenant, token)
      put_bytes(url, @jpg)

      other = Brando.Factory.insert(:random_user, role: :admin) |> enable_two_factor()
      other_token = connect_directly(other, tenant)["access_token"]

      assert %{"isError" => true, "structuredContent" => %{"error" => "There is no such upload for this connection" <> _}} =
               call(tenant, other_token, "finish_upload", %{"upload_id" => id})

      # Still this connection's to finish
      assert %{"structuredContent" => %{"asset" => _}} = call(tenant, token, "finish_upload", %{"upload_id" => id})
    end
  end

  describe "import_url" do
    test "imports an image from an address, and reuses it after", %{tenant: tenant, token: token, grant: grant} do
      receiver = WebhookReceiver.start(fn _request -> {200, @png} end)
      Brando.MCP.Watch.subscribe(grant.id)

      args = %{"url" => WebhookReceiver.url(receiver, "/photos/Sunset%20Beach.png?key=secret"), "alt" => "A beach"}
      assert %{"structuredContent" => result} = call(tenant, token, "import_url", args)
      assert %{"asset" => %{"kind" => "image", "id" => id}, "reused" => false, "applied" => ["alt"]} = result
      assert [%Image{id: ^id, path: path}] = images()
      assert path =~ ~r{/uploads/[^/]+\.png$}

      assert_receive {Brando.MCP.Watch, %{state: :ok, tool: "brando_media_import_url", details: details}}
      assert %{"images" => [%{"id" => ^id, "reused" => false}], "folder" => "uploads"} = details
      refute Jason.encode!(details) =~ "secret"

      assert %{"structuredContent" => %{"asset" => %{"id" => ^id}, "reused" => true}} =
               call(tenant, token, "import_url", args)
    end

    test "copies the focal point of another image", %{tenant: tenant, token: token} do
      %{"structuredContent" => %{"asset" => %{"id" => old}}} =
        upload!(tenant, token, @jpg, %{"focal" => %{"x" => 5, "y" => 95, "mode" => "position"}})

      receiver = WebhookReceiver.start(fn _request -> {200, @png} end)

      assert %{"structuredContent" => %{"asset" => %{"id" => new}}} =
               call(tenant, token, "import_url", %{
                 "url" => WebhookReceiver.url(receiver, "/a.png"),
                 "focal" => %{"from" => %{"kind" => "image", "id" => old}}
               })

      assert %{focal: %{x: 5, y: 95, mode: :position}} = Brando.Repo.get!(Image, new)
    end

    test "refuses plain http, private addresses and credentials", %{tenant: tenant, token: token} do
      for {url, message} <- [
            {"http://images.example.com/a.png", "Only https"},
            {"https://cms.internal.test/a.png", "not public"},
            {"https://169.254.169.254/latest/meta-data", "not public"},
            {"https://user:pass@images.example.com/a.png", "user name or password"},
            {"file:///etc/passwd", "not an address"},
            {"ftp://images.example.com/a.png", "Only https"},
            {"https://nowhere.invalid/a.png", "could not be found"}
          ] do
        assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
                 call(tenant, token, "import_url", %{"url" => url})

        assert error =~ message, url
      end

      assert images() == []
    end

    test "an import refused before the store makes no folder; one the store refuses leaves it",
         %{tenant: tenant, token: token} do
      html = WebhookReceiver.start(fn _request -> {200, "<html></html>"} end)

      for url <- ["https://169.254.169.254/a.png", WebhookReceiver.url(html, "/a.png")] do
        assert %{"isError" => true} = call(tenant, token, "import_url", %{"url" => url, "folder" => "refused"})
      end

      refute Brando.Repo.repo().exists?(from(f in Folder, where: f.name == "refused"))

      # The folder is made before the store, which refuses an image over the
      # pixel limit only once it has the file
      put_test_env(Brando.Images, Keyword.put(Application.get_env(:brando, Brando.Images, []), :max_pixels, 10))
      png = WebhookReceiver.start(fn _request -> {200, @png} end)

      assert %{"isError" => true} =
               call(tenant, token, "import_url", %{"url" => WebhookReceiver.url(png, "/a.png"), "folder" => "too-large"})

      refute Brando.Repo.repo().exists?(from(i in Image, where: like(i.path, "%/too-large/%")))
      assert Brando.Repo.repo().exists?(from(f in Folder, where: f.name == "too-large"))
    end

    test "does not follow a redirect", %{tenant: tenant, token: token} do
      receiver = WebhookReceiver.start(fn _request -> {302, [{"location", "http://127.0.0.1:1/x.png"}], ""} end)

      assert %{"isError" => true, "structuredContent" => %{"error" => error}} =
               call(tenant, token, "import_url", %{"url" => WebhookReceiver.url(receiver, "/a.png")})

      assert error =~ "redirect"
      assert_received {:webhook_request, _}
      refute_received {:webhook_request, _}
    end

    test "refuses an answer over the size limit, and one that is not an image", %{tenant: tenant, token: token} do
      big = WebhookReceiver.start(fn _request -> {200, @png <> :binary.copy(<<0>>, @limit)} end)

      assert %{"isError" => true, "structuredContent" => %{"error" => "The image is larger than" <> _}} =
               call(tenant, token, "import_url", %{"url" => WebhookReceiver.url(big, "/a.png")})

      html = WebhookReceiver.start(fn _request -> {200, "<html></html>"} end)

      assert %{"isError" => true, "structuredContent" => %{"error" => "Not an image the site takes" <> _}} =
               call(tenant, token, "import_url", %{"url" => WebhookReceiver.url(html, "/a.png")})

      assert images() == []
    end
  end

  describe "with group authorization" do
    setup %{conn: conn} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Brando.Authorization.Boundary.put_scope(nil)
      owner = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      user = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{}) |> enable_two_factor()
      {:ok, _} = Brando.Authorization.Migration.run()
      _ = conn
      %{owner: owner, member: user, scope: Brando.Authorization.Scope.standalone(owner)}
    end

    defp group!(c, keys) do
      {:ok, group} =
        Brando.Authorization.Groups.create(c.scope, %{name: "MCP #{System.unique_integer([:positive])}"}, keys)

      {:ok, :ok} = Brando.Authorization.Groups.add_member(c.scope, group.id, c.member.id)
      group
    end

    test "uploading takes create on images, checked again when the bytes arrive", %{tenant: tenant} = c do
      group!(c, ["brando.admin.access", "brando.mcp.connect", "brando.images.read"])
      token = connect_directly(c.member, tenant)["access_token"]

      for {name, args} <- [
            {"prepare_upload", %{"kind" => "image", "filename" => "a.jpg"}},
            {"import_url", %{"url" => "https://images.example.com/a.png"}},
            {"finish_upload", %{"upload_id" => "x"}}
          ] do
        assert %{"isError" => true, "structuredContent" => %{"error" => error}} = call(tenant, token, name, args)
        assert error =~ "permission to create", name
      end

      creators = group!(c, ["brando.images.create"])
      {_id, url} = prepare!(tenant, token)

      # Taken away between preparing and sending
      {:ok, _} = Brando.Authorization.Groups.remove_member(c.scope, creators.id, c.member.id)
      assert put_bytes(url, @jpg).status == 403
    end

    test "a person who may create images but not update them sets a new image's focal point and texts",
         %{tenant: tenant} = c do
      group!(c, ["brando.admin.access", "brando.mcp.connect", "brando.images.read", "brando.images.create"])
      token = connect_directly(c.member, tenant)["access_token"]
      attrs = %{"focal" => %{"x" => 20, "y" => 70}, "title" => "Harbour", "alt" => "Boats"}

      assert %{"structuredContent" => %{"asset" => %{"id" => id}, "applied" => ["alt", "focal", "title"]}} =
               upload!(tenant, token, @jpg, attrs)

      assert %Image{focal: %{x: 20, y: 70}, title: title, alt: alt} = Brando.Repo.get!(Image, id)
      assert Map.values(title) == ["Harbour"]
      assert Map.values(alt) == ["Boats"]

      receiver = WebhookReceiver.start(fn _request -> {200, @png} end)

      assert %{"structuredContent" => %{"asset" => %{"id" => png}, "applied" => ["alt", "focal", "title"]}} =
               call(tenant, token, "import_url", Map.put(attrs, "url", WebhookReceiver.url(receiver, "/a.png")))

      assert %Image{focal: %{x: 20, y: 70}} = Brando.Repo.get!(Image, png)
    end
  end
end
