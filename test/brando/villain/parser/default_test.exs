
defmodule Brando.Villain.ParserTest.Parser do
  use Brando.Villain.Parser
end

defmodule Brando.Villain.ParserTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Brando.ConnCase

  import __MODULE__.Parser

  test "header/1" do
    assert header(%{"text" => "Header"}) == ~s(<h1>Header</h1>)
    assert header(%{"text" => "Header", "level" => "5"}) == ~s(<h5>Header</h5>)

    assert header(%{"text" => "Header", "level" => "5", "anchor" => "test"}) ==
             ~s(<a name="test"></a><h5>Header</h5>)
  end

  test "text/1" do
    assert text(%{"text" => "**Some** text here.", "type" => "paragraph"}) ==
             ~s(<p><strong>Some</strong> text here.</p>\n)

    assert text(%{"text" => "**Some** text here.", "type" => "lead"}) ==
             ~s(<div class=\"lead\">**Some** text here.</div>)
  end

  test "map/1" do
    assert map(%{"embed_url" => "http://nrk.no", "source" => "gmaps"}) ==
    "<div class=\"map-wrapper\">\n             <iframe width=\"420\"\n                     height=\"315\"\n                     src=\"http://nrk.no\"\n                     frameborder=\"0\"\n                     allowfullscreen>\n             </iframe>\n           </div>"
  end

  test "html/1" do
    assert html(%{"text" => "<h1>test</h1>"}) == "<h1>test</h1>"
  end

  test "video/1 youtube" do
    assert video(%{"remote_id" => "asdf1234", "source" => "youtube"}) ==
             "<div class=\"video-wrapper\">\n             <iframe width=\"420\"\n                     height=\"315\"\n                     src=\"//www.youtube.com/embed/asdf1234?autoplay=1&controls=0&showinfo=0&rel=0\"\n                     frameborder=\"0\"\n                     allowfullscreen>\n             </iframe>\n           </div>"
  end

  test "video/1 vimeo" do
    assert video(%{"remote_id" => "asdf1234", "source" => "vimeo"}) ==
             "<div class=\"video-wrapper\">\n             <iframe src=\"//player.vimeo.com/video/asdf1234\"\n                     width=\"500\"\n                     height=\"281\"\n                     frameborder=\"0\"\n                     webkitallowfullscreen\n                     mozallowfullscreen\n                     allowfullscreen>\n             </iframe>\n           </div>"
  end

  test "divider/1" do
    assert divider("whatever") == ~s(<hr>)
  end

  test "list/1" do
    assert list(%{"text" => "* test\n * test2"}) ==
             ~s(<ul>\n<li>test\n</li>\n<li>test2\n</li>\n</ul>\n)
  end

  test "columns/1" do
    assert columns([
             %{
               "class" => "six",
               "data" => [
                 %{"data" => %{"text" => "Header 1"}, "type" => "header"},
                 %{"data" => %{"text" => "Paragraph 1", "type" => "paragraph"}, "type" => "text"}
               ]
             },
             %{
               "class" => "six",
               "data" => [
                 %{"data" => %{"text" => "Header 2"}, "type" => "header"},
                 %{"data" => %{"text" => "Paragraph 2", "type" => "paragraph"}, "type" => "text"}
               ]
             }
           ]) ==
             "<div class=\"row\"><div class=\"col-md-6\"><h1>Header 1</h1><p>Paragraph 1</p>\n</div><div class=\"col-md-6\"><h1>Header 2</h1><p>Paragraph 2</p>\n</div></div>"
  end

  test "blockquote/1" do
    assert blockquote(%{"text" => "> Some text", "cite" => "J. Williamson"}) ==
             "<blockquote><p>Some text</p>\n<p>— <cite>J. Williamson</cite></p>\n</blockquote>\n"

    assert blockquote(%{"text" => "> Some text", "cite" => ""}) ==
             "<blockquote><p>Some text</p>\n</blockquote>\n"
  end
end
