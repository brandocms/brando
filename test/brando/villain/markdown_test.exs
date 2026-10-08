defmodule Brando.Villain.MarkdownTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Villain.Markdown
  alias Brando.Villain.Markdown.HTML

  setup do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user)
    {:ok, %{user: user, image: image}}
  end

  defp module!(code, opts \\ []) do
    params =
      Factory.params_for(:module, %{
        code: code,
        markdown_code: opts[:markdown],
        multi: opts[:multi] || false,
        name: "Test module",
        help_text: "Help",
        namespace: "all",
        class: "test",
        refs: [],
        vars: []
      })

    {:ok, module} = Brando.Content.create_module(params, :system)
    module
  end

  defp ref(name, type, data, extra \\ %{}) do
    Map.merge(%{name: name, description: nil, uid: Brando.Utils.generate_uid(), data: %{type: type, data: data}}, extra)
  end

  defp block(module, refs, opts \\ []) do
    %{
      type: opts[:type] || :module,
      module_id: module.id,
      uid: Brando.Utils.generate_uid(),
      active: Keyword.get(opts, :active, true),
      multi: opts[:multi] || false,
      children: opts[:children] || [],
      refs: refs,
      vars: opts[:vars] || []
    }
  end

  defp render(blocks), do: blocks |> Enum.map(&%{block: &1}) |> Markdown.render(%Brando.Pages.Page{language: "en"})

  describe "default per ref type" do
    test "rich text keeps its emphasis, links and lists, headings are headings" do
      module =
        module!(~s(<section class="intro">{% ref refs.title %}<div class="body">{% ref refs.text %}</div></section>))

      markdown =
        render([
          block(module, [
            ref("title", "header", %{text: "Key figures", level: 2}),
            ref("text", "text", %{
              text:
                ~s(<p>The <strong>tiled</strong> pools, see <a href="/rooms">rooms</a>.</p><ul><li>Floor area: 8,400 m²</li><li>Rooms: 221</li></ul>),
              type: :paragraph
            })
          ])
        ])

      assert markdown ==
               """
               ## Key figures

               The **tiled** pools, see [rooms](#{Brando.Utils.hostname("/rooms")}).

               - Floor area: 8,400 m²
               - Rooms: 221\
               """
    end

    test "a picture is an image with its alt text and caption", %{image: image} do
      module = module!("<figure>{% ref refs.cover %}</figure>")

      markdown =
        render([
          block(module, [
            ref("cover", "picture", %Brando.Villain.Blocks.PictureBlock.Data{alt: "The pool", title: "The old pool"}, %{
              image_id: image.id,
              image: image
            })
          ])
        ])

      assert markdown =~ ~r/^!\[The pool\]\(http[^)]+\/media\/image\/[^)]+\.jpg\)\n\n\*The old pool\*$/
    end

    test "videos are links, and what a reader cannot use is left out" do
      module = module!("{% ref refs.video %}{% ref refs.svg %}{% ref refs.map %}<form><button>Book</button></form>")

      markdown =
        render([
          block(module, [
            ref("video", "video", %{type: :youtube, remote_id: "abc123", title: "A tour"}),
            ref("svg", "svg", %{code: "<svg><text>logo</text></svg>"}),
            ref("map", "map", %{embed_url: "https://maps.example.com", source: :gmaps})
          ])
        ])

      assert markdown == "[A tour](https://www.youtube.com/watch?v=abc123)"
    end

    test "variables printed by the HTML template are kept" do
      module = module!(~s(<div class="member"><h3>{{ member_name }}</h3><p>{{ member_role }}</p></div>))

      vars = [
        %{key: "member_name", label: "Name", type: :string, value: "Kari Nordmann"},
        %{key: "member_role", label: "Role", type: :string, value: "Architect"}
      ]

      assert render([block(module, [], vars: vars)]) == "### Kari Nordmann\n\nArchitect"
    end

    test "text that looks like Markdown is escaped" do
      module = module!("{% ref refs.text %}")
      markdown = render([block(module, [ref("text", "text", %{text: "<p># not a heading *really*</p>"})])])
      assert markdown == "\\# not a heading \\*really\\*"
    end
  end

  describe "markdown template" do
    test "renders instead of the HTML, with refs as Markdown and variables" do
      module =
        module!("<div>{% ref refs.text %}</div>",
          markdown: "## {{ heading }}\n\n{% ref refs.text %}\n\n- Rooms: {{ rooms }}"
        )

      vars = [
        %{key: "heading", label: "Heading", type: :string, value: "Facts"},
        %{key: "rooms", label: "Rooms", type: :string, value: "221"}
      ]

      markdown =
        render([block(module, [ref("text", "text", %{text: "<p>A <em>restored</em> bathhouse.</p>"})], vars: vars)])

      assert markdown == "## Facts\n\nA *restored* bathhouse.\n\n- Rooms: 221"
    end
  end

  describe "structure" do
    test "containers render their children, inactive blocks are left out" do
      module = module!("{% ref refs.text %}")
      first = block(module, [ref("text", "text", %{text: "<p>First</p>"})])
      hidden = block(module, [ref("text", "text", %{text: "<p>Hidden</p>"})], active: false)
      second = block(module, [ref("text", "text", %{text: "<p>Second</p>"})])

      container = %{
        type: :container,
        uid: Brando.Utils.generate_uid(),
        active: true,
        palette_id: nil,
        container_id: nil,
        anchor: nil,
        children: [first, hidden, second]
      }

      assert render([container]) == "First\n\nSecond"
    end

    test "a multi module renders its entries within its own template" do
      child = module!(~s(<li>{{ item }}</li>))
      parent = module!(~s(<section><h2>{{ heading }}</h2><ul>{{ content }}</ul></section>), multi: true)

      children =
        for item <- ["One", "Two"] do
          child
          |> block([], type: :module_entry, vars: [%{key: "item", label: "Item", type: :string, value: item}])
        end

      parent_block =
        block(parent, [],
          multi: true,
          children: children,
          vars: [%{key: "heading", label: "Heading", type: :string, value: "List"}]
        )

      assert render([parent_block]) == "## List\n\n- One\n- Two"
    end
  end

  describe "HTML conversion" do
    test "tables, quotes, code and line breaks" do
      html = """
      <blockquote><p>Quoted</p></blockquote>
      <table><tr><th>Room</th><th>Size</th></tr><tr><td>Suite</td><td>40 m²</td></tr></table>
      <pre><code>mix test</code></pre>
      <p>One<br>Two</p>
      """

      assert HTML.to_markdown(html) ==
               "> Quoted\n\n| Room | Size |\n| --- | --- |\n| Suite | 40 m² |\n\n    mix test\n\nOne\\\nTwo"
    end

    test "lazy images use their real source, scripts and navigation are dropped" do
      html =
        ~s[<nav><a href="/">Home</a></nav><img src="data:image/gif;base64,R0" data-src="https://cdn.example.com/a.jpg" alt="A"><script>alert(1)</script>]

      assert HTML.to_markdown(html) == "![A](https://cdn.example.com/a.jpg)"
    end

    test "an exclamation mark is only escaped where it would start an image" do
      assert HTML.to_markdown("<h1>Welcome!</h1><p>Not an image: ![x](y)</p>") ==
               "# Welcome!\n\nNot an image: !\\[x\\](y)"
    end

    test "already written Markdown passes through" do
      assert HTML.to_markdown("<div><p>Intro</p><brando-markdown>## Kept\n\n- *as is*</brando-markdown></div>") ==
               "Intro\n\n## Kept\n\n- *as is*"
    end
  end
end
