defmodule Brando.Villain.RawOnRichTextTest do
  @moduledoc """
  `raw` decodes the entities of text that was escaped when a template read it.
  Rich text is not escaped when read: it arrives sanitized, and the characters
  an editor typed are entities in it. So `raw` leaves a value read as rich text
  as it is, also after a filter and through `assign`, and decodes any other text
  as it always did.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.Content.TableRow
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Item
  alias Brando.RichTextRows.Quote
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.Blocks.TextBlock

  defmodule ProjectFilters do
    @moduledoc false
    use Brando.Villain.Filters

    def as_safe(_value, _context), do: {:safe, "&lt;b&gt;bold&lt;/b&gt;"}
  end

  # What an editor typed, stored as rich text stores it: text, not markup
  @typed "<p>&lt;img src=x onerror=alert(1)&gt;</p>"
  @safe ~s(<p>A <strong>quote</strong> with <a href="https://example.com/">a link</a></p>)

  setup do
    {:ok, %{user: Factory.insert(:random_user)}}
  end

  defp active_elements(html), do: html |> Floki.parse_fragment!() |> Floki.find("img[onerror], script")

  # As a site renders an entry's own template: the context made first
  defp render_entry(template, entry), do: Villain.parse_and_render(template, Villain.get_base_context(entry))

  defp entry(text),
    do: %Entry{title: "T", intro: text, quotes: [%Quote{text: text}], items: [%Item{label: "A", text: text}]}

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

  defp text_ref(text),
    do: %Ref{
      name: "text",
      uid: Utils.generate_uid(),
      active: true,
      data: %TextBlock{type: "text", data: %TextBlock.Data{text: text, type: "paragraph"}}
    }

  # Each kind of rich text, as a template that prints it with FILTERS after it
  # and a function that renders that template with `text` stored in it
  defp kinds do
    [
      {"a blueprint's rich-text field", "{{ entry.intro FILTERS }}",
       fn tpl, text, _user -> render_entry(tpl, entry(text)) end},
      {"a rich-text field in a module", "{{ entry.intro FILTERS }}",
       fn tpl, text, user -> render(block(module!(user, tpl), []), entry(text)) end},
      {"a text block's text", "{{ refs.text.data.data.text FILTERS }}",
       fn tpl, text, user -> render(block(module!(user, tpl), refs: [text_ref(text)])) end},
      {"a rich-text variable", "{{ body FILTERS }}",
       fn tpl, text, user ->
         render(block(module!(user, tpl), vars: [%Var{key: "body", label: "B", type: :rich_text, value: text}]))
       end},
      {"a rich-text variable of a table row",
       "{% for row in block.table_rows %}{{ row.vars[0].value FILTERS }}{% endfor %}",
       fn tpl, text, user ->
         var = %Var{key: "body", label: "B", type: :rich_text, value: text}
         render(block(module!(user, tpl), table_rows: [%TableRow{vars: [var]}]))
       end},
      {"an embeds_many row's rich-text field", "{{ entry.quotes[0].text FILTERS }}",
       fn tpl, text, _user -> render_entry(tpl, entry(text)) end},
      {"a has_many row's rich-text field", "{% for row in entry.items %}{{ row.text FILTERS }}{% endfor %}",
       fn tpl, text, _user -> render_entry(tpl, entry(text)) end}
    ]
  end

  defp run(template, filters, text, user, fun), do: fun.(String.replace(template, "FILTERS", filters), text, user)

  describe "raw on rich text" do
    # Each kind that fails, named, rather than the first
    test "prints typed markup as text, as it prints without raw", %{user: user} do
      failing =
        for {kind, template, fun} <- kinds(),
            plain = run(template, "", @typed, user, fun),
            html = run(template, "| raw", @typed, user, fun),
            not (plain =~ "&lt;img" and html == plain and active_elements(html) == []),
            do: kind

      assert failing == []
    end

    test "prints safe markup as markup", %{user: user} do
      failing =
        for {kind, template, fun} <- kinds(),
            run(template, "| raw", @safe, user, fun) != @safe or run(template, "", @safe, user, fun) != @safe,
            do: kind

      assert failing == []
    end

    test "leaves typed markup as text after a filter that returns text", %{user: user} do
      failing =
        for {kind, template, fun} <- kinds(),
            html = run(template, "| truncate: 100 | raw", @typed, user, fun),
            active_elements(html) != [] or html != run(template, "| truncate: 100", @typed, user, fun),
            do: kind

      assert failing == []
    end

    test "leaves typed markup as text through assign" do
      for template <- [
            "{% assign x = entry.intro %}{{ x | raw }}",
            "{% assign x = entry.quotes | first %}{{ x.text | raw }}",
            "{% assign x = entry.intro | truncate: 100 %}{{ x | raw }}",
            "{% for row in entry.items %}{% assign t = row.text %}{{ t | raw }}{% endfor %}"
          ] do
        html = render_entry(template, entry(@typed))

        assert active_elements(html) == [], template
        assert html =~ "&lt;img", template
      end
    end

    test "leaves typed markup as text through a capture of the value alone" do
      html = render_entry("{% capture c %}{{ entry.intro }}{% endcapture %}{{ c | raw }}", entry(@typed))

      assert active_elements(html) == []
      assert html =~ "&lt;img"
    end

    test "leaves typed markup in a rich-text global as text", %{user: user} do
      preserve_cache(:globals)

      {:ok, set} =
        Brando.Sites.create_global_set(
          %{
            label: "Site",
            key: "site",
            language: "en",
            vars: [%{key: "body", label: "B", type: "rich_text", value: @typed}]
          },
          user
        )

      Brando.Cache.Globals.update({:ok, set})

      for template <- ["{{ globals.site.body | raw }}", "{% assign g = globals.site %}{{ g.body | raw }}"] do
        assert render_entry(template, entry("")) == @typed, template
        assert render(block(module!(user, template), [])) == @typed, template
      end
    end
  end

  describe "raw on rich text a filter splits" do
    test "leaves each piece of a split as text" do
      for template <- [
            ~s({{ entry.intro | split: "</p>" | first | raw }}),
            ~s({{ entry.intro | split: "<p>" | last | raw }}),
            ~s({% assign parts = entry.intro | split: "</p>" %}{{ parts[0] | raw }}),
            ~s({% assign parts = entry.intro | split: "</p>" %}{% for p in parts %}{{ p | raw }}{% endfor %})
          ] do
        html = render_entry(template, entry(@typed))

        assert active_elements(html) == [], template
        assert html =~ "&lt;img", template
      end
    end

    test "leaves each piece of a split rich-text variable as text", %{user: user} do
      template = ~s({{ body | split: "</p>" | first | raw }})
      var = %Var{key: "body", label: "B", type: :rich_text, value: @typed}
      html = render(block(module!(user, template), vars: [var]))

      assert active_elements(html) == []
      assert html =~ "&lt;img"
    end

    test "marks the text items of nested lists" do
      Brando.Villain.TemplateView.rich_text_scope(fn ->
        rich = Brando.Villain.TemplateView.read_as_rich_text("&lt;b&gt;")
        [[a], b, 1] = Brando.Villain.TemplateView.keep_rich_text([["&lt;i&gt;"], "&amp;", 1], [rich])

        assert Brando.Villain.TemplateView.read_as_rich_text?(a)
        assert Brando.Villain.TemplateView.read_as_rich_text?(b)
      end)
    end
  end

  describe "marks" do
    alias Brando.Villain.TemplateView

    setup do
      clear_marks()
      :ok
    end

    defp clear_marks do
      for {{TemplateView, _} = key, _} <- Process.get(), do: Process.delete(key)
    end

    defp marks, do: for({{TemplateView, _}, %MapSet{} = value} <- Process.get(), do: value)

    test "text with nothing for raw to decode is not marked" do
      TemplateView.read_as_rich_text("")
      TemplateView.read_as_rich_text("<p>plain</p>")

      refute TemplateView.read_as_rich_text?("")
      refute TemplateView.read_as_rich_text?("<p>plain</p>")
      assert TemplateView.read_as_rich_text?(TemplateView.read_as_rich_text("<p>&amp;</p>"))
    end

    test "an empty rich-text field leaves raw decoding other text" do
      entry = %Entry{title: "<em>Hi</em>", intro: "<p></p>"}

      for template <- [
            ~s({{ entry.title | replace: "zz", "" | raw }}),
            ~s({{ entry.title | default: "" | raw }}),
            ~s({{ entry.title | truncate: 50, "" | raw }}),
            ~s({% assign s = "" %}{{ s | append: entry.title | raw }})
          ] do
        assert render_entry("{{ entry.intro | strip_html }}" <> template, entry) == "<em>Hi</em>", template
      end
    end

    test "an empty rich-text variable is not marked", %{user: user} do
      template = ~s({{ body }}{{ entry.title | default: "" | raw }})
      var = %Var{key: "body", label: "B", type: :rich_text, value: ""}
      page = %Page{title: "<em>Hi</em>", language: :en}

      assert render(block(module!(user, template), vars: [var]), page) == "<em>Hi</em>"
    end

    test "reaching the cap keeps the newest marks" do
      for n <- 1..998, do: TemplateView.read_as_rich_text("&amp;#{n}")
      new = for n <- 1..3, do: TemplateView.read_as_rich_text("&lt;new#{n}&gt;")

      assert Enum.all?(new, &TemplateView.read_as_rich_text?/1)

      # And the memory stays bounded
      for n <- 1..5_000, do: TemplateView.read_as_rich_text("&amp;more#{n}")
      assert marks() |> Enum.map(&MapSet.size/1) |> Enum.sum() <= 2_000
    end

    test "rendering Markdown leaves no marks", %{user: user} do
      module = module!(user, "{{ body }}{% for row in block.table_rows %}{{ row.vars[0].value }}{% endfor %}")
      var = %Var{key: "body", label: "B", type: :rich_text, value: @typed}

      blocks = [
        %{block: block(module, vars: [var], table_rows: [%TableRow{vars: [%{var | key: "row"}]}])}
      ]

      assert Brando.Villain.Markdown.render(blocks, %Page{title: "T", language: :en}) =~ "img"
      assert marks() == []
    end
  end

  describe "raw on a caption" do
    test "leaves typed markup in a picture ref's title as text", %{user: user} do
      ref = %Ref{
        name: "pic",
        uid: Utils.generate_uid(),
        active: true,
        data: %Brando.Villain.Blocks.PictureBlock{
          type: "picture",
          data: %Brando.Villain.Blocks.PictureBlock.Data{title: @typed}
        }
      }

      html = render(block(module!(user, "{{ refs.pic.data.data.title | raw }}"), refs: [ref]))

      assert active_elements(html) == []
      assert html =~ "&lt;img"
    end

    test "leaves typed markup in an image's title as text" do
      image = Factory.build(:image, %{title: @typed})
      context = Villain.get_base_context(%Page{title: "T", language: :en, meta_image: image})
      html = Villain.parse_and_render("{{ entry.meta_image.title | raw }}", context)

      assert active_elements(html) == []
      assert html =~ "&lt;img"
    end
  end

  describe "raw on other text, as before" do
    test "decodes a plain field into its markup", %{user: user} do
      page = %Page{title: "<em>Hi</em> &amp; more", language: :en}
      assert render(block(module!(user, "{{ entry.title | raw }}"), []), page) == "<em>Hi</em> & more"
      assert render_entry("{{ entry.title | raw }}", %Entry{title: "<em>Hi</em>"}) == "<em>Hi</em>"
    end

    test "decodes a plain field after a filter and through assign" do
      entry = %Entry{title: "<em>Hi</em>"}
      assert render_entry("{{ entry.title | truncate: 100 | raw }}", entry) == "<em>Hi</em>"
      assert render_entry("{% assign t = entry.title %}{{ t | raw }}", entry) == "<em>Hi</em>"
    end

    test "decodes text the template built" do
      assert render_entry(~s({% assign s = "&lt;b&gt;x&lt;/b&gt;" %}{{ s | raw }}), entry("")) == "<b>x</b>"

      # Text a template captured is new text, built from what it printed
      assert render_entry("{% capture c %}{{ entry.title }}{% endcapture %}{{ c | raw }}", %Entry{title: "<b>x</b>"}) ==
               "<b>x</b>"
    end

    test "decodes a plain field a filter passes on beside rich text" do
      entry = %Entry{title: "<em>Hi</em>", intro: "<p>Tom &amp; Co</p>"}

      assert render_entry("{{ entry.title | default: entry.intro | raw }}", entry) == "<em>Hi</em>"

      pieces = ~s({% assign a = entry.intro | split: "</p>" %}{% assign b = entry.title | split: "|" %})
      assert render_entry(pieces <> "{% assign all = a | concat: b %}{{ all | last | raw }}", entry) == "<em>Hi</em>"
    end

    test "leaves text a filter joined from rich text and a plain field whole" do
      html = render_entry("{{ entry.intro | append: entry.title | raw }}", %{entry(@typed) | title: "<em>Hi</em>"})

      assert active_elements(html) == []
      assert html =~ "&lt;em&gt;Hi&lt;/em&gt;"
    end

    test "decodes a plain image title, which is escaped when read" do
      image = Factory.build(:image, %{title: "<small>2024</small> R&D"})
      context = Villain.get_base_context(%Page{title: "<small>2024</small> R&D", language: :en, meta_image: image})

      assert Villain.parse_and_render("{{ entry.meta_image.title | raw }}", context) == "<small>2024</small> R&D"
      # Read first without `raw`, it leaves the same text in another field decoding
      template = "{{ entry.meta_image.title }}|{{ entry.title | raw }}"
      assert Villain.parse_and_render(template, context) =~ "|<small>2024</small> R&D"
    end

    test "decodes rich text a template captured with other text around it" do
      html = render_entry("{% capture c %}<div>{{ entry.intro }}</div>{% endcapture %}{{ c | raw }}", entry(@typed))
      assert [_] = active_elements(html)
    end

    test "a project's filter returning {:safe, html} decodes as before" do
      context = %{Villain.get_base_context(entry(@typed)) | filter_module: ProjectFilters}
      assert Villain.parse_and_render("{{ entry.intro | as_safe | raw }}", context) == "<b>bold</b>"
    end
  end

  describe "without raw, as before" do
    test "rich text prints as it is read" do
      html = Brando.RichText.render_html(@typed)
      assert render_entry("{{ entry.intro }}", entry(@typed)) == html
      assert render_entry("{{ entry.quotes[0].text }}", entry(@typed)) == html
      assert render_entry("{% assign x = entry.intro %}{{ x }}", entry(@typed)) == html
      assert render_entry("{{ entry.intro | truncate: 100 }}", entry(@typed)) == html
      assert render_entry("{{ entry.intro | truncate: 20 }}", entry(@typed)) == "<p>&lt;img src=x ..."
      assert render_entry("{{ entry.intro | strip_html }}", entry(@typed)) == "&lt;img src=x onerror=alert(1)&gt;"
    end

    test "a plain field prints escaped" do
      assert render_entry("{{ entry.title }}", %Entry{title: "<em>Hi</em>"}) == "&lt;em&gt;Hi&lt;/em&gt;"
    end
  end
end
