defmodule Brando.Villain.AssignedTagArgumentsTest do
  # A value passed through `assign` prints as the value printed directly: in
  # `{{ }}` as the same expression, escaped once. The tag arguments that read
  # an assigned text as typed (picture's `alt`, `route`, `route_i18n`,
  # `editable_field`, `inspect`) print it as the field holding that text,
  # escaped once (#3825). Every other tag and option gets what it got before:
  # the text as `{{ }}` prints it. A string a `for` or `tablerow` loop reads
  # of a list of strings, the list assigned or not, prints as that string
  # does (#3849, #3858).
  use Brando.ConnCase, async: true

  alias Brando.Factory
  alias Brando.RichTextRows.Entry
  alias Brando.Villain.Parser

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
  # the value has. `:escaped`: that text, escaped once. `:as_printed`: the
  # template with a literal holding the text as `{{ }}` prints it, which is
  # what an assigned variable gave every tag before.
  @printed [
    text: {"{{ V }}", :expression},
    attribute: {~s(<i title="{{ V }}"></i>), :expression},
    # Arguments that read an assigned text as typed
    picture_alt: {"{% picture entry.cover { lazyload: false, alt: V } %}", :field},
    route: {"{% route page_path show { V } %}", :field},
    route_in_attribute: {~s(<a href="{% route page_path show { V } %}"></a>), :field},
    route_i18n: {~s({% route_i18n "en" page_path show { V } %}), :field},
    route_i18n_in_attribute: {~s(<a href="{% route_i18n "en" page_path show { V } %}"></a>), :field},
    inspect: {"{% inspect V %}", :field},
    editable_field: {"{% editable_field V %}", :escaped},
    # Every other tag and option
    picture_caption: {"{% picture entry.cover { lazyload: false, caption: V } %}", :as_printed},
    picture_class: {"{% picture entry.cover { lazyload: false, picture_class: V } %}", :as_printed},
    video_caption: {"{% video entry.video { caption: V } %}", :as_printed},
    video_opacity: {"{% video entry.video { cover: 'svg', opacity: V } %}", :as_printed},
    video_width: {"{% video entry.video { cover: 'svg', width: V } %}", :as_printed},
    video_height: {"{% video entry.video { cover: 'svg', height: V } %}", :as_printed},
    form: {"{% form V %}", :as_printed}
  ]

  # Each way a loop reads a string of a list, with `q` for the string: the
  # loop opens and closes around the template
  @loops [
    loop: {"{% for q in entry.tags %}", "{% endfor %}"},
    loop_over_assigned_list: {"{% assign list = entry.tags %}{% for q in list %}", "{% endfor %}"},
    tablerow: {"{% tablerow q in entry.tags %}", "{% endtablerow %}"},
    tablerow_over_assigned_list: {"{% assign list = entry.tags %}{% tablerow q in list %}", "{% endtablerow %}"}
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

    entry =
      %Entry{title: @typed, intro: @rich}
      |> Map.put(:tags, [@typed])
      |> Map.put(:cover, image)
      |> Map.put(:video, video)

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

          :escaped ->
            Parser.escape_var_value(unquote(text))

          :as_printed ->
            printed = render("{{ #{value} }}", entry)
            refute printed =~ ~s(")
            render(with_value(template, ~s("#{printed}")), entry)
        end

      assert render("{% assign q = #{value} %}" <> with_value(template, "q"), entry) == expected
    end
  end

  # A string a loop reads of a list of strings (#3849): as the string printed
  # directly, `entry.tags[0]`, in the same loop
  for {kind, {open, close}} <- @loops, {way, {template, reference}} <- @printed do
    test "#{kind}, #{way}", %{entry: entry} do
      template = unquote(template)

      expected =
        case unquote(reference) do
          :expression ->
            with_value(template, "entry.tags[0]")

          :field ->
            with_value(template, "entry.title")

          :escaped ->
            Parser.escape_var_value(@typed)

          :as_printed ->
            printed = render("{{ entry.tags[0] }}", entry)
            refute printed =~ ~s(")
            with_value(template, ~s("#{printed}"))
        end

      in_loop = &(unquote(open) <> &1 <> unquote(close))
      assert render(in_loop.(with_value(template, "q")), entry) == render(in_loop.(expected), entry)
    end
  end

  # Nothing a loop reads of a list of strings prints as markup, however it is printed
  for {kind, {open, close}} <- @loops, {way, {template, _reference}} <- @printed do
    test "#{kind}, #{way}, prints no markup of the string", %{entry: entry} do
      entry = %{entry | tags: ["<script>x</script>", ~s(<b title="&amp;">)]}
      html = render(unquote(open) <> with_value(unquote(template), "q") <> unquote(close), entry)
      refute html =~ "<script"
      refute html =~ "<b "
    end
  end

  # `render … for` would bind each string as `for` does, but Brando's
  # templates load no partials: it renders nothing, and binds no string
  test "render for a list loads no partial", %{entry: entry} do
    assert_raise Liquex.Error, fn -> render(~s({% render "card" for entry.tags as q %}{{ q }}), entry) end
  end

  test "an assigned list of strings reaches inspect as the list itself", %{entry: entry} do
    entry = %{entry | tags: [@typed, "R&D"]}
    assert render("{% assign list = entry.tags %}{% inspect list %}", entry) == render("{% inspect entry.tags %}", entry)
  end

  # A list that starts from a literal was never escaped: its strings reach a
  # tag as before, through a loop or a name set from it
  test "a loop over a literal list, or a name set from a literal, reads it as it prints", %{entry: entry} do
    expected = render(~s({% inspect "A&amp;B" %}), entry)

    for template <- [
          ~s({% assign list = "A&amp;B" | split: "," %}{% for q in list %}{% inspect q %}{% endfor %}),
          ~s({% assign list = "A&amp;B" | split: "," %}{% assign l = list %}{% for q in l %}{% inspect q %}{% endfor %}),
          ~s({% assign label = "A&amp;B" %}{% assign q = label %}{% inspect q %})
        ] do
      assert render(template, entry) == expected, template
    end
  end

  test "a name a loop shadowed reads as it did after the loop", %{entry: entry} do
    html =
      render(
        "{% assign q = entry.title %}{% for q in (1..2) %}{% endfor %}{% route page_path show { q } %}",
        entry
      )

    assert html == render("{% route page_path show { entry.title } %}", entry)
  end

  # What a name was set from is tied to the value it holds, not to the name:
  # a later loop, assign or capture of it marks only what it gives the name
  test "a name a loop set again, or an assign in a loop, reads as it holds after the loop", %{entry: entry} do
    expected = render("{% route page_path show { entry.title } %}", entry)

    for template <- [
          "{% for q in (1..1) %}{% assign q = entry.title %}{% endfor %}",
          "{% for q in entry.tags %}{% assign q = entry.title %}{% endfor %}",
          ~s({% assign q = "x" %}{% for q in entry.tags %}{% endfor %}{% assign q = entry.title %})
        ] do
      assert render(template <> "{% route page_path show { q } %}", entry) == expected, template
    end
  end

  test "a name a loop over nothing would set reads as it holds in the loop's else", %{entry: entry} do
    entry = %{entry | tags: []}

    html =
      render(
        "{% assign q = entry.title %}{% for q in entry.tags %}{{ q }}" <>
          "{% else %}{% picture entry.cover { lazyload: false, alt: q } %}{% endfor %}",
        entry
      )

    assert html == render("{% picture entry.cover { lazyload: false, alt: entry.title } %}", entry)
  end

  # A value that starts from a name set from a literal, or from a literal,
  # and reads a field in a filter holds the field's text escaped
  test "an assigned value a filter adds a field to reads as the field", %{entry: entry} do
    for template <- [
          "{% picture entry.cover { lazyload: false, alt: V } %}",
          "{% route page_path show { V } %}"
        ],
        assigns <- [
          ~s({% assign prefix = "Photo: " %}{% assign alt = prefix | append: entry.title %}),
          ~s({% assign alt = "Photo: " | append: entry.title %})
        ] do
      assert render(assigns <> with_value(template, "alt"), entry) ==
               render(with_value(template, "entry.title"), %{entry | title: "Photo: " <> @typed}),
             assigns <> template
    end
  end

  test "a capture of a name set from a literal reads as what it captured", %{entry: entry} do
    html =
      render(
        ~s({% assign q = "x" %}{% capture q %}{{ entry.title }}{% endcapture %}{% assign alt = q %}) <>
          "{% route page_path show { alt } %}",
        entry
      )

    assert html == render("{% route page_path show { entry.title } %}", entry)
  end

  # `break` and `continue` in a loop's else leave the loop around it
  test "break and continue in an inner loop's else reach the outer loop", %{entry: entry} do
    entry = %{entry | tags: []}

    for {signal, expected} <- [{"break", "1"}, {"continue", "12"}] do
      template =
        "{% for x in (1..2) %}{{ x }}{% for tag in entry.tags %}{{ tag }}" <>
          "{% else %}{% #{signal} %}{% endfor %}-{% endfor %}"

      assert render(template, entry) == expected, signal
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

  # The text a tag reads is tied to the value: a capture of the same name
  # holding the same bytes reads as the assigned text, and is escaped all the same
  test "a capture of the same name and bytes still prints an escaped alt", %{entry: entry} do
    html =
      render(
        "{% assign q = entry.title %}{% capture q %}{{ entry.title }}{% endcapture %}" <>
          "{% picture entry.cover { lazyload: false, alt: q } %}",
        entry
      )

    refute html =~ "<b>"
    assert [@typed | _] = html |> Floki.parse_fragment!() |> Floki.attribute("img", "alt")
  end

  # A literal was never escaped: assigned, it reaches every tag as before
  test "an assigned literal reaches a tag as it is", %{entry: entry} do
    for template <- [
          "{% picture entry.cover { lazyload: false, alt: V } %}",
          "{% route page_path show { V } %}",
          "{% inspect V %}",
          "{% editable_field V %}"
        ] do
      assert render(~s({% assign label = "A&amp;B" %}) <> with_value(template, "label"), entry) ==
               render(with_value(template, ~s("A&amp;B")), entry),
             template
    end
  end

  # Only the variable read as itself is read as typed: an expression on it
  # reads the value assigned, as before
  test "an expression on an assigned variable reads the value assigned", %{entry: entry} do
    entry = %{entry | title: "<"}
    assert render("{% assign q = entry.title %}{{ q.size }}", entry) == "4"

    for template <- [
          "{% picture entry.cover { lazyload: false, alt: V } %}",
          "{% inspect V %}",
          "{% editable_field V %}"
        ] do
      assert render("{% assign q = entry.title %}" <> with_value(template, "q.size"), entry) ==
               render(with_value(template, "4"), entry),
             template
    end
  end

  test "raw keeps what it gives an assigned value", %{entry: entry} do
    assert render("{% assign q = entry.title | raw %}{{ q }}", entry) == render("{{ entry.title | raw }}", entry)
  end

  # An assigned value no tag reads runs its filters once, on the value `{{ }}` reads
  test "an assign of a filtered atom field works as it prints" do
    page = %Brando.Pages.Page{title: "T", status: :published}

    assert Brando.Villain.parse_and_render(
             "{% assign q = entry.status | base_encode64 %}{{ q }}",
             Brando.Villain.get_base_context(page)
           ) == Base.encode64("published")
  end

  # The text a tag reads is the exact inverse of the escape a field is read with
  # (random texts of the characters it changes and those its references are made of)
  test "unescaping gives back the escaped text" do
    alphabet = String.graphemes(~s(<>&"'{}%amp;lt#123 ))
    random = for _ <- 1..500, do: Enum.map_join(1..:rand.uniform(12), fn _ -> Enum.random(alphabet) end)

    for text <-
          [
            @typed,
            "{{ entry.title }} {% if x %}",
            "&amp; &lt; &#39; &#123;",
            "",
            "<script>{}</script>",
            "ø–é"
          ] ++ random do
      assert text |> Parser.escape_var_value() |> Parser.unescape_var_value() == text, inspect(text)
    end
  end
end
