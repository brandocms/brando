defmodule Brando.SSGTest do
  use Brando.ConnCase

  alias Brando.SSG

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
end
