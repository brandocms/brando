defmodule Brando.SSGTest do
  use Brando.ConnCase

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.SSG
  alias Brando.SSG.Context
  alias Brando.Test.SSGEndpoint
  alias Brando.WebhookReceiver

  # For a custom fetcher, which answers whatever origin it is asked for
  @base_url "http://127.0.0.1:4000"

  defmodule Fixture do
    import Brando.SSG

    urls :pages do
      ["/", "/about", "/feed.xml", "https://example.com/absolute"]
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-ssg-#{System.unique_integer([:positive])}")
    static_path = Path.join(root, "static")
    media_path = Path.join(root, "media")
    output_path = Path.join(root, "output")

    File.mkdir_p!(Path.join(static_path, "assets"))
    File.write!(Path.join([static_path, "assets", "app.css"]), "body{}")
    File.mkdir_p!(Path.join(media_path, "images"))
    File.write!(Path.join([media_path, "images", "logo.txt"]), "logo")

    put_test_env(:tenancy_mode, :none)
    put_test_env(:media_path, media_path)

    on_exit(fn -> File.rm_rf(root) end)

    %{static_path: static_path, media_path: media_path, output_path: output_path}
  end

  test "builds declared URLs, release assets, and media through the callable API", context do
    test_pid = self()

    fetcher = fn url, opts ->
      send(test_pid, {:fetched, URI.parse(url).path, opts[:headers]})
      {:ok, %{status: 200, body: "<main>#{URI.parse(url).path}</main>"}}
    end

    assert {:ok, result} =
             SSG.build(
               output_path: context.output_path,
               site_files: false,
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
               base_url: @base_url,
               fetcher: fetcher
             )

    assert result.url_count == 4
    assert result.processed_urls == 4
    assert result.failed_urls == []
    assert result.file_count == 6
    assert result.total_size > 0

    assert File.read!(Path.join(context.output_path, "index.html")) =~ "<main>/</main>"
    assert File.read!(Path.join([context.output_path, "about", "index.html"])) =~ "/about"
    assert File.read!(Path.join(context.output_path, "feed.xml")) =~ "/feed.xml"
    assert File.read!(Path.join([context.output_path, "absolute", "index.html"])) =~ "/absolute"
    assert File.read!(Path.join([context.output_path, "assets", "app.css"])) == "body{}"
    assert File.read!(Path.join([context.output_path, "media", "images", "logo.txt"])) == "logo"

    # Signed with tenancy_mode: :none too, so the application knows a build's request
    assert_receive {:fetched, "/", [{"x-brando-ssg-token", token}]}
    assert_receive {:fetched, "/about", [{"x-brando-ssg-token", ^token}]}
  end

  test "returns failed URLs with partial build statistics", context do
    fetcher = fn url, _opts ->
      if URI.parse(url).path == "/about",
        do: {:ok, %{status: 503, body: "unavailable"}},
        else: {:ok, %{status: 200, body: "ok"}}
    end

    assert {:error, :url_failures, result} =
             SSG.build(
               output_path: context.output_path,
               site_files: false,
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
               base_url: @base_url,
               fetcher: fetcher
             )

    assert result.processed_urls == 4
    assert result.failed_urls == ["/about (HTTP 503)"]
    refute File.exists?(Path.join([context.output_path, "about", "index.html"]))
    assert File.exists?(Path.join(context.output_path, "index.html"))
  end

  test "dry run resolves URLs without touching the filesystem", context do
    assert {:ok, result} =
             SSG.build(
               output_path: context.output_path,
               site_files: false,
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
               dry_run: true,
               fetcher: fn _url, _opts -> flunk("dry run must not fetch") end
             )

    assert result.url_count == 4
    assert result.file_count == 0
    refute File.exists?(context.output_path)
  end

  test "rejects symlinks in copied assets", context do
    outside = Path.join(context.output_path <> "-outside", "secret.txt")
    File.mkdir_p!(Path.dirname(outside))
    File.write!(outside, "secret")
    File.ln_s!(outside, Path.join(context.static_path, "linked-secret.txt"))

    assert {:error, {:unsupported_source_file, linked_path}, _result} =
             SSG.build(
               output_path: context.output_path,
               site_files: false,
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
               base_url: @base_url,
               fetcher: fn _url, _opts -> {:ok, %{status: 200, body: "ok"}} end
             )

    assert linked_path == Path.join(context.static_path, "linked-secret.txt")
    refute File.exists?(Path.join(context.output_path, "linked-secret.txt"))
  end

  describe "redirects from a listed path" do
    defmodule AboutOnly do
      @moduledoc false
      import Brando.SSG

      urls :pages do
        ["/about"]
      end
    end

    setup context do
      put_test_env(:tenancy_mode, :multi)

      site = %Site{id: 1, key: "default", delivery_mode: :static}
      environment = %Environment{id: 2, site_id: 1, key: "staging", live: false}

      elsewhere = WebhookReceiver.start(fn _request -> {200, "internal answer"} end)

      build = fn base_url ->
        SSG.build(site, environment,
          base_url: base_url,
          output_path: context.output_path,
          site_files: false,
          static_path: context.static_path,
          media_path: context.media_path,
          ssg_module: AboutOnly
        )
      end

      %{elsewhere: elsewhere, build: build, page: Path.join([context.output_path, "about", "index.html"])}
    end

    # The answer for each path on the site the build renders. It gets the site's
    # own URL too, for answers that name it.
    defp start_site(answers) do
      site =
        WebhookReceiver.start(fn %{path: path, headers: %{"host" => host}} ->
          answers.(path, "http://" <> host)
        end)

      "http://127.0.0.1:#{site.port}"
    end

    defp redirect(location, status \\ 302), do: {status, [{"location", location}], "You are being redirected."}

    defp assert_only_listed_path_requested do
      assert_received {:webhook_request, %{path: "/about"}}
      refute_receive {:webhook_request, _second_request}, 100
    end

    test "to another host fails the URL with no request there, so neither the token nor the answer moves", context do
      target = WebhookReceiver.url(context.elsewhere, "/internal")
      base_url = start_site(fn "/about", _site -> redirect(target) end)

      assert {:error, :url_failures, result} = context.build.(base_url)

      assert [failure] = result.failed_urls
      assert failure =~ "/about"
      assert failure =~ "302"
      assert failure =~ "http://127.0.0.1:#{context.elsewhere.port}"

      assert_only_listed_path_requested()
      refute File.exists?(context.page)
    end

    test "to the same host on another port or in protocol-relative form fails the URL", context do
      for location <- [
            "//127.0.0.1:#{context.elsewhere.port}/internal",
            "http://127.0.0.1:#{context.elsewhere.port}/internal"
          ] do
        base_url = start_site(fn "/about", _site -> redirect(location) end)

        assert {:error, :url_failures, %{failed_urls: [_failure]}} = context.build.(base_url)
        assert_only_listed_path_requested()
        refute File.exists?(context.page)
      end
    end

    test "with the site's host only as userinfo or on another scheme fails the URL", context do
      test = self()
      elsewhere_port = context.elsewhere.port

      for location <- [
            "http://site.test:4000@127.0.0.1:#{elsewhere_port}/internal",
            "http://user:secret@site.test:4000/about",
            "https://site.test:4000/about",
            "//site.test/about",
            "http://SITE.TEST:4001/about"
          ] do
        fetcher = fn url, _opts ->
          send(test, {:fetched, url})
          {:ok, %{status: 302, headers: %{"location" => [location]}, body: ""}}
        end

        assert {:error, :url_failures, %{failed_urls: [failure]}} =
                 SSG.build(
                   base_url: "http://site.test:4000",
                   output_path: context.output_path,
                   site_files: false,
                   static_path: context.static_path,
                   media_path: context.media_path,
                   ssg_module: AboutOnly,
                   fetcher: fetcher
                 )

        refute failure =~ "secret"
        assert_received {:fetched, "http://site.test:4000/about"}
        refute_received {:fetched, _second_request}
      end
    end

    test "with a Location the failure text keeps out credentials and invalid bytes", context do
      test = self()

      for location <- ["http://user:secret@/x", <<"http://bad", 0xFF, ".test/x">>] do
        fetcher = fn url, _opts ->
          send(test, {:fetched, url})
          {:ok, %{status: 302, headers: %{"location" => [location]}, body: ""}}
        end

        assert {:error, :url_failures, %{failed_urls: [failure]}} =
                 SSG.build(
                   base_url: "http://site.test:4000",
                   output_path: context.output_path,
                   site_files: false,
                   static_path: context.static_path,
                   media_path: context.media_path,
                   ssg_module: AboutOnly,
                   fetcher: fetcher
                 )

        assert String.valid?(failure)
        assert failure =~ "another origin"
        refute failure =~ "secret"
        refute failure =~ "user"
        assert_received {:fetched, "http://site.test:4000/about"}
        refute_received {:fetched, _second_request}
      end
    end

    test "to the same origin in another form follows it and stores the answer", context do
      test = self()

      for {base_url, location, expected} <- [
            {"http://site.test", "//site.test/om-oss", "http://site.test/om-oss"},
            {"http://site.test:4000", "http://SITE.TEST:4000/x", "http://SITE.TEST:4000/x"},
            {"http://SITE.test:4000", "http://site.TEST:4000/x", "http://site.TEST:4000/x"}
          ] do
        fetcher = fn url, _opts ->
          send(test, {:fetched, url})

          if url == base_url <> "/about",
            do: {:ok, %{status: 302, headers: %{"location" => [location]}, body: ""}},
            else: {:ok, %{status: 200, body: "<main>#{url}</main>"}}
        end

        assert {:ok, %{failed_urls: []}} =
                 SSG.build(
                   base_url: base_url,
                   output_path: context.output_path,
                   site_files: false,
                   static_path: context.static_path,
                   media_path: context.media_path,
                   ssg_module: AboutOnly,
                   fetcher: fetcher
                 )

        assert_received {:fetched, ^expected}
        assert File.read!(context.page) =~ "<main>#{expected}</main>"
      end
    end

    test "inside the site stores the answer at the listed path and sends the token only there", context do
      base_url =
        start_site(fn
          "/about", _site -> redirect("/om-oss", 301)
          "/om-oss", site -> redirect(site <> "/nb/om-oss", 307)
          "/nb/om-oss", _site -> {200, "<main>Om oss</main>"}
        end)

      assert {:ok, %{failed_urls: []}} = context.build.(base_url)
      assert File.read!(context.page) =~ "Om oss"

      header = Context.header()

      tokens =
        for path <- ["/about", "/om-oss", "/nb/om-oss"] do
          assert_received {:webhook_request, %{path: ^path, headers: %{^header => token}}}
          token
        end

      assert [_one_token] = Enum.uniq(tokens)
    end

    test "inside the site, then to another host, fails the URL without leaving the site", context do
      target = WebhookReceiver.url(context.elsewhere, "/internal")

      base_url =
        start_site(fn
          "/about", _site -> redirect("/om-oss")
          "/om-oss", _site -> redirect(target)
        end)

      assert {:error, :url_failures, %{failed_urls: [_failure]}} = context.build.(base_url)

      assert_received {:webhook_request, %{path: "/about"}}
      assert_received {:webhook_request, %{path: "/om-oss"}}
      refute_receive {:webhook_request, %{path: "/internal"}}, 100
      refute File.exists?(context.page)
    end

    test "in a loop inside the site fails the URL", context do
      base_url =
        start_site(fn
          "/about", _site -> redirect("/om-oss")
          "/om-oss", _site -> redirect("/about")
        end)

      assert {:error, :url_failures, %{failed_urls: [failure]}} = context.build.(base_url)
      assert failure =~ "too_many_redirects"
    end

    test "without a location, or with a status that does not redirect, fails the URL", context do
      for {status, headers} <- [{302, []}, {300, [{"location", "/om-oss"}]}, {304, [{"location", "/om-oss"}]}] do
        base_url = start_site(fn "/about", _site -> {status, headers, ""} end)

        assert {:error, :url_failures, %{failed_urls: [failure]}} = context.build.(base_url)
        assert failure == "/about (HTTP #{status})"
        assert_only_listed_path_requested()
      end
    end

    test "a custom fetcher gets redirect: false and its answers go through the same check", context do
      test = self()

      fetcher = fn url, opts ->
        send(test, {:fetched, URI.parse(url).path, opts[:redirect]})

        case URI.parse(url).path do
          "/about" -> {:ok, %{status: 302, headers: [{"Location", "/om-oss"}], body: ""}}
          "/om-oss" -> {:ok, %{status: 200, body: "<main>Om oss</main>"}}
        end
      end

      assert {:ok, %{failed_urls: []}} =
               SSG.build(
                 output_path: context.output_path,
                 site_files: false,
                 static_path: context.static_path,
                 media_path: context.media_path,
                 ssg_module: AboutOnly,
                 base_url: @base_url,
                 fetcher: fetcher
               )

      assert_received {:fetched, "/about", false}
      assert_received {:fetched, "/om-oss", false}
    end
  end

  describe "the origin a build requests" do
    defmodule RootOnly do
      @moduledoc false
      import Brando.SSG

      urls :pages do
        ["/", "/about"]
      end
    end

    defmodule NotStartedEndpoint do
      @moduledoc false
      use Phoenix.Endpoint, otp_app: :brando
    end

    defp build_root(context, opts) do
      SSG.build(
        [
          output_path: context.output_path,
          site_files: false,
          static_path: context.static_path,
          media_path: context.media_path,
          ssg_module: RootOnly
        ] ++ opts
      )
    end

    test "is the endpoint's own HTTP listener, on whatever port it listens", context do
      receiver = SSGEndpoint.start(fn %{path: path} -> {200, "<main>#{path}</main>"} end)
      refute receiver.port == 4000

      assert {:ok, %{failed_urls: [], processed_urls: 2}} = build_root(context, endpoint: SSGEndpoint)

      assert_received {:webhook_request, %{path: "/", headers: %{"host" => host} = headers}}
      assert host == "localhost:#{receiver.port}"
      refute Map.has_key?(headers, "x-forwarded-proto")
      assert_received {:webhook_request, %{path: "/about"}}
      assert File.read!(Path.join(context.output_path, "index.html")) =~ "<main>/</main>"
    end

    test "is the application's endpoint unless the build names one", context do
      receiver = SSGEndpoint.start(fn _request -> {200, "ok"} end)
      put_test_env(:endpoint_module, SSGEndpoint)

      assert {:ok, %{failed_urls: []}} = build_root(context, [])
      assert_received {:webhook_request, %{headers: %{"host" => host}}}
      assert host == "localhost:#{receiver.port}"
    end

    test "follows a redirect to the listener under the host it sends, on the listener's address", context do
      put_test_env(:tenancy_mode, :multi)
      site = %Site{id: 1, key: "default", delivery_mode: :static}
      environment = %Environment{id: 2, site_id: 1, key: "staging", live: false}

      # Absolute, from the request's Host, as `Plug.Conn.request_url/1` writes
      # it. On IPv6 only, where `localhost` itself may not reach the listener.
      receiver =
        SSGEndpoint.start(
          fn
            %{path: "/about", headers: %{"host" => host}} -> {302, [{"location", "http://#{host}/om-oss"}], ""}
            %{path: path} -> {200, "<main>#{path}</main>"}
          end,
          listen_ip: {0, 0, 0, 0, 0, 0, 0, 0},
          receiver_ip: {0, 0, 0, 0, 0, 0, 0, 1}
        )

      assert {:ok, %{failed_urls: []}} =
               SSG.build(site, environment,
                 endpoint: SSGEndpoint,
                 output_path: context.output_path,
                 site_files: false,
                 static_path: context.static_path,
                 media_path: context.media_path,
                 ssg_module: RootOnly
               )

      assert File.read!(Path.join([context.output_path, "about", "index.html"])) =~ "<main>/om-oss</main>"

      header = Context.header()

      for path <- ["/", "/about", "/om-oss"] do
        assert_received {:webhook_request, %{path: ^path, headers: %{^header => _token, "host" => host}}}
        assert host == "localhost:#{receiver.port}"
      end
    end

    test "is the address a listener is bound to when that is not a wildcard", context do
      assert {:ok, "http://127.0.0.1:4100"} = listener_url_for(context, {127, 0, 0, 1}, 4100)
      assert {:ok, "http://10.0.0.5:4100"} = listener_url_for(context, {10, 0, 0, 5}, 4100)
      assert {:ok, "http://[::1]:4100"} = listener_url_for(context, {0, 0, 0, 0, 0, 0, 0, 0}, 4100)
      assert {:ok, "http://[::1]:4100"} = listener_url_for(context, {0, 0, 0, 0, 0, 0, 0, 1}, 4100)
    end

    test "is :base_url when the build passes one, with no listener needed", context do
      site = WebhookReceiver.start(fn _request -> {200, "ok"} end)

      assert {:ok, %{failed_urls: []}} =
               build_root(context, endpoint: NotStartedEndpoint, base_url: WebhookReceiver.url(site, ""))
    end

    test "without a listener fails the build before any request, leaving the output as it was", context do
      File.mkdir_p!(context.output_path)
      File.write!(Path.join(context.output_path, "index.html"), "the last build")
      fetcher = fn _url, _opts -> flunk("a build without a listener must not request anything") end

      # Not running; and running with server: false (the test application's)
      for endpoint <- [NotStartedEndpoint, BrandoIntegrationWeb.Endpoint] do
        assert {:error, {:no_http_listener, ^endpoint} = reason, %{processed_urls: 0}} =
                 build_root(context, endpoint: endpoint, fetcher: fetcher)

        assert SSG.error_message(reason) =~ "#{inspect(endpoint)} has no HTTP listener"
        assert File.read!(Path.join(context.output_path, "index.html")) == "the last build"
      end
    end

    # Bandit is not among Brando's test dependencies, and Cowboy's :ranch is not
    # loaded (the test application's endpoint answers {:error, "function
    # :ranch.get_addr/1 is undefined ..."}). These are the answers the adapters
    # give for no listener, read from their source.
    @no_listener_answers [
      # Phoenix.Endpoint.Cowboy2Adapter.server_info/2 (Phoenix 1.8.16) rescues
      # :ranch.get_addr/1, whose ETS lookup raises for a listener that was
      # never started (server: false)
      {:error, "errors were found at the given arguments"},
      # :ranch.get_addr/1 (ranch 2.2) for a listener that is not listening yet
      {:ok, {:undefined, :undefined}},
      # Bandit.PhoenixAdapter.server_info/2 (Bandit 1.14) with no {endpoint,
      # :http} child, as with server: false
      {:error, :no_server_found},
      # ThousandIsland.listener_info/1 (1.6), which Bandit returns as it is,
      # with no listener process
      :error,
      # Both, for a listener on a Unix socket (`ip: {:local, path}`)
      {:ok, {:local, "/tmp/acme.sock"}}
    ]

    test "is no listener for each answer the adapters give without one", context do
      assert {:error, message} = BrandoIntegrationWeb.Endpoint.server_info(:http)
      assert is_binary(message)

      for answer <- @no_listener_answers do
        start_answering(NotStartedEndpoint, answer)
        assert SSG.listener_url(NotStartedEndpoint) == :error, "#{inspect(answer)} is no listener"

        assert {:error, {:no_http_listener, NotStartedEndpoint}, %{processed_urls: 0}} =
                 build_root(context, endpoint: NotStartedEndpoint)

        :ok = stop_supervised(NotStartedEndpoint)
      end
    end

    test "is not needed for a dry run", context do
      assert {:ok, %{url_count: 2}} = build_root(context, endpoint: NotStartedEndpoint, dry_run: true)
    end

    defmodule AnsweringAdapter do
      @moduledoc false
      def child_specs(_endpoint, _config), do: []
      def server_info(endpoint, _scheme), do: endpoint.config(:server_info_answer)
    end

    defp start_answering(endpoint, answer) do
      Application.put_env(:brando, endpoint,
        adapter: AnsweringAdapter,
        server_info_answer: answer,
        http: [port: 4100],
        server: true,
        secret_key_base: String.duplicate("x", 64)
      )

      on_exit(fn -> Application.delete_env(:brando, endpoint) end)
      start_supervised!(endpoint, restart: :temporary)
    end

    # The adapter reports the configured address, so no socket is needed here
    defp listener_url_for(_context, ip, port) do
      Application.put_env(:brando, NotStartedEndpoint,
        adapter: SSGEndpoint.Adapter,
        http: [ip: ip, port: port],
        server: true,
        secret_key_base: String.duplicate("x", 64)
      )

      on_exit(fn -> Application.delete_env(:brando, NotStartedEndpoint) end)
      pid = start_supervised!(NotStartedEndpoint, restart: :temporary)
      result = SSG.listener_url(NotStartedEndpoint)
      :ok = stop_supervised(NotStartedEndpoint)
      refute Process.alive?(pid)
      result
    end
  end

  describe "an endpoint with force_ssl" do
    defmodule PagesOnly do
      @moduledoc false
      import Brando.SSG

      urls :pages do
        ["/", "/about"]
      end
    end

    # As phx.new 1.8 writes it in config/prod.exs
    @phx_new_force_ssl [rewrite_on: [:x_forwarded_proto], exclude: [hosts: ["localhost", "127.0.0.1"]]]
    @https_url [url: [host: "example.com", port: 443, scheme: "https"]]

    # The request the build made, as Phoenix's adapters hand it to the endpoint
    # (the host from its Host header), through `Plug.SSL` as `force_ssl`
    # configures it: Phoenix adds the endpoint's host to redirect to.
    # `app` answers the requests `Plug.SSL` lets through.
    defp through_force_ssl(force_ssl, %{path: path, headers: headers}, app \\ &page/1) do
      ssl = Plug.SSL.init(Keyword.put_new(force_ssl, :host, "example.com"))

      conn =
        headers
        |> Map.delete("host")
        |> Enum.reduce(Plug.Test.conn(:get, "http://" <> headers["host"] <> path), fn {name, value}, conn ->
          Plug.Conn.put_req_header(conn, name, value)
        end)
        |> Plug.SSL.call(ssl)

      if conn.halted,
        do: {conn.status, [{"location", hd(Plug.Conn.get_resp_header(conn, "location"))}], ""},
        else: app.(conn)
    end

    defp page(conn), do: {200, [], "<main>#{conn.request_path}</main>"}

    defp build_pages(context, opts) do
      SSG.build(
        [
          endpoint: SSGEndpoint,
          output_path: context.output_path,
          site_files: false,
          static_path: context.static_path,
          media_path: context.media_path,
          ssg_module: PagesOnly
        ] ++ opts
      )
    end

    test "as phx.new writes it lets the build's requests through on a wildcard listener", context do
      for {listen_ip, receiver_ip} <- [
            {{0, 0, 0, 0}, {127, 0, 0, 1}},
            {{0, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0, 1}}
          ] do
        SSGEndpoint.start(&through_force_ssl(@phx_new_force_ssl, &1),
          listen_ip: listen_ip,
          receiver_ip: receiver_ip,
          config: [force_ssl: @phx_new_force_ssl]
        )

        assert {:ok, %{failed_urls: [], processed_urls: 2}} = build_pages(context, [])
        assert File.read!(Path.join([context.output_path, "about", "index.html"])) =~ "<main>/about</main>"
        stop_supervised!(SSGEndpoint)
      end
    end

    test "as phx.new writes it lets the build's requests through on a listener bound to one address", context do
      test = self()
      SSGEndpoint.start(fn _request -> {500, "not this way"} end, listen_ip: {10, 0, 0, 5})

      fetcher = fn url, opts ->
        %URI{host: host, path: path} = URI.parse(url)
        send(test, {:fetched, host})

        {status, headers, body} = through_force_ssl(@phx_new_force_ssl, %{path: path, headers: Map.new(opts[:headers])})
        {:ok, %{status: status, headers: headers, body: body}}
      end

      assert {:ok, %{failed_urls: [], processed_urls: 2}} = build_pages(context, fetcher: fetcher)
      assert_received {:fetched, "10.0.0.5"}
    end

    test "with its own exclude and rewrite_on lets the build through when the endpoint's URL is https", context do
      force_ssl = [rewrite_on: [:x_forwarded_proto], exclude: [hosts: ["internal.example.com"]]]

      SSGEndpoint.start(&through_force_ssl(force_ssl, &1), config: [force_ssl: force_ssl] ++ @https_url)

      assert {:ok, %{failed_urls: []}} = build_pages(context, [])
      assert_received {:webhook_request, %{headers: %{"x-forwarded-proto" => "https"}}}
    end

    test "with its own exclude and no rewrite_on fails each URL naming force_ssl", context do
      force_ssl = [exclude: [hosts: ["internal.example.com"]]]

      SSGEndpoint.start(&through_force_ssl(force_ssl, &1), config: [force_ssl: force_ssl] ++ @https_url)

      assert {:error, :url_failures, %{failed_urls: [root, about]}} = build_pages(context, [])
      assert root =~ "/ (HTTP 301"
      assert about =~ "/about (HTTP 301"
      assert about =~ "force_ssl"
      assert about =~ "localhost"
      assert about =~ "rewrite_on"
      refute about =~ "redirect_off_origin"
    end

    test "with rewrite_on follows a redirect the application builds from the request, on the listener", context do
      force_ssl = [rewrite_on: [:x_forwarded_proto], exclude: [hosts: ["internal.example.com"]]]

      # The scheme is https after rewrite_on, so `Plug.Conn.request_url/1`
      # names https and the Host the build sent
      app = fn
        %{request_path: "/about"} = conn ->
          {302, [{"location", String.replace(Plug.Conn.request_url(conn), "/about", "/om-oss")}], ""}

        conn ->
          page(conn)
      end

      receiver =
        SSGEndpoint.start(&through_force_ssl(force_ssl, &1, app), config: [force_ssl: force_ssl] ++ @https_url)

      assert {:ok, %{failed_urls: []}} = build_pages(context, [])
      assert File.read!(Path.join([context.output_path, "about", "index.html"])) =~ "<main>/om-oss</main>"
      assert_received {:webhook_request, %{path: "/om-oss", headers: %{"host" => host}}}
      assert host == "localhost:#{receiver.port}"
    end

    test "redirecting to the same path on https under the host the build sent fails the URL naming force_ssl",
         context do
      # Redirects to the request's own host, and does not read x-forwarded-proto
      force_ssl = [host: nil, exclude: [hosts: ["internal.example.com"]]]

      SSGEndpoint.start(&through_force_ssl(force_ssl, &1), config: [force_ssl: force_ssl] ++ @https_url)

      assert {:error, :url_failures, %{failed_urls: [root, about]}} = build_pages(context, [])
      assert root =~ "force_ssl"
      assert about =~ "/about (HTTP 301"
      assert about =~ "force_ssl"
    end

    test "redirecting to the same path on the listener's https origin again and again fails the URL naming force_ssl",
         context do
      test = self()

      SSGEndpoint.start(
        fn %{path: path, headers: %{"host" => host}} ->
          send(test, {:answered, path})
          {301, [{"location", "https://#{host}#{path}"}], ""}
        end,
        config: @https_url
      )

      assert {:error, :url_failures, %{failed_urls: [root, about]}} = build_pages(context, [])
      assert root =~ "force_ssl"
      assert about =~ "/about (HTTP 301"
      assert about =~ "force_ssl"

      # The listed path, and the redirect followed once on the listener
      for path <- ["/", "/", "/about", "/about"], do: assert_received({:answered, ^path})
      refute_received {:answered, _third_request}
    end

    test "redirecting to the same path on https on another host fails the URL without naming force_ssl", context do
      # A canonical-host plug, not the endpoint's host that force_ssl names
      SSGEndpoint.start(
        fn %{path: path} -> {301, [{"location", "https://www.example.com" <> path}], ""} end,
        config: @https_url
      )

      assert {:error, :url_failures, %{failed_urls: [_root, about]}} = build_pages(context, [])
      assert about =~ "another origin"
      refute about =~ "force_ssl"
    end

    test "with :base_url, redirecting to the same path on https fails the URL without naming force_ssl", context do
      fetcher = fn _url, _opts -> {:ok, %{status: 301, headers: [{"location", "https://site.test:4000/about"}]}} end

      assert {:error, :url_failures, %{failed_urls: [_root, about]}} =
               build_pages(context, base_url: "http://site.test:4000", fetcher: fetcher)

      assert about =~ "another origin"
      refute about =~ "force_ssl"
      refute about =~ "localhost"
    end
  end

  describe "a redirect on a listener build" do
    defmodule ListedAbout do
      @moduledoc false
      import Brando.SSG

      urls :pages do
        ["/about"]
      end
    end

    test "to another origin fails the URL with no request there, so the signed header stays", context do
      put_test_env(:tenancy_mode, :multi)
      site = %Site{id: 1, key: "default", delivery_mode: :static}
      environment = %Environment{id: 2, site_id: 1, key: "staging", live: false}
      test = self()
      receiver = SSGEndpoint.start(fn _request -> {500, "not this way"} end)
      elsewhere = WebhookReceiver.start()
      port = receiver.port
      header = Context.header()

      for location <- [
            "http://localhost:#{elsewhere.port}/internal",
            "http://localhost:#{port}@evil.example/internal",
            "http://localhost.evil.example:#{port}/internal",
            "//evil.example/internal"
          ] do
        fetcher = fn url, opts ->
          send(test, {:fetched, url, Map.new(opts[:headers])})
          {:ok, %{status: 302, headers: [{"location", location}], body: ""}}
        end

        assert {:error, :url_failures, %{failed_urls: [failure]}} =
                 SSG.build(site, environment,
                   endpoint: SSGEndpoint,
                   fetcher: fetcher,
                   output_path: context.output_path,
                   site_files: false,
                   static_path: context.static_path,
                   media_path: context.media_path,
                   ssg_module: ListedAbout
                 )

        assert failure =~ "another origin", location
        url = "http://127.0.0.1:#{port}/about"
        assert_received {:fetched, ^url, %{^header => _token}}
        refute_received {:fetched, _second_request, _headers}
      end
    end
  end

  describe "a build's site files" do
    defmodule SitePages do
      @moduledoc false
      import Brando.SSG

      urls :pages do
        ["/", "/about", "/old"]
      end
    end

    defmodule SiteSitemap do
      @moduledoc false
      import Brando.Sitemap

      sitemap "pages" do
        [url(%{loc: Brando.Utils.hostname("about")})]
      end
    end

    @page ~s(<!DOCTYPE html>\n<html><head>) <>
            ~s(<link rel="stylesheet" href="/assets/app.css">) <>
            ~s(</head><body><p>Every word stays as it was.</p></body></html>)

    setup context do
      cached = Cachex.get!(:cache, :seo)

      on_exit(fn ->
        if cached, do: Cachex.put(:cache, :seo, cached), else: Cachex.del(:cache, :seo)
      end)

      put_seo = fn redirects_by_language ->
        Cachex.put(
          :cache,
          :seo,
          Map.new(redirects_by_language, fn {language, redirects} ->
            {language, %Brando.Sites.SEO{redirects: redirects}}
          end)
        )
      end

      put_seo.([])
      site = Brando.Utils.hostname()
      test = self()

      answer = fn
        %{path: "/", headers: headers} ->
          send(test, {:headers, "/", headers})
          {200, @page <> ~s(<link type="text/markdown" rel="alternate" href="#{site}/index.md">)}

        %{path: "/about"} ->
          links =
            ~s(<link rel="alternate" type="text/markdown" href="/about.md">) <>
              ~s(<link rel="alternate" type="text/markdown" href="https://elsewhere.example.com/x.md">) <>
              ~s(<link rel="alternate" hreflang="nb" href="#{site}/nb/om-oss">)

          {200, @page <> links}

        %{path: "/old"} ->
          {301, [{"location", "/about"}], ""}

        %{path: "/index.md"} ->
          {200, "# Home\n"}

        %{path: "/about.md"} ->
          {200, "# About\n"}

        %{path: "/__brando_ssg__/not-found"} ->
          {404, "<h1>This page is not here</h1>"}

        %{path: "/robots.txt", headers: headers} ->
          {200, "User-agent: *\nDisallow:\nSitemap-header: #{headers["x-brando-ssg-sitemap"]}\n"}

        %{path: path} ->
          {500, "unexpected #{path}"}
      end

      build = fn opts ->
        SSG.build(
          Keyword.merge(
            [
              endpoint: SSGEndpoint,
              output_path: context.output_path,
              static_path: context.static_path,
              media_path: context.media_path,
              ssg_module: SitePages,
              sitemap_module: SiteSitemap
            ],
            opts
          )
        )
      end

      %{answer: answer, build: build, put_seo: put_seo, site: site}
    end

    defp read_output(context, path), do: File.read!(Path.join(context.output_path, path))

    # The build's request, as Phoenix hands it to the endpoint, through a
    # frontend router in the plug order an installation generates
    defp through_router(%{path: path, headers: headers}) do
      conn =
        headers
        |> Map.delete("host")
        |> Enum.reduce(Plug.Test.conn(:get, "http://" <> headers["host"] <> path), fn {name, value}, conn ->
          Plug.Conn.put_req_header(conn, name, value)
        end)
        |> Brando.Test.SiteRouter.call(Brando.Test.SiteRouter.init([]))

      {conn.status, [], conn.resp_body}
    end

    test "holds the bytes the application answered, its 404, robots.txt, sitemap and Markdown alternates",
         context do
      SSGEndpoint.start(context.answer)

      assert {:ok, result} = context.build.([])
      assert result.failed_urls == []
      assert result.url_count == 3
      refute Map.has_key?(result, :page_redirects)

      assert read_output(context, "about/index.html") ==
               @page <>
                 ~s(<link rel="alternate" type="text/markdown" href="/about.md">) <>
                 ~s(<link rel="alternate" type="text/markdown" href="https://elsewhere.example.com/x.md">) <>
                 ~s(<link rel="alternate" hreflang="nb" href="#{context.site}/nb/om-oss">)

      assert read_output(context, "index.md") == "# Home\n"
      assert read_output(context, "about.md") == "# About\n"
      refute File.exists?(Path.join(context.output_path, "x.md"))
      assert read_output(context, "404.html") == "<h1>This page is not here</h1>"
      assert read_output(context, "robots.txt") =~ "Sitemap-header: 1"

      index = context.output_path |> Path.join("sitemaps/sitemap.xml.gz") |> File.read!() |> :zlib.gunzip()
      assert index =~ Brando.Utils.public_hostname("sitemaps/sitemap-00001.xml.gz")
      sitemap = context.output_path |> Path.join("sitemaps/sitemap-00001.xml.gz") |> File.read!() |> :zlib.gunzip()
      assert sitemap =~ "<loc>#{Brando.Utils.public_hostname("about")}</loc>"

      # The listed path that redirects keeps the page it ends at, and is listed
      assert read_output(context, "old/index.html") =~ "Every word stays as it was."

      assert %{"version" => 1, "redirects" => [old]} = Jason.decode!(read_output(context, "_redirects.json"))

      assert old == %{
               "source" => "/old",
               "target" => "/about",
               "status" => 301,
               "exact" => true,
               "pattern" => "/old$",
               "language" => nil
             }
    end

    test "with tenancy_mode: :none robots.txt through Brando's controller names the build's sitemap", context do
      SSGEndpoint.start(fn
        %{path: "/robots.txt"} = request -> through_router(request)
        request -> context.answer.(request)
      end)

      assert {:ok, %{failed_urls: []}} = context.build.([])
      assert read_output(context, "robots.txt") =~ "Sitemap: #{Brando.Utils.public_hostname("sitemaps/sitemap.xml.gz")}"

      # Unsigned, the header is not believed
      assert {200, _headers, body} =
               through_router(%{path: "/robots.txt", headers: %{"host" => "example.com", "x-brando-ssg-sitemap" => "1"}})

      refute body =~ "sitemaps/sitemap.xml.gz"
    end

    test "without a sitemap tells robots.txt there is none", context do
      SSGEndpoint.start(context.answer)

      assert {:ok, %{failed_urls: []}} = context.build.(sitemap_module: nil)
      assert read_output(context, "robots.txt") =~ "Sitemap-header: 0"
      refute File.exists?(Path.join(context.output_path, "sitemaps"))
    end

    test "lists the redirect rules the application answers, in order, for a static host", context do
      SSGEndpoint.start(context.answer)
      alias Brando.Sites.Redirect

      context.put_seo.([
        {"no",
         [
           %Redirect{from: Brando.Sites.Redirects.exact_source("/gammel-side"), to: "/ny-side", code: 301},
           %Redirect{from: "/nyheter/:slug", to: "/artikler/:slug", code: 302}
         ]},
        {"en",
         [
           # A page the build has: Brando never answers this rule
           %Redirect{from: "/about$", to: "/elsewhere", code: 301},
           %Redirect{from: "/old-.*", to: "https://example.com/", code: 301},
           %Redirect{from: "/gone$", to: "/", code: 410},
           %Redirect{from: "/broken(", to: "/", code: 301}
         ]}
      ])

      assert {:ok, %{failed_urls: []}} = context.build.([])
      assert %{"redirects" => redirects} = Jason.decode!(read_output(context, "_redirects.json"))

      assert Enum.map(redirects, &Map.take(&1, ["source", "target", "status", "exact", "language"])) == [
               %{"source" => "/old", "target" => "/about", "status" => 301, "exact" => true, "language" => nil},
               %{
                 "source" => "/gammel-side",
                 "target" => "/ny-side",
                 "status" => 301,
                 "exact" => true,
                 "language" => "no"
               },
               %{
                 "source" => "/nyheter/:slug",
                 "target" => "/artikler/:slug",
                 "status" => 302,
                 "exact" => false,
                 "language" => "no"
               },
               %{
                 "source" => nil,
                 "target" => "https://example.com/",
                 "status" => 301,
                 "exact" => false,
                 "language" => "en"
               },
               %{"source" => "/gone", "target" => nil, "status" => 410, "exact" => true, "language" => "en"}
             ]

      assert Enum.at(redirects, 3)["pattern"] == "/old-.*"
    end

    test "writes no 404.html, and notes why, when the application answers a missing path with a page", context do
      SSGEndpoint.start(fn
        %{path: "/__brando_ssg__/not-found"} -> {200, "a page for every path"}
        request -> context.answer.(request)
      end)

      assert {:ok, %{failed_urls: [], notes: [note]}} = context.build.([])
      assert note =~ "/__brando_ssg__/not-found: no 404.html written, the site answers a missing path with HTTP 200"
      refute File.exists?(Path.join(context.output_path, "404.html"))
    end

    test "fails the error page's path when the application answers it with an error", context do
      SSGEndpoint.start(fn
        %{path: "/__brando_ssg__/not-found"} -> {500, "down"}
        request -> context.answer.(request)
      end)

      assert {:error, :url_failures, %{failed_urls: [failure]}} = context.build.([])
      assert failure =~ "/__brando_ssg__/not-found (HTTP 500"
      refute File.exists?(Path.join(context.output_path, "404.html"))
    end

    test "skips a Markdown alternate the application answers 404 for, and notes it", context do
      SSGEndpoint.start(fn
        %{path: "/about.md"} -> {404, "Not found\n"}
        request -> context.answer.(request)
      end)

      assert {:ok, result} = context.build.([])
      assert result.failed_urls == []
      assert result.notes == ["/about.md: not written, the application answers 404 for this Markdown alternate"]
      refute File.exists?(Path.join(context.output_path, "about.md"))
      assert read_output(context, "index.md") == "# Home\n"
    end

    test "fails the robots.txt and Markdown paths the application cannot answer", context do
      SSGEndpoint.start(fn
        %{path: path} when path in ["/robots.txt", "/about.md"] -> {500, "down"}
        request -> context.answer.(request)
      end)

      assert {:error, :url_failures, %{failed_urls: failures}} = context.build.([])
      assert failures == ["/about.md (HTTP 500)", "/robots.txt (HTTP 500)"]
    end

    test "with HEEx debug output configured fails before requesting anything", context do
      for option <- [:debug_heex_annotations, :debug_attributes] do
        previous = Application.fetch_env(:phoenix_live_view, option)
        Application.put_env(:phoenix_live_view, option, true)

        try do
          File.mkdir_p!(context.output_path)
          File.write!(Path.join(context.output_path, "previous.html"), "previous build")

          fetcher = fn _url, _opts -> flunk("a build with debug output must not request anything") end

          assert {:error, {:heex_debug_output, [^option]} = reason, _result} =
                   context.build.(base_url: "http://site.test", fetcher: fetcher)

          assert SSG.error_message(reason) =~ "#{option}: true"
          assert read_output(context, "previous.html") == "previous build"
        after
          case previous do
            {:ok, value} -> Application.put_env(:phoenix_live_view, option, value)
            :error -> Application.delete_env(:phoenix_live_view, option)
          end
        end
      end
    end
  end
end
