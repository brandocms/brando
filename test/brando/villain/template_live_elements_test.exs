defmodule Brando.Villain.TemplateLiveElementsTest do
  @moduledoc """
  Text an editor typed reaches the public page as text. Ways it could come
  out as a live element: `raw` on a field that stores rendered blocks,
  `url_decode` on rich text or on plain text, and a picture's or image's
  title holding markup the caption editor does not make.
  """
  use Brando.ConnCase, async: true

  alias Brando.Captions
  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Item
  alias Brando.RichTextRows.Quote
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock

  setup do
    {:ok, %{user: Factory.insert(:random_user)}}
  end

  defp active_elements(html), do: html |> Floki.parse_fragment!() |> Floki.find("img, script, [onerror]")

  defp render_entry(template, entry), do: Villain.parse_and_render(template, Villain.get_base_context(entry))

  defp module!(user, code) do
    {:ok, module} = Content.create_module(Factory.params_for(:module, %{code: code}), user)
    module
  end

  defp block(module, attrs) do
    struct(
      %Block{type: :module, active: true, module_id: module.id, uid: Utils.generate_uid(), vars: [], refs: []},
      attrs
    )
  end

  defp render(blocks, entry \\ %Page{title: "T", language: :en}),
    do: Villain.parse(Enum.map(List.wrap(blocks), &%{block: &1}), entry)

  describe "raw on rendered blocks" do
    # Blocks as stored: what an editor typed in a text block is text in them
    @rendered ~s|<p>&lt;img src=x onerror=alert(1)&gt;</p><p class="lead">Tom &amp; <em>Jerry</em></p>|

    defp entries do
      [
        {%Page{title: "T", language: :en, rendered_blocks: @rendered}, "rendered_blocks"},
        {%Brando.TraitTest.Project{title: "T", rendered_bio_blocks: @rendered}, "rendered_bio_blocks"}
      ]
    end

    test "prints the stored HTML as it is", %{user: user} do
      for {entry, field} <- entries() do
        assert render_entry("{{ entry.#{field} | raw }}", entry) == @rendered, field
      end

      page = %Page{title: "T", language: :en, rendered_blocks: @rendered}
      assert render(block(module!(user, "{{ entry.rendered_blocks | raw }}"), []), page) == @rendered
    end

    test "leaves typed text as text after a filter and through assign" do
      for {entry, field} <- entries(),
          template <- [
            "{{ entry.#{field} | truncate: 1000 | raw }}",
            "{{ entry.#{field} | strip | raw }}",
            "{% assign x = entry.#{field} %}{{ x | raw }}",
            ~s({% assign parts = entry.#{field} | split: "&lt;/p&gt;" %}{{ parts | first | raw }})
          ] do
        assert active_elements(render_entry(template, entry)) == [], template
      end
    end

    test "prints as before without raw" do
      for {entry, field} <- entries() do
        assert render_entry("{{ entry.#{field} }}", entry) ==
                 "&lt;p&gt;&lt;img src=x onerror=alert(1)&gt;&lt;/p&gt;&lt;p class=&quot;lead&quot;&gt;" <>
                   "Tom &amp; &lt;em&gt;Jerry&lt;/em&gt;&lt;/p&gt;"
      end
    end
  end

  describe "url_decode on rich text" do
    @encoded "<p>%3Cimg src=x onerror=alert(1)%3E</p>"
    @safe "<p>A %3Cstrong%3Equote%3C/strong%3E</p>"

    defp text_ref(text),
      do: %Ref{
        name: "text",
        uid: Utils.generate_uid(),
        active: true,
        data: %TextBlock{type: "text", data: %TextBlock.Data{text: text, type: "paragraph"}}
      }

    defp kinds do
      [
        {"a blueprint's rich-text field",
         fn filters, text, _user ->
           render_entry("{{ entry.intro #{filters} }}", %Entry{title: "T", intro: text})
         end},
        {"a text block's text",
         fn filters, text, user ->
           render(block(module!(user, "{{ refs.text.data.data.text #{filters} }}"), refs: [text_ref(text)]))
         end},
        {"a rich-text variable",
         fn filters, text, user ->
           var = %Var{key: "body", label: "B", type: :rich_text, value: text}
           render(block(module!(user, "{{ body #{filters} }}"), vars: [var]))
         end}
      ]
    end

    test "sanitizes the decoded text as rich text is sanitized", %{user: user} do
      failing =
        for {kind, fun} <- kinds(),
            filters <- ["| url_decode", "| url_decode | raw", "| truncate: 100 | url_decode"],
            html = fun.(filters, @encoded, user),
            active_elements(html) != [],
            do: {kind, filters}

      assert failing == []
    end

    test "prints decoded safe markup as markup", %{user: user} do
      failing =
        for {kind, fun} <- kinds(),
            filters <- ["| url_decode", "| url_decode | raw"],
            fun.(filters, @safe, user) != "<p>A <strong>quote</strong></p>",
            do: {kind, filters}

      assert failing == []
    end

    test "decodes plain text, escaped as a plain field is" do
      assert render_entry("{{ entry.title | url_decode }}", %Entry{title: "Tom%20%26%20Jerry"}) == "Tom &amp; Jerry"
    end

    # A `%` not followed by two hex digits stays as typed, and so does an
    # escape that does not decode to a whole UTF-8 character: `%be` is the
    # byte 0xBE, which starts no character
    @percents [
      {"100% sure", "100% sure"},
      {"%", "%"},
      {"%zz", "%zz"},
      {"a trailing %4", "a trailing %4"},
      {"50%25 off 100%", "50% off 100%"},
      {"%4g%41+b%", "%4gA b%"},
      {"5%be off, 9%E2 and %E2%82%AC", "5%be off, 9%E2 and €"},
      {"%E2%82 then %E2%82%AC%E2", "%E2%82 then €%E2"}
    ]

    test "keeps a bare % in plain text as typed" do
      for {typed, decoded} <- @percents do
        assert Brando.Villain.Filters.url_decode(typed, %{}) == decoded, typed

        # Filtered text that starts with `%` prints it as `&#37;`, so that no
        # Liquid tag can begin there
        html = render_entry("{{ entry.title | url_decode }}", %Entry{title: typed})
        assert HtmlEntities.decode(html) == decoded, typed
      end
    end

    test "keeps a bare % in rich text as typed, and sanitizes what it decoded", %{user: user} do
      for {kind, fun} <- kinds(), {typed, decoded} <- @percents do
        assert fun.("| url_decode", "<p>#{typed}</p>", user) == "<p>#{decoded}</p>", "#{kind}: #{typed}"
      end

      for {kind, fun} <- kinds() do
        html = fun.("| url_decode", "<p>100% %3Cimg src=x onerror=alert(1)%3E 5%be</p>", user)
        assert active_elements(html) == [], kind
        assert html =~ "100% ", kind
        assert html =~ " 5%be", kind
      end
    end
  end

  describe "url_decode on plain text" do
    @encoded_tag "%3Cimg%20src=x%20onerror=alert(1)%3E"
    @decoded_tag "<img src=x onerror=alert(1)>"

    # Each kind of plain value, as a function that renders `{{ VALUE FILTERS }}`
    # with `text` stored in it (or written in the template, for a literal)
    defp plain_kinds do
      [
        {"a plain entry field", fn filters, text, _user -> render_entry("{{ entry.title #{filters} }}", plain(text)) end},
        {"a plain field of an embeds_many row",
         fn filters, text, _user -> render_entry("{{ entry.quotes[0].credit #{filters} }}", plain(text)) end},
        {"a plain field of a has_many row",
         fn filters, text, _user ->
           render_entry("{% for row in entry.items %}{{ row.label #{filters} }}{% endfor %}", plain(text))
         end},
        {"a plain module variable",
         fn filters, text, user ->
           var = %Var{key: "heading", label: "H", type: :string, value: text}
           render(block(module!(user, "{{ heading #{filters} }}"), vars: [var]))
         end},
        {"a string literal",
         fn filters, text, user -> render(block(module!(user, ~s({{ "#{text}" #{filters} }})), [])) end},
        {"a value from assign",
         fn filters, text, _user ->
           render_entry("{% assign t = entry.title %}{{ t #{filters} }}", plain(text))
         end}
      ]
    end

    defp plain(text),
      do: %Entry{title: text, quotes: [%Quote{credit: text}], items: [%Item{label: text, text: "<p>x</p>"}]}

    test "prints what it decoded as text, escaped as a plain field is", %{user: user} do
      failing =
        for {kind, fun} <- plain_kinds(),
            html = fun.("| url_decode", @encoded_tag, user),
            html != "&lt;img src=x onerror=alert(1)&gt;",
            do: {kind, html}

      assert failing == []
    end

    test "is escaped once assigned, and a filter after it gets escaped text", %{user: user} do
      failing =
        for {kind, fun} <- plain_kinds(),
            {filters, expected} <- [
              {"| url_decode | append: '!'", "&lt;img src=x onerror=alert(1)&gt;!"},
              {"| url_decode | truncate: 100", "&lt;img src=x onerror=alert(1)&gt;"},
              # What a plain field holding the decoded text gives to the same filter
              {"| url_decode | size", "#{String.length("&lt;img src=x onerror=alert(1)&gt;")}"}
            ],
            html = fun.(filters, @encoded_tag, user),
            html != expected,
            do: {kind, filters, html}

      assert failing == []

      assert render_entry("{% assign t = entry.title | url_decode %}{{ t }}", plain(@encoded_tag)) ==
               "&lt;img src=x onerror=alert(1)&gt;"
    end

    test "with raw after it, prints what raw prints of a plain field", %{user: user} do
      failing =
        for {kind, fun} <- plain_kinds(),
            raw_of_plain = fun.("| raw", @decoded_tag, user),
            html = fun.("| url_decode | raw", @encoded_tag, user),
            html != raw_of_plain or html != @decoded_tag,
            do: {kind, html, raw_of_plain}

      assert failing == []
    end

    test "a comparison sees the escaped text, as with a plain field" do
      template =
        ~s({% assign t = entry.title | url_decode %}{% if t == "R&amp;D" %}escaped{% elsif t == "R&D" %}typed{% endif %})

      assert render_entry(template, plain("R%26D")) == "escaped"
      assert render_entry(~s({% if entry.title == "R&amp;D" %}escaped{% endif %}), plain("R&D")) == "escaped"
    end

    test "a Markdown template gets the decoded text as it is", %{user: user} do
      {:ok, module} =
        Content.create_module(
          Factory.params_for(:module, %{code: "<p>x</p>", markdown_code: "{{ '%3Cb%3E a %26 b' | url_decode }}"}),
          user
        )

      md = Villain.Markdown.render([%{block: block(module, [])}], %Page{title: "T", language: :en})
      assert md =~ "<b> a & b"
    end
  end

  describe "picture and image titles" do
    @title ~s|<em>a</em><img src=x onerror=alert(1)>|

    defp picture_ref(title),
      do: %Ref{
        name: "pic",
        uid: Utils.generate_uid(),
        active: true,
        data: %PictureBlock{type: "picture", data: %PictureBlock.Data{title: title}}
      }

    test "print only the caption editor's elements", %{user: user} do
      for filters <- ["", "| raw"] do
        html = render(block(module!(user, "{{ refs.pic.data.data.title #{filters} }}"), refs: [picture_ref(@title)]))
        assert html == "<em>a</em>", filters

        image = Factory.build(:image, %{title: @title})
        context = Villain.get_base_context(%Page{title: "T", language: :en, meta_image: image})
        assert Villain.parse_and_render("{{ entry.meta_image.title #{filters} }}", context) == "<em>a</em>", filters
      end
    end

    test "keep the elements and attributes the editor makes" do
      for caption <- [
            ~s(<p style="text-align: center;">A <strong>b</strong> <em>c</em></p>),
            ~s(<p><a href="https://example.com/" target="_blank" rel="noopener noreferrer">a</a></p>),
            ~s(<p><a href="/x" data-identifier-id="4" class="action-button">a</a></p>),
            ~s(<h2 class="lead">A</h2><ul><li>b</li></ul><p><span style="color: #ff0000;">c</span><sub>1</sub><sup>2</sup></p>),
            ~s(<ol start="3"><li>Third</li></ol>)
          ] do
        assert Captions.caption_html(caption) == caption
      end
    end

    test "remove other elements and attributes, keeping their text" do
      assert Captions.caption_html(~s|<p onclick="x()" style="position: fixed">A</p><div>B</div>|) == "<p>A</p>B"
      assert Captions.caption_html(~s|<p><a href="javascript:alert(1)">a</a></p>|) == "<p><a>a</a></p>"

      assert Captions.caption_html(~s(<p><em>a</em><iframe src="https://example.com/"></iframe></p>)) ==
               "<p><em>a</em></p>"

      assert Captions.caption_html(~s(<p><em>a</em></p><svg><circle r="1"/></svg>)) == "<p><em>a</em></p>"
      assert Captions.library_html(~s(<p>Old</p><img src="x">)) == "<p>Old</p>"
      assert Captions.caption_html(~s|<ol start="expression(1)" type="a"><li>A</li></ol>|) == "<ol><li>A</li></ol>"
    end

    test "a title without the editor's markup is text, as before" do
      assert Captions.caption_html("Fish & <chips>") == "Fish &amp; &lt;chips&gt;"
      assert Captions.caption_html(~s(<img src="x">)) == "&lt;img src=&quot;x&quot;&gt;"
    end
  end
end
