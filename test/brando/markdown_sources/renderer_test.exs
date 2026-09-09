defmodule Brando.MarkdownSources.RendererTest do
  use ExUnit.Case, async: true
  alias Brando.MarkdownSources.{HTTP, Renderer, Source}

  defp document(markdown),
    do: %{markdown: markdown, repository: "acme/docs", path: "guides/start.md", commit: String.duplicate("a", 40)}

  test "renders GFM and deterministic headings, resolving links at the imported commit" do
    {:ok, html} =
      Renderer.render(
        document(
          "# Hello\n\n# Hello\n\n[Next](next.md)\n\n![Diagram](../images/example.png)\n\n| A | B |\n|---|---|\n| 1 | 2 |"
        )
      )

    assert html =~ ~s(id="hello")
    assert html =~ ~s(id="hello-1")
    assert html =~ "https://github.com/acme/docs/blob/#{String.duplicate("a", 40)}/guides/next.md"
    assert html =~ "https://raw.githubusercontent.com/acme/docs/#{String.duplicate("a", 40)}/images/example.png"
    assert html =~ "<table>"
    {:ok, headings} = Renderer.render(document("# Hello\n# Hello\n# Hello-1"))
    ids = headings |> Floki.parse_fragment!() |> Floki.find("h1") |> Floki.attribute("id")
    assert ids == ["hello", "hello-1", "hello-1-1"]
  end

  test "external content cannot inject executable HTML or unsafe URLs" do
    {:ok, html} =
      Renderer.render(
        document(
          "<script>alert(1)</script>\n\n<svg onload='alert(2)'></svg>\n\n<img src=x onerror=alert(3)>\n\n[bad](javascript:alert(4))\n\n![bad](data:image/svg+xml,test)"
        )
      )

    refute html =~ "<script"
    refute html =~ "<svg"
    refute html =~ "onerror="
    refute html =~ "javascript:"
    refute html =~ "data:image"
    assert Renderer.safe_url("//example.org/file", document(""), "img") == nil
    assert Renderer.safe_url("../../../../outside", document(""), "a") == nil
    assert Renderer.safe_url("%2e%2e/%2e%2e/%2e%2e/outside", document(""), "a") == nil
    assert Renderer.safe_url("https://user:secret@example.org/file", document(""), "a") == nil
  end

  test "file paths and network destinations exclude traversal and private targets" do
    for path <- ["../secrets.md", "x/../secrets.md", "/etc/file.md", "x//y.md", "x%2Fy.md", "x\\y.md", "x.txt"],
        do: refute(Source.valid_path?(path))

    assert Source.valid_path?("guides/Getting started.md")

    for address <- [
          {127, 0, 0, 1},
          {10, 0, 0, 1},
          {169, 254, 169, 254},
          {192, 168, 1, 1},
          {172, 16, 0, 1},
          {100, 64, 0, 1},
          {0, 0, 0, 0},
          {224, 0, 0, 1}
        ],
        do: refute(HTTP.public_address?(address))

    assert HTTP.public_address?({140, 82, 112, 5})
  end
end
