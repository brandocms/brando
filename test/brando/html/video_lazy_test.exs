defmodule Brando.HTML.VideoLazyTest do
  # A video rendered as `<video>` is lazy unless the call or the record says
  # otherwise: its source goes in `data-src` for the frontend to set, so the
  # browser downloads nothing while it parses the page. `lazy` is the option,
  # `preload` the older name for it and the record's column.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Videos.Video
  alias Brando.Villain.Parser

  @src "https://src.vid/clip.mp4"

  defp record(attrs \\ %{}), do: struct(%Video{type: :external_file, source_url: @src}, attrs)

  defp render(video, opts), do: render_component(&Brando.HTML.Video.video/1, %{video: video, opts: opts})

  defp render_tag(video, args) do
    Brando.Villain.parse_and_render("{% video video #{args} %}", Liquex.Context.new(%{"video" => video}))
  end

  # The main `<video>`, not the `<noscript>` one
  defp main_video(html), do: html |> Floki.parse_fragment!() |> Floki.find("[data-video]")

  defp lazy?(html) do
    video = main_video(html)
    html =~ ~s(data-preload="#{@src}") and html_attr(video, "data-src") == @src and html_attr(video, "src") == nil
  end

  defp eager?(html) do
    video = main_video(html)
    not (html =~ "data-preload") and html_attr(video, "src") == @src and html_attr(video, "data-src") == nil
  end

  defp html_attr(node, name), do: node |> Floki.attribute(name) |> List.first()

  describe "the default" do
    test "a record with nothing stored and no option renders lazy" do
      assert lazy?(render(record(), []))
    end

    test "a string source renders lazy" do
      assert lazy?(render(@src, []))
    end

    test "a nil option asks the record, then the default" do
      assert lazy?(render(record(), lazy: nil))
      assert lazy?(render(record(), preload: nil))
      assert eager?(render(record(%{preload: false}), lazy: nil, preload: nil))
    end

    test "the tag renders lazy with no option" do
      assert lazy?(render_tag(record(), ""))
    end
  end

  describe "lazy" do
    test "on the call wins over the record, both ways" do
      assert lazy?(render(record(%{preload: false}), lazy: true))
      assert eager?(render(record(%{preload: true}), lazy: false))
    end

    test "on the tag renders eager over a record that is lazy" do
      assert eager?(render_tag(record(%{preload: true}), "{ lazy: false }"))
    end

    test "wins over preload when a call passes both, both ways" do
      assert lazy?(render(record(), lazy: true, preload: false))
      assert eager?(render(record(), lazy: false, preload: true))
    end
  end

  describe "compatibility" do
    test "a record with false stored renders eager" do
      assert eager?(render(record(%{preload: false}), []))
    end

    test "preload on the call renders as before" do
      assert lazy?(render(record(%{preload: false}), preload: true))
      assert eager?(render(record(%{preload: true}), preload: false))
    end

    test "a legacy string preload renders as before" do
      html = render(record(), preload: "metadata")

      assert html =~ ~s(data-preload="#{@src}")
      assert html_attr(main_video(html), "data-src") == @src
    end

    test "a video block that leaves the setting alone, on a record with nothing stored, renders lazy" do
      assert lazy?(Parser.video(record(), []))
    end

    test "a gallery video that leaves the setting alone, on a record with nothing stored, renders lazy" do
      gallery = %Brando.Galleries.Gallery{gallery_objects: [%{video: record(), config: %{}}]}

      assert lazy?(Parser.gallery(%{gallery: gallery}, []))
    end
  end

  describe "without JavaScript" do
    test "the noscript video carries controls and autoplay when they are on" do
      html = render(record(%{controls: true, autoplay: true}), [])
      noscript = html |> Floki.parse_fragment!() |> Floki.find("noscript video")

      assert Floki.attribute(noscript, "controls") != []
      assert Floki.attribute(noscript, "autoplay") != []
      assert html_attr(noscript, "src") == @src
    end

    # An eager video's own `<video>` has the source: a fallback beside it
    # would be a second player
    test "an eager video has no noscript video" do
      html = render(record(), lazy: false, controls: true, autoplay: true)
      assert html |> Floki.parse_fragment!() |> Floki.find("noscript") == []
    end

    test "the noscript video leaves them off when they are off" do
      noscript = record() |> render([]) |> Floki.parse_fragment!() |> Floki.find("noscript video")

      assert Floki.attribute(noscript, "controls") == []
      assert Floki.attribute(noscript, "autoplay") == []
    end
  end
end
