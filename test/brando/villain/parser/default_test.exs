defmodule Brando.Villain.ParserTest do
  use ExUnit.Case
  import Brando.Villain.Parser.Default

  test "header/1" do
    assert header(%{text: "Header"}) == ~s(<h1>Header</h1>)
  end

  test "text/1" do
    assert text(%{text: "**Some** text here."}) ==
      ~s(<p><strong>Some</strong> text here.</p>\n)
  end

  test "video/1 youtube" do
    assert video(%{remote_id: "asdf1234", source: "youtube"}) ==
      ~s(<iframe width="420" height="315" src="//www.youtube.com/embed/asdf1234" frameborder="0" allowfullscreen></iframe>)
  end

  test "video/1 vimeo" do
    assert video(%{remote_id: "asdf1234", source: "vimeo"}) ==
      "<iframe src=\"//player.vimeo.com/video/asdf1234\" width=\"500\" height=\"281\" frameborder=\"0\" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe>"
  end

  test "image/1" do
    assert image(%{url: "http://vg.no", caption: "Caption", credits: "Credits"}) ==
      ~s(<img src="http://vg.no" alt="Caption / Credits" class="img-responsive" />)
  end

  test "divider/1" do
    assert divider("whatever") == ~s(<hr>)
  end

  test "list/1" do
    assert list(%{text: "* test\n * test2"}) ==
      ~s(<ul>\n<li>test\n</li>\n<li>test2\n</li>\n</ul>\n)
  end

  test "columns/1" do
    assert columns([%{class: "six", data: [%{data: %{text: "Header 1"}, type: "header"}, %{data: %{text: "Paragraph 1"}, type: "text"}]},
                    %{class: "six", data: [%{data: %{text: "Header 2"}, type: "header"}, %{data: %{text: "Paragraph 2"}, type: "text"}]}]) ==
      ["<div class=\"six\"><h1>Header 1</h1><p>Paragraph 1</p>\n</div>", "<div class=\"six\"><h1>Header 2</h1><p>Paragraph 2</p>\n</div>"]
  end
end