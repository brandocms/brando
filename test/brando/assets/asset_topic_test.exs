defmodule Brando.Assets.AssetTopicTest do
  @moduledoc """
  An image's processing result and a file's CDN upload reach the admin views
  waiting for them in the asset's own environment, and none in another
  environment waiting for an asset with the same id (#4018). Site Acme has a
  production and a staging environment, each in its own schema; a test gives
  an asset in one the id of an asset in the other.
  """
  # Synchronous: media paths and CDN settings are the application's, and the
  # environments' schemas have fixed names.
  use Brando.LiveCase, async: false
  use Oban.Testing, repo: BrandoIntegration.Repo

  alias Brando.Files
  alias Brando.Images
  alias Brando.Images.Image
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Worker.FileUploader
  alias Brando.Worker.ImageProcessor

  @production "tenant_assettopic_production"
  @staging "tenant_assettopic_staging"
  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)
  @queue_form "form#brando-upload-manager-queue-form"

  defmodule Migrator do
    @moduledoc false
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  # The S3 endpoint, answering a multipart upload; only the socket is replaced
  defmodule S3Stub do
    @moduledoc false
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(:post, url, _body, _headers, _opts) do
      if String.contains?(url, "uploads") and not String.contains?(url, "uploadId"),
        do: {:ok, %{status_code: 200, headers: [], body: initiated()}},
        else: {:ok, %{status_code: 200, headers: [], body: completed()}}
    end

    def request(:put, _url, _body, _headers, _opts),
      do: {:ok, %{status_code: 200, headers: [{"ETag", ~s("etag")}], body: ""}}

    def request(_method, _url, _body, _headers, _opts), do: {:ok, %{status_code: 200, headers: [], body: ""}}

    defp initiated,
      do:
        ~s(<?xml version="1.0"?><InitiateMultipartUploadResult><Bucket>testbucket</Bucket><Key>k</Key><UploadId>up1</UploadId></InitiateMultipartUploadResult>)

    defp completed,
      do:
        ~s(<?xml version="1.0"?><CompleteMultipartUploadResult><Location>l</Location><Bucket>testbucket</Bucket><Key>k</Key><ETag>"etag"</ETag></CompleteMultipartUploadResult>)
  end

  test "without tenancy the topics are the ones they have always been" do
    assert Images.image_topic(42) == "brando:image:42"
    assert Files.file_topic(42) == "brando:file:42"
  end

  describe "in an installation with environments" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir, current_user: user} do
      put_test_env(:media_path, Path.join(dir, "media"))
      put_test_env(:sites_path, Path.join(dir, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Tenant.Cache.clear()
      end)

      {:ok, _site} =
        Tenant.Setup.create_site(
          %{name: "Acme", key: "assettopic", languages: ["en"], default_language: "en", status: :active},
          user,
          environments: [
            %{name: "Production", key: "production", live: true, domain: "assettopic.test"},
            %{name: "Staging", key: "staging", live: false, domain: "staging.assettopic.test"}
          ]
        )

      :ok
    end

    test "the topics name the environment" do
      for topic <- [&Images.image_topic/1, &Files.file_topic/1] do
        assert Tenant.with_prefix(@staging, fn -> topic.(42) end) =~ ":tenant:" <> @staging

        refute Tenant.with_prefix(@staging, fn -> topic.(42) end) ==
                 Tenant.with_prefix(@production, fn -> topic.(42) end)
      end
    end

    # The manager and the form run in LiveView processes of their own, which
    # hold the environment the editor works in
    test "an image uploaded in staging is finished by its own processing, not production's", %{
      conn: conn,
      current_user: user
    } do
      %Page{} = page = Factory.build(:page, creator: nil, creator_id: user.id)
      page = Tenant.with_prefix(@staging, fn -> Brando.Repo.insert!(page) end)

      conn =
        conn
        |> Plug.Conn.put_session("brando_site_key", "assettopic")
        |> Plug.Conn.put_session("brando_environment_key", "staging")

      {form, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      manager = find_live_child(form, "brando-upload-manager-lv")
      # The manager queues the processing and the test runs it, so that
      # another environment's result can come while the upload is processing
      :sys.replace_state(manager.pid, &tap(&1, fn _state -> Process.put(:oban_testing, :manual) end))
      Process.put(:oban_testing, :manual)

      body = File.read!(@fixture)
      ref = intake(manager, form, "photo.jpg", byte_size(body))
      transfer(manager, ref, "photo.jpg", body)

      assert %{status: :processing, asset_id: id} = items(manager)[ref]
      assert %Image{} = Tenant.with_prefix(@staging, fn -> Brando.Repo.get(Image, id) end)
      assert Tenant.with_prefix(@production, fn -> Brando.Repo.get(Image, id) end) == nil
      :erlang.trace(form.pid, true, [:receive])

      # Production processes an image of its own with the same id
      foreign = insert_image(@production, id)
      assert {:ok, _} = perform_job(ImageProcessor, processing_args(foreign, @production))
      render(manager)
      render(form)
      assert %{status: :processing} = items(manager)[ref]
      refute_received {:trace, _pid, :receive, {%Image{}, [:image, _status], _path}}
      assert Enum.sort([form.pid, manager.pid]) == subscribers(@staging, id)

      [job] = all_enqueued(worker: ImageProcessor)
      assert job.args["tenant_prefix"] == @staging
      assert {:ok, _} = perform_job(ImageProcessor, job.args)
      render(manager)

      assert %{status: :done} = items(manager)[ref]
      assert_receive {:trace, _pid, :receive, {%Image{id: ^id, status: :processed} = image, [:image, :updated], _}}
      assert image.__meta__.prefix == @staging
      render(form)
      assert subscribers(@staging, id) == []
    end

    # With group authorization the manager stores and subscribes in the scope
    # the page signed into the upload, and unsubscribes in its own: the same
    test "with group authorization an upload in staging leaves no subscription behind", %{
      conn: conn,
      current_user: user
    } do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      %Page{} = page = Factory.build(:page, creator: nil, creator_id: user.id)
      page = Tenant.with_prefix(@staging, fn -> Brando.Repo.insert!(page) end)

      conn =
        conn
        |> Plug.Conn.put_session("brando_site_key", "assettopic")
        |> Plug.Conn.put_session("brando_environment_key", "staging")

      {form, html} = live_form(conn, "/admin/pages/update/#{page.id}")
      manager = find_live_child(form, "brando-upload-manager-lv")

      [scope_token] =
        html |> Floki.parse_document!() |> Floki.attribute("main[data-authorization-upload]", "data-authorization-upload")

      assert {:ok, %{prefix: @staging}} =
               Phoenix.Token.verify(BrandoIntegrationWeb.Endpoint, "brando-authorized-upload-scope", scope_token)

      :sys.replace_state(manager.pid, &tap(&1, fn _state -> Process.put(:oban_testing, :manual) end))
      Process.put(:oban_testing, :manual)

      body = File.read!(@fixture)
      ref = intake(manager, form, "photo.jpg", byte_size(body), %{"scope_token" => scope_token})
      transfer(manager, ref, "photo.jpg", body)

      assert %{status: :processing, asset_id: id} = items(manager)[ref]
      assert %Image{} = Tenant.with_prefix(@staging, fn -> Brando.Repo.get(Image, id) end)
      assert manager.pid in subscribers(@staging, id)

      [job] = all_enqueued(worker: ImageProcessor)
      assert job.args["tenant_prefix"] == @staging
      assert {:ok, _} = perform_job(ImageProcessor, job.args)
      render(manager)
      render(form)

      assert %{status: :done} = items(manager)[ref]
      assert subscribers(@staging, id) == []
    end

    # The manager is sticky: it keeps the environment of the page load, which
    # the page names in its `brando_context` meta and the browser sends along
    # when it joins a page it navigated to
    test "a live navigation into another environment loads the page, so the manager follows it", %{
      conn: conn,
      current_user: user
    } do
      %Page{} = page = Factory.build(:page, creator: nil, creator_id: user.id)
      page = Tenant.with_prefix(@production, fn -> Brando.Repo.insert!(page) end)
      path = "/admin/pages/update/#{page.id}"

      conn =
        conn
        |> Plug.Conn.put_session("brando_site_key", "assettopic")
        |> Plug.Conn.put_session("brando_environment_key", "production")

      # The page load names the environment its sticky views run in
      html = conn |> get("/admin/pages") |> html_response(200)

      assert ["assettopic/production"] =
               html |> Floki.parse_document!() |> Floki.attribute(~s(meta[name="brando_context"]), "content")

      # A link to a page in production from a page opened in staging, against the session
      from_staging = navigated_from(conn, "/admin/pages?brando_environment_key=staging", "assettopic/staging")
      assert {:error, {:redirect, %{to: ^path}}} = live(from_staging, path)

      from_production = navigated_from(conn, "/admin/pages", "assettopic/production")
      assert {:ok, _form, _html} = live(from_production, path)

      # A link that names staging in its query, as the shared library's do
      staging_listing = "/admin/pages?brando_environment_key=staging"
      assert {:error, {:redirect, %{to: ^staging_listing}}} = live(from_production, staging_listing)

      # The first join after a page load is not a navigation
      assert {:ok, _form, _html} = live(put_connect_params(conn, %{"brando_context" => "assettopic/staging"}), path)
    end

    test "a file's CDN upload is reported in its own environment only" do
      put_test_env(Brando.Files, cdn: %{cdn() | keep_local_copy: true})
      stub_s3()

      production = insert_file(@production, nil)
      _staging = insert_file(@staging, production.id)
      follow(@production, production.id)
      follow(@staging, production.id)

      args = %{
        "file_id" => production.id,
        "config_target" => "default",
        "user_id" => nil,
        "field_full_path" => [],
        "tenant_prefix" => @production
      }

      assert {:ok, _} = perform_job(FileUploader, args)

      assert_receive {:heard, @production, %Files.File{cdn: true} = file}
      assert file.__meta__.prefix == @production
      settle()
      refute_received {:heard, @staging, _file}
    end
  end

  defp intake(manager, form, filename, size, target \\ %{}) do
    render_hook(manager, "intake", %{
      "files" => [%{"index" => 0, "name" => filename, "size" => size, "type" => "image/jpeg"}],
      "target" =>
        Map.merge(
          %{
            "kind" => "entry_field",
            "field" => "meta_image",
            "asset_type" => "image",
            "config_target" => "default",
            "deliver_topic" => deliver_topic(form)
          },
          target
        )
    })

    [ref] = manager |> items() |> Map.keys()
    ref
  end

  defp navigated_from(conn, path, context),
    do: put_connect_params(conn, %{"_live_referer" => "http://localhost#{path}", "brando_context" => context})

  defp deliver_topic(form) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(form.pid)
    Enum.find_value(components, &(&1.module == BrandoAdmin.Components.Form && &1.assigns.deliver_topic))
  end

  defp transfer(manager, ref, name, content) do
    tagged = "#{ref}::#{name}"
    upload = file_input(manager, @queue_form, :queue, [%{name: tagged, content: content, type: "image/jpeg"}])
    render_upload(upload, tagged)
  end

  defp subscribers(prefix, image_id) do
    topic = Tenant.with_prefix(prefix, fn -> Images.image_topic(image_id) end)
    Brando.pubsub() |> Registry.lookup(topic) |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  end

  defp items(manager), do: :sys.get_state(manager.pid).socket.assigns.items

  defp processing_args(image, prefix),
    do: %{
      "image_id" => image.id,
      "config_target" => "default",
      "user_id" => nil,
      "field_full_path" => [],
      "tenant_prefix" => prefix
    }

  defp insert_image(prefix, id) do
    Tenant.with_prefix(prefix, fn ->
      path = "images/assettopic/#{prefix}.jpg"
      file = Images.Utils.media_path(path)
      File.mkdir_p!(Path.dirname(file))
      File.cp!(@fixture, file)

      Brando.Repo.insert!(%Image{
        id: id,
        path: path,
        width: 300,
        height: 292,
        formats: [:jpg],
        sizes: %{},
        status: :unprocessed,
        config_target: "default"
      })
    end)
  end

  defp insert_file(prefix, id) do
    Tenant.with_prefix(prefix, fn ->
      {:ok, cfg} = Files.get_config_for("default")
      filename = "#{prefix}.png"
      file = Images.Utils.media_path(Path.join(cfg.upload_path, filename))
      File.mkdir_p!(Path.dirname(file))
      File.cp!(Path.expand("../../fixtures/sample.png", __DIR__), file)

      Brando.Repo.insert!(%Files.File{
        id: id,
        filename: filename,
        filesize: 1,
        mime_type: "image/png",
        config_target: "default"
      })
    end)
  end

  defp cdn,
    do: %{
      enabled: true,
      bucket: "testbucket",
      media_url: "https://testbucket.example.com",
      s3: %Brando.CDN.S3Config{access_key_id: "KEY", secret_access_key: "SECRET", region: "ams3"},
      keep_local_copy: true
    }

  defp stub_s3 do
    previous = Application.get_env(:ex_aws, :http_client)
    Application.put_env(:ex_aws, :http_client, S3Stub)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ex_aws, :http_client, previous),
        else: Application.delete_env(:ex_aws, :http_client)
    end)
  end

  # A process following file `id` in `prefix`: it sends the test each update
  # it hears, with the prefix
  defp follow(prefix, id) do
    test = self()

    {:ok, pid} =
      Task.start_link(fn ->
        Tenant.with_prefix(prefix, fn -> Phoenix.PubSub.subscribe(Brando.pubsub(), Files.file_topic(id)) end)
        send(test, {:following, prefix})
        forward(test, prefix)
      end)

    assert_receive {:following, ^prefix}
    Process.put(:followers, [pid | Process.get(:followers, [])])
  end

  defp forward(test, prefix) do
    receive do
      {file, [:file, :updated], _path} ->
        send(test, {:heard, prefix, file})
        forward(test, prefix)

      {:settle, ref} ->
        send(test, {:settled, ref})
        forward(test, prefix)
    end
  end

  # A broadcast has reached every follower's mailbox once it returns; a
  # follower answers :settle after forwarding what came before it
  defp settle do
    for pid <- Process.get(:followers, []) do
      ref = make_ref()
      send(pid, {:settle, ref})
      assert_receive {:settled, ^ref}
    end
  end
end
