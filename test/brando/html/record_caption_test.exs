defmodule Brando.HTML.RecordCaptionTest do
  # `caption: true` has the library print a record's own text, which an editor
  # wrote or a video provider supplied: it reaches the page as text or as
  # sanitized rich text. A caption the template passes is the template's markup.
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Phoenix.Component
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Brando.HTML.Images
  alias Brando.HTML.Video

  @payload ~s(<img src=x onerror="document.title='caption'">)
  @rich_payload ~s(<p onclick="document.title='caption'">Rich <em>text</em></p>)

  defp image(title) do
    %Brando.Images.Image{
      path: "images/ferry.jpg",
      sizes: %{"small" => "images/small/ferry.jpg"},
      width: 300,
      height: 200,
      title: %{"en" => title},
      config_target: "default"
    }
  end

  defp video(fields) do
    struct!(
      %Brando.Videos.Video{
        type: :mux,
        status: :ready,
        width: 1920,
        height: 1080,
        aspect_ratio: "1920/1080",
        meta: %{"mux" => %{"playback_id" => "pb123"}}
      },
      fields
    )
  end

  defp render_picture(image, opts) do
    assigns = %{image: image, opts: Keyword.merge([key: :small, language: "en"], opts)}

    rendered_to_string(~H"""
    <Images.picture src={@image} opts={@opts} />
    """)
  end

  defp render_video(video, opts) do
    assigns = %{video: video, opts: opts}

    rendered_to_string(~H"""
    <Video.video video={@video} opts={@opts} />
    """)
  end

  defp liquid(template, context), do: Brando.Villain.parse_and_render(template, Liquex.Context.new(context))

  # What a browser would make of the figcaption: elements in it and its text.
  defp figcaption(html) do
    html |> Floki.parse_fragment!() |> Floki.find("figcaption")
  end

  defp assert_inert_text(html, text) do
    assert [{"figcaption", [], [^text]}] = figcaption(html)
  end

  describe "caption: true on a picture" do
    test "shows a title holding markup as text" do
      assert_inert_text(render_picture(image(@payload), caption: true), @payload)
    end

    test "sanitizes a title that is rich text" do
      [caption] = render_picture(image(@rich_payload), caption: true) |> figcaption()

      assert Floki.attribute(caption, "p", "onclick") == []
      assert Floki.find(caption, "em") != []
    end

    test "shows nothing for a title with no text" do
      assert figcaption(render_picture(image(nil), caption: true)) == []
      assert figcaption(render_picture(image(""), caption: true)) == []
    end

    test "leaves Liquid in the title for no later pass to evaluate" do
      refute render_picture(image("{{ entry.title }}"), caption: true) =~ "{{"
    end

    test "keeps a placement's rich-text title" do
      placement = %{image("Title") | title: "<p>Placed <strong>here</strong></p>"}

      [caption] = render_picture(placement, caption: true) |> figcaption()
      assert Floki.find(caption, "strong") != []
    end
  end

  describe "caption: true on a video" do
    test "shows a caption holding markup as text" do
      assert_inert_text(render_video(video(caption: @payload), caption: true), @payload)
    end

    test "shows a title holding markup as text" do
      assert_inert_text(render_video(video(caption: nil, title: @payload), caption: true), @payload)
    end

    test "sanitizes a caption that is rich text" do
      [caption] = render_video(video(caption: @rich_payload), caption: true) |> figcaption()

      assert Floki.attribute(caption, "p", "onclick") == []
      assert Floki.find(caption, "em") != []
    end

    test "an emptied caption falls back to the title" do
      assert_inert_text(render_video(video(caption: "<p></p>", title: "The title"), caption: true), "The title")
    end

    test "shows nothing for a record with no text" do
      assert figcaption(render_video(video(caption: nil, title: nil), caption: true)) == []
      assert figcaption(render_video(video(caption: "", title: ""), caption: true)) == []
    end

    test "leaves Liquid in the text for no later pass to evaluate" do
      refute render_video(video(caption: "{{ entry.title }}"), caption: true) =~ "{{"
      refute render_video(video(caption: nil, title: "{{ entry.title }}"), caption: true) =~ "{{"
    end
  end

  describe "the Liquid tags" do
    test "{% picture %} with caption: true shows a title holding markup as text" do
      "{% picture image { key: 'small', caption: true } %}"
      |> liquid(%{"image" => image(@payload), "language" => "en"})
      |> assert_inert_text(@payload)
    end

    test "{% video %} with caption: true shows a caption holding markup as text" do
      "{% video video { caption: true } %}"
      |> liquid(%{"video" => video(caption: @payload)})
      |> assert_inert_text(@payload)
    end

    test "{% video %} with caption: true shows a title holding markup as text" do
      "{% video video { caption: true } %}"
      |> liquid(%{"video" => video(caption: nil, title: @payload)})
      |> assert_inert_text(@payload)
    end

    test "a template's own caption keeps its markup" do
      assert [{"figcaption", [], [{"b", [], ["Ours"]}]}] =
               "{% picture image { key: 'small', caption: '<b>Ours</b>' } %}"
               |> liquid(%{"image" => image("Title"), "language" => "en"})
               |> figcaption()

      assert [{"figcaption", [], [{"b", [], ["Ours"]}]}] =
               "{% video video { caption: '<b>Ours</b>' } %}"
               |> liquid(%{"video" => video(caption: "Record's")})
               |> figcaption()
    end
  end

  describe "a template's own caption" do
    test "prints its markup on a picture" do
      assert [{"figcaption", [], [{"b", [], ["Ours"]}]}] =
               image("Title") |> render_picture(caption: "<b>Ours</b>") |> figcaption()
    end

    test "prints its markup on a video" do
      assert [{"figcaption", [], [{"b", [], ["Ours"]}]}] =
               video(caption: "Record's") |> render_video(caption: "<b>Ours</b>") |> figcaption()
    end

    test "a video's title option with caption: true is the template's too" do
      assert [{"figcaption", [], [{"b", [], ["Ours"]}]}] =
               video(caption: "Record's") |> render_video(caption: true, title: "<b>Ours</b>") |> figcaption()
    end
  end

  test "plain text survives: an ampersand is escaped once, a legacy entity not again" do
    assert render_picture(image("Fish & chips"), caption: true) =~ "<figcaption>Fish &amp; chips</figcaption>"
    assert render_picture(image("Fish &amp; chips"), caption: true) =~ "<figcaption>Fish &amp; chips</figcaption>"
    assert render_video(video(caption: "Fish & chips"), caption: true) =~ "<figcaption>Fish &amp; chips</figcaption>"
  end
end
