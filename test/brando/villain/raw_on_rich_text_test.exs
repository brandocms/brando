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
