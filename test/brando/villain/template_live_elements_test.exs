defmodule Brando.Villain.TemplateLiveElementsTest do
  @moduledoc """
  Text an editor typed reaches the public page as text. Three ways it could
  come out as a live element: `raw` on a field that stores rendered blocks,
  `url_decode` on rich text, and a picture's or image's title holding markup
  the caption editor does not make.
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

    test "decodes plain text as before" do
      assert render_entry("{{ entry.title | url_decode }}", %Entry{title: "Tom%20%26%20Jerry"}) == "Tom & Jerry"
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
            ~s(<h2 class="lead">A</h2><ul><li>b</li></ul><p><span style="color: #ff0000;">c</span><sub>1</sub><sup>2</sup></p>)
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
    end

    test "a title without the editor's markup is text, as before" do
      assert Captions.caption_html("Fish & <chips>") == "Fish &amp; &lt;chips&gt;"
      assert Captions.caption_html(~s(<img src="x">)) == "&lt;img src=&quot;x&quot;&gt;"
    end
  end
end
