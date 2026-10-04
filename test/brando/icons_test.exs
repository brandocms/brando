defmodule Brando.IconsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Icons

  doctest Brando.Icons

  describe "resolve/1" do
    test "accepts current names, Lucide aliases and legacy hero names" do
      assert Icons.resolve("file-text") == {:ok, "file-text"}
      assert Icons.resolve("home") == {:ok, "house"}
      assert Icons.resolve("hero-photo") == {:ok, "image"}
      assert Icons.resolve("hero-check-circle-mini") == {:ok, "circle-check"}
      assert Icons.resolve("hero-sparkles-solid") == {:ok, "sparkles"}
    end

    test "rejects unknown names and non-strings" do
      assert Icons.resolve("hero-not-an-icon") == :error
      assert Icons.resolve("") == :error
      assert Icons.resolve(nil) == :error
    end

    test "every legacy entry points at a Lucide icon" do
      for {hero, lucide} <- Icons.Legacy.map() do
        assert {:ok, _} = Icons.resolve(lucide), "hero-#{hero} maps to unknown #{lucide}"
      end
    end
  end

  test "exists?/1 only accepts current names" do
    assert Icons.exists?("house")
    refute Icons.exists?("home")
    refute Icons.exists?("hero-x-mark")
  end

  test "the stylesheet holds one rule per icon and its path carries the version" do
    stylesheet = Icons.stylesheet()

    assert stylesheet =~ ~s(.lucide-house{--lucide:url\("data:image/svg+xml;utf8,<svg )
    assert length(String.split(stylesheet, ".lucide-")) - 1 == length(Icons.names())
    refute stylesheet =~ ~r/[#%]/
    assert :zlib.gunzip(Icons.stylesheet_gzip()) == stylesheet
    assert Icons.stylesheet_path() =~ ~r"^/__brando/icons/lucide-#{Regex.escape(Icons.version())}-[0-9a-f]{12}\.css$"
  end

  describe "Brando.HTML.Icon.icon/1" do
    test "renders a masked span" do
      html = render_component(&Brando.HTML.Icon.icon/1, name: "hero-x-mark", class: "s")

      assert html == ~s(<span data-icon class="lucide-x s"></span>)
    end

    test "renders the fallback for unknown names" do
      html = render_component(&Brando.HTML.Icon.icon/1, name: "not-an-icon")

      assert html =~ ~s(class="lucide-circle-question-mark")
    end
  end

  describe "Brando.Plug.Icons" do
    test "serves the current stylesheet with immutable caching, gzipped when accepted" do
      conn = Plug.Test.conn(:get, Icons.stylesheet_path()) |> forward()

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/css"]
      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
      assert conn.resp_body == Icons.stylesheet()

      gzipped =
        Plug.Test.conn(:get, Icons.stylesheet_path())
        |> Plug.Conn.put_req_header("accept-encoding", "gzip, br")
        |> forward()

      assert Plug.Conn.get_resp_header(gzipped, "content-encoding") == ["gzip"]
      assert gzipped.resp_body == Icons.stylesheet_gzip()
    end

    test "404s any other file" do
      conn = Plug.Test.conn(:get, "/__brando/icons/lucide-0.0.0-000000000000.css") |> forward()
      assert conn.status == 404
    end

    defp forward(conn) do
      conn
      |> Map.put(:path_info, conn.path_info -- ["__brando", "icons"])
      |> Brando.Plug.Icons.call([])
    end
  end

  describe "literal icon names in the source" do
    @roots ["lib", "assets/src", "priv/templates"]
    @extensions ~w(.ex .exs .eex .heex .svelte .js)
    @patterns [
      # <.icon name="x">, <Icon.icon name="x">, <Brando.HTML.Icon.icon name="x">, <Icon name="x">
      ~r/<(?:\.icon|[A-Z][\w.]*\.icon|Icon)\b[^>]*?\bname=["']([^"'{}]+)["']/s,
      # icon: "x", icon="x"
      ~r/\bicon(?::\s*|=)["']([a-z0-9][a-z0-9-]*)["']/
    ]

    test "every literal name is a current Lucide icon" do
      unknown =
        for root <- @roots,
            file <- Path.wildcard(Path.join(root, "**/*")),
            Path.extname(file) in @extensions,
            # The legacy map is all old names by design.
            file != "lib/brando/icons/legacy.ex",
            source = File.read!(file),
            pattern <- @patterns,
            [_, name] <- Regex.scan(pattern, source),
            not Icons.exists?(name),
            uniq: true,
            do: "#{file}: #{name}"

      assert unknown == [], "unknown icon names:\n" <> Enum.join(unknown, "\n")
    end
  end
end
