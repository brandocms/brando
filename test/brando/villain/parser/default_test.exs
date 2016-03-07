defmodule Brando.Villain.ParserTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Brando.ConnCase

  alias Brando.Image
  alias Brando.Factory

  import Brando.Villain.Parser.Default

  test "header/1" do
    assert header(%{"text" => "Header"}) == ~s(<h1>Header</h1>)
    assert header(%{"text" => "Header", "level" => "5"}) == ~s(<h5>Header</h5>)
  end

  test "text/1" do
    assert text(%{"text" => "**Some** text here.", "type" => "paragraph"}) ==
      ~s(<p><strong>Some</strong> text here.</p>\n)
    assert text(%{"text" => "**Some** text here.", "type" => "lead"}) ==
      ~s(<p class="lead"><strong>Some</strong> text here.</p>\n)
  end

  test "video/1 youtube" do
    assert video(%{"remote_id" => "asdf1234", "source" => "youtube"}) ==
      "<div class=\"video-wrapper\"><iframe width=\"420\" height=\"315\" src=\"//www.youtube.com/embed/asdf1234?autoplay=1&controls=0&showinfo=0&rel=0\" frameborder=\"0\" allowfullscreen></iframe></div>"
  end

  test "video/1 vimeo" do
    assert video(%{"remote_id" => "asdf1234", "source" => "vimeo"}) ==
      "<div class=\"video-wrapper\"><iframe src=\"//player.vimeo.com/video/asdf1234\" width=\"500\" height=\"281\" frameborder=\"0\" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe></div>"
  end

  test "image/1" do
    assert image(%{"url" => "http://vg.no", "title" => "Caption", "credits" => "Credits"}) ==
      ~s(<div class=\"img-wrapper\">\n  <img src=\"http://vg.no\" alt=\"Caption/Credits\" class=\"img-responsive\" />\n  <div class=\"image-info-wrapper\">\n    <div class=\"image-title\">\n      Caption\n    </div>\n    <div class=\"image-credits\">\n      Credits\n    </div>\n  </div>\n</div>\n)
    assert image(%{"url" => "http://vg.no", "title" => "Caption", "credits" => "Credits", "link" => "http://db.no"}) ==
      ~s(<div class="img-wrapper">\n  <a href="http://db.no" title="Caption"><img src="http://vg.no" alt="Caption/Credits" class="img-responsive" /></a>\n  <div class="image-info-wrapper">\n    <div class="image-title">\n      Caption\n    </div>\n    <div class="image-credits">\n      Credits\n    </div>\n  </div>\n</div>\n)
  end

  test "divider/1" do
    assert divider("whatever") == ~s(<hr>)
  end

  test "list/1" do
    assert list(%{"text" => "* test\n * test2"}) ==
      ~s(<ul>\n<li>test\n</li>\n<li>test2\n</li>\n</ul>\n)
  end

  test "columns/1" do
    assert columns([%{"class" => "six", "data" => [%{"data" => %{"text" => "Header 1"}, "type" => "header"}, %{"data" => %{"text" => "Paragraph 1", "type" => "paragraph"}, "type" => "text"}]},
                    %{"class" => "six", "data" => [%{"data" => %{"text" => "Header 2"}, "type" => "header"}, %{"data" => %{"text" => "Paragraph 2", "type" => "paragraph"}, "type" => "text"}]}]) ==
      "<div class=\"row\"><div class=\"col-md-6\"><h1>Header 1</h1><p>Paragraph 1</p>\n</div><div class=\"col-md-6\"><h1>Header 2</h1><p>Paragraph 2</p>\n</div></div>"
  end

  test "blockquote/1" do
    assert blockquote(%{"text" => "> Some text", "cite" => "J. Williamson"})
           == "<blockquote><p>Some text</p>\n<p>— <cite>J. Williamson</cite></p>\n</blockquote>\n"
    assert blockquote(%{"text" => "> Some text", "cite" => ""})
           == "<blockquote><p>Some text</p>\n</blockquote>\n"
  end

  test "slideshow/1" do
    setup_images()

    ret = slideshow(%{"imageseries" => "my-slides", "size" => "small"})

    assert ret =~ "/media/tmp/path/to/fake/image.jpg"
    assert ret =~ "/media/tmp/path/to/fake/image2.jpg"
  end

  defp setup_images do
    img1 = %{
      sequence: 0, image: %{title: "Title", credits: "credits",
      path: "/tmp/path/to/fake/image.jpg",
      sizes: %{small: "/tmp/path/to/fake/image.jpg",
      thumb: "/tmp/path/to/fake/thumb.jpg"}}
    }
    img2 = %{
      sequence: 1, image: %{title: "Title2", credits: "credits2",
      path: "/tmp/path/to/fake/image2.jpg",
      sizes: %{small: "/tmp/path/to/fake/image2.jpg",
      thumb: "/tmp/path/to/fake/thumb2.jpg"}}
    }

    user = Factory.create(:user)
    category = Factory.create(:image_category, creator: user, name: "Slideshows", slug: "slideshows")
    series = Factory.create(:image_series, creator: user, image_category: category, name: "My Slides", slug: "my-slides")

    img1
    |> Map.put(:creator_id, user.id)
    |> Map.put(:image_series_id, series.id)
    |> Image.create(user)

    img2
    |> Map.put(:creator_id, user.id)
    |> Map.put(:image_series_id, series.id)
    |> Image.create(user)
  end
end
