defmodule Brando.Villain.TagMarkupOptionsTest do
  # What a tag prints of a field passed to it straight. A plain field's text
  # is text in an option the tag prints as markup (picture's `caption`,
  # video's `caption`, `title` and `play_button`); rich text and a literal
  # the template writes print as markup. A video's svg cover takes `opacity`,
  # `width` and `height` as numbers; its `<video>` takes the sizes as written.
  # A form key prints in a comment as text.
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.RichTextRows.Entry

  @markup ~s(<em>x</em>)
  @rich ~s(<p>A <strong>B</strong></p>)

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :ready,
        meta: %{"bunny" => %{"video_guid" => "guid-for-a-test"}}
      )

    entry = %Entry{title: @markup, intro: @rich} |> Map.put(:cover, image) |> Map.put(:video, video)
    {:ok, entry: entry}
  end

  defp render(template, entry), do: Brando.Villain.parse_and_render(template, Brando.Villain.get_base_context(entry))

  @options [
    picture_caption: "{% picture entry.cover { lazyload: false, caption: V } %}",
    video_caption: "{% video entry.video { caption: V } %}",
    video_title: "{% video entry.video { caption: true, title: V } %}",
    video_play_button: "{% video entry.video { play_button: V } %}"
  ]

  for {option, template} <- @options do
    test "#{option}: a plain field prints as text", %{entry: entry} do
      html = render(String.replace(unquote(template), "V", "entry.title"), entry)
      refute html =~ @markup
      assert html =~ "&lt;em&gt;x&lt;/em&gt;"
    end

    test "#{option}: a rich-text field prints as markup", %{entry: entry} do
      assert render(String.replace(unquote(template), "V", "entry.intro"), entry) =~ @rich
    end

    test "#{option}: a literal prints as markup", %{entry: entry} do
      assert render(String.replace(unquote(template), "V", "'#{@markup}'"), entry) =~ @markup
    end

    test "#{option}: a value assigned with raw prints as markup", %{entry: entry} do
      template = "{% assign c = entry.title | raw %}" <> String.replace(unquote(template), "V", "c")
      assert render(template, entry) =~ @markup
    end
  end

  describe "the svg cover of a video" do
    @breakout ~s[0)"><img src=x onerror=alert(1)>]

    for option <- ~w(opacity width height) do
      test "takes no markup from #{option}", %{entry: entry} do
        html =
          render("{% video entry.video { cover: 'svg', #{unquote(option)}: entry.title } %}", %{entry | title: @breakout})

        cover = html |> Floki.parse_fragment!() |> Floki.find("[data-cover]") |> Floki.raw_html()
        refute cover =~ "onerror"
        refute html =~ "<img src=x"
        assert cover =~ "<img"
      end
    end

    # The `<video>` takes the template's value as it is (HEEx escapes it); the
    # cover takes the size from the ratio
    test "a size that is no number reaches the video element as written", %{entry: entry} do
      for value <- ["100%", "auto"] do
        html = render(~s({% video entry.video { aspect_ratio: "16/9", cover: 'svg', width: "#{value}" } %}), entry)
        assert [^value, ^value] = html |> Floki.parse_fragment!() |> Floki.attribute("video", "width")
        assert [cover] = html |> Floki.parse_fragment!() |> Floki.find("[data-cover] img")
        assert Floki.attribute(cover, "width") == ["16"]
      end
    end

    test "takes a number or a numeric text", %{entry: entry} do
      html =
        render("{% video entry.video { cover: 'svg', opacity: entry.title, width: 320, height: '180' } %}", %{
          entry
          | title: "0.5"
        })

      assert html =~ "0%2C0%2C0%2C0.5%29"
      assert html =~ ~s(width="320")
      assert html =~ ~s(height="180")
    end
  end

  describe "a form that is not published" do
    test "prints its key in the comment as text", %{entry: entry} do
      for key <- [~s[--><img src=x onerror=alert(1)>], ~s(--!><b>x</b>), "{{ entry.title }}", "{% raw %}"] do
        html = render("{% form entry.title %}", %{entry | title: key})
        assert [{:comment, _}] = Floki.parse_fragment!(html), key
        refute html =~ "{", key
        refute html =~ "<img", key
      end
    end
  end
end
