defmodule Brando.SSGTest do
  use Brando.ConnCase

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.SSG
  alias Brando.SSG.Context
  alias Brando.WebhookReceiver

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
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
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

    assert_receive {:fetched, "/", []}
    assert_receive {:fetched, "/about", []}
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
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
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
               static_path: context.static_path,
               media_path: context.media_path,
               ssg_module: Fixture,
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
            "https://site.test:4000/about"
          ] do
        fetcher = fn url, _opts ->
          send(test, {:fetched, url})
          {:ok, %{status: 302, headers: %{"location" => [location]}, body: ""}}
        end

        assert {:error, :url_failures, %{failed_urls: [failure]}} =
                 SSG.build(
                   base_url: "http://site.test:4000",
                   output_path: context.output_path,
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
                 static_path: context.static_path,
                 media_path: context.media_path,
                 ssg_module: AboutOnly,
                 fetcher: fetcher
               )

      assert_received {:fetched, "/about", false}
      assert_received {:fetched, "/om-oss", false}
    end
  end
end
