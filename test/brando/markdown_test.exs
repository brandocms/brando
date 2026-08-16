defmodule Brando.MarkdownTest do
  use ExUnit.Case, async: true

  alias Brando.Markdown

  test "converts Markdown to HTML through raising and non-raising APIs" do
    assert Markdown.to_html("Hello **world**") ==
             {:ok, "<p>Hello <strong>world</strong></p>"}

    assert Markdown.to_html!("# Hello") == "<h1>Hello</h1>"
  end

  test "renders soft line breaks only when requested" do
    assert Markdown.to_html!("line one\nline two") == "<p>line one\nline two</p>"

    assert Markdown.to_html!("line one\nline two", breaks: true) ==
             "<p>line one<br />\nline two</p>"
  end

  test "preserves the GFM features enabled by Earmark" do
    assert Markdown.to_html!("before ~~gone~~ after") ==
             "<p>before <del>gone</del> after</p>"

    assert Markdown.to_html!("visit https://example.com") ==
             ~s(<p>visit <a href="https://example.com">https://example.com</a></p>)

    assert Markdown.to_html!("| A | B |\n|---|---|\n| 1 | 2 |") =~ "<table>"
  end

  test "preserves smart punctuation and trusted raw HTML" do
    assert Markdown.to_html!(~s("quotes" -- dash --- em ...)) ==
             "<p>“quotes” – dash — em …</p>"

    assert Markdown.to_html!(~s(<div class="notice">Content</div>)) ==
             ~s(<div class="notice">Content</div>)
  end
end
