defmodule Brando.Villain.AssignedTagArgumentsTest do
  # A value passed through `assign` prints as the value printed directly: in
  # `{{ }}` as the same expression, escaped once, and in a tag as the field
  # holding the same text, which the tag escapes once (#3825).
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.RichTextRows.Entry

  @typed ~s(<b> & "q" it's)
  @rich ~s(<p>A &amp; <strong>B</strong> it's</p>)

  # Each kind of value: how a template writes it, and the text a tag gets of it
  @values [
    plain: {"entry.title", @typed},
    rich: {"entry.intro", @rich},
    filtered: {~s(entry.title | append: " & co"), @typed <> " & co"}
  ]

  # Each way of printing it: the template, with `V` for the value, and what it
  # prints the same as. `:expression`: the template with the value itself in
  # place of `V`. `:field`: the template with a plain field holding the text
  # the value has. `link` takes a link, which is no text: an assigned link is
  # a record, and reaches the tag as it does without `assign`. `video` prints
  # text only from the options it prints as markup (`caption`, `title`,
  # `play_button`); its other options are settings.
  @printed [
    text: {"{{ V }}", :expression},
    attribute: {~s(<i title="{{ V }}"></i>), :expression},
    picture_alt: {"{% picture entry.cover { lazyload: false, alt: V } %}", :field},
    route: {"{% route page_path show { V } %}", :field},
    route_in_attribute: {~s(<a href="{% route page_path show { V } %}"></a>), :field},
    route_i18n: {~s({% route_i18n "en" page_path show { V } %}), :field},
    route_i18n_in_attribute: {~s(<a href="{% route_i18n "en" page_path show { V } %}"></a>), :field},
    # Options a tag prints as markup get the text as `{{ }}` prints it, as before
    picture_caption: {"{% picture entry.cover { lazyload: false, caption: V } %}", :as_printed},
    video_caption: {"{% video entry.video { caption: V } %}", :as_printed}
  ]

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

    entry = %Entry{title: @typed, intro: @rich} |> Map.put(:cover, image) |> Map.put(:video, video)
    {:ok, entry: entry}
  end

  defp render(template, entry), do: Brando.Villain.parse_and_render(template, Brando.Villain.get_base_context(entry))

  defp with_value(template, value), do: String.replace(template, "V", value)

  for {kind, {value, text}} <- @values, {way, {template, reference}} <- @printed do
    test "#{kind} value through assign, #{way}", %{entry: entry} do
      value = unquote(value)
      template = unquote(template)

      expected =
        case unquote(reference) do
          :expression ->
            render(with_value(template, value), entry)

          :field ->
            render(with_value(template, "entry.title"), %{entry | title: unquote(text)})

          :as_printed ->
            printed = render("{{ #{value} }}", entry)
            render(with_value(template, "entry.title"), %{entry | title: "MARK"}) |> String.replace("MARK", printed)
        end

      assert render("{% assign q = #{value} %}" <> with_value(template, "q"), entry) == expected
    end
  end

  test "a loop variable of the same name is read as the loop's", %{entry: entry} do
    html =
      render(
        ~s({% assign q = entry.title %}{% assign list = "x,y" | split: "," %}{% for q in list %}{% route page_path show { q } %}|{% endfor %}),
        entry
      )

    assert html == render(~s({% route page_path show { "x" } %}|{% route page_path show { "y" } %}|), entry)
  end

  test "an assigned variable read in its own assign keeps the text a tag reads", %{entry: entry} do
    html = render(~s({% assign q = entry.title %}{% assign q = q | append: "!" %}{% route page_path show { q } %}), entry)
    assert html == render("{% route page_path show { entry.title } %}", %{entry | title: @typed <> "!"})
  end

  test "raw keeps what it gives an assigned value", %{entry: entry} do
    assert render("{% assign q = entry.title | raw %}{{ q }}", entry) == render("{{ entry.title | raw }}", entry)
  end
end
