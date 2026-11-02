defmodule Brando.Villain.InertEditorTextTest do
  @moduledoc """
  What editors write reaches the page as text or sanitized rich text, never as
  Liquid; what Liquid reads of entry data prints as text unless a template opts
  in; and credentials never reach a template.
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
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.Blocks.MarkdownBlock
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Brando.Villain.TemplateView

  defmodule ProjectFilters do
    @moduledoc false
    use Brando.Villain.Filters

    def load_page(_key, _context), do: Process.get(:project_filter_page)
    def load_pages(_key, _context), do: [Process.get(:project_filter_page)]
    def load_settings(_key, _context), do: Process.get(:project_filter_settings)
    def settings_for(_block, _context), do: Process.get(:project_filter_settings)
    def wrapped_settings_for(block, context), do: TemplateView.wrap(settings_for(block, context))
  end

  # An image with a handler, percent-encoded so a sanitizer sees only text. Its
  # handler sets a marker and nothing else.
  @encoded "%3Cimg%20src%3Dx%20onerror%3D%22document.title%3D1%22%3E"
  @payload "{{ '#{@encoded}' | url_decode }}"
  @hash "$2b$12$dummy.stored.value.for.a.test"
  @markup_title ~s(<img src=x onerror="document.title=1">)

  setup do
    user = Factory.insert(:random_user)

    {:ok, _} =
      user
      |> Ecto.Changeset.change(password: @hash)
      |> Brando.Repo.update()

    user = Brando.Repo.get!(Brando.Users.User, user.id)
    {:ok, %{user: user}}
  end

  defp module!(user, code, attrs \\ %{}) do
    {:ok, module} = Content.create_module(Factory.params_for(:module, Map.merge(%{code: code}, attrs)), user)
    module
  end

  defp block(module, attrs) do
    struct(
      %Block{type: :module, active: true, module_id: module.id, uid: Utils.generate_uid(), vars: [], refs: []},
      attrs
    )
  end

  defp ref(name, data), do: %Ref{name: name, uid: Utils.generate_uid(), active: true, data: data}
  defp text_ref(text), do: ref("text", %TextBlock{type: "text", data: %TextBlock.Data{text: text, type: "paragraph"}})

  defp active_elements(html) do
    html |> Floki.parse_fragment!() |> Floki.find("img[onerror], script")
  end

  defp render(blocks, entry \\ %Page{title: "T", language: :en}) do
    Villain.parse(Enum.map(List.wrap(blocks), &%{block: &1}), entry)
  end

  # A template renders in a module and in the final pass (a container's code)
  defp in_module_and_final_pass(user, code, entry) do
    in_module = render(block(module!(user, code), []), entry)

    {:ok, container} =
      Content.create_container(
        %{name: "Final pass", namespace: "all", help_text: "x", code: "<div>" <> code <> "</div>{{ content }}"},
        user
      )

    container_block = %Block{
      type: :container,
      active: true,
      container_id: container.id,
      uid: Utils.generate_uid(),
      children: [],
      vars: [],
      refs: []
    }

    [in_module, render(container_block, entry)]
  end

  describe "editor text" do
    test "a text ref runs no Liquid", %{user: user} do
      html = render(block(module!(user, "{% ref refs.text %}"), refs: [text_ref("<p>#{@payload}</p>")]))

      assert active_elements(html) == []
      assert Floki.text(Floki.parse_fragment!(html)) == @payload
    end

    test "a Markdown ref runs no Liquid", %{user: user} do
      data = %MarkdownBlock{type: "markdown", data: %MarkdownBlock.Data{text: "Some #{@payload}"}}
      html = render(block(module!(user, "{% ref refs.md %}"), refs: [ref("md", data)]))

      assert active_elements(html) == []
      refute html =~ "{{"
      assert Floki.text(Floki.parse_fragment!(html)) =~ "url_decode"
    end

    test "a rich_text var runs no Liquid", %{user: user} do
      var = %Var{key: "body", label: "Body", type: :rich_text, value: "<p>#{@payload}</p>"}

      for code <- ["{{ body }}", "{% if body %}{{ body }}{% endif %}"] do
        html = render(block(module!(user, code), vars: [var]))

        assert active_elements(html) == []
        assert Floki.text(Floki.parse_fragment!(html)) == @payload
      end
    end

    test "a rich_text var in a multi module's entry and a table row runs no Liquid", %{user: user} do
      var = %Var{key: "body", label: "Body", type: :rich_text, value: "<p>#{@payload}</p>"}
      child_module = module!(user, "{{ body }}")
      parent = module!(user, "{{ content }}{% for e in entries %}{{ e.vars.body }}{% endfor %}")

      child = block(child_module, type: :module_entry, vars: [var])
      html = render(block(parent, multi: true, children: [child]))

      assert active_elements(html) == []
      assert html =~ "<p>&#123;&#123;"

      row = %TableRow{vars: [var]}
      code = "{% for row in block.table_rows %}{{ row.body }}|{{ row.vars[0].value }}{% endfor %}"
      html = render(block(module!(user, code), table_rows: [row]))

      assert active_elements(html) == []
      assert [_, _] = html |> Floki.parse_fragment!() |> Floki.find("p")
      refute html =~ "{{"
      refute html =~ "&lt;p"
    end

    test "a picture's caption runs no Liquid, with and without its own alt", %{user: user} do
      image = Factory.insert(:image, creator: user)

      for alt <- ["Alt", nil] do
        data = %PictureBlock{type: "picture", data: %PictureBlock.Data{title: "<p>#{@payload}</p>", alt: alt}}
        picture = %{ref("pic", data) | image_id: image.id, image: image}
        html = render(block(module!(user, "{% ref refs.pic %}"), refs: [picture]))

        assert active_elements(html) == []
        refute html =~ "Error parsing"
        refute html =~ "{{"
      end
    end

    test "Liquid in text a page never showed as Liquid costs the render no parse", %{user: user} do
      html = render(block(module!(user, "{% ref refs.text %}"), refs: [text_ref("<p>{% if unclosed %}</p>")]))

      refute html =~ "Error parsing"
      assert Floki.text(Floki.parse_fragment!(html)) == "{% if unclosed %}"
    end
  end

  describe "credentials" do
    test "no path prints a password hash", %{user: user} do
      var = %Var{key: "x", label: "X", type: :string, value: "v", creator: user}

      entry = %Page{
        title: "T",
        language: :en,
        updated_by: user,
        creator: user,
        vars: [var]
      }

      templates = [
        "{{ entry.updated_by.password }}",
        "{{ entry.creator.password }}",
        "{{ entry.vars[0].creator.password }}",
        "{% for v in entry.vars %}{{ v.creator.password }}{% endfor %}",
        "{% assign u = entry.updated_by %}{{ u.password }}",
        "{{ entry.vars | first | default: entry.updated_by | size }}",
        "{% assign users = entry.vars | map: 'creator' %}{{ users | map: 'password' }}",
        "{{ entry.vars | map: 'creator' | map: 'password' }}",
        "{% inspect entry %}",
        "{% inspect entry.updated_by %}",
        "{% inspect entry.vars %}",
        "{{ entry | inspect }}",
        "{{ entry.updated_by | inspect }}"
      ]

      for code <- templates, html <- in_module_and_final_pass(user, code, entry) do
        refute html =~ @hash, "#{code} printed the hash"
        refute html =~ "dummy.stored"
      end
    end

    test "a link or media var's creator is no way to a hash", %{user: user} do
      image = Factory.insert(:image, creator: user)

      vars = [
        %Var{key: "cta", label: "C", type: :link, link_type: :url, value: "/a", creator: user},
        %Var{key: "pic", label: "P", type: :image, image_id: image.id, image: %{image | creator: user}}
      ]

      for code <- ["{{ cta.creator.password }}", "{{ pic.creator.password }}", "{% inspect cta %}", "{% inspect pic %}"] do
        html = render(block(module!(user, code), vars: vars))
        refute html =~ @hash, "#{code} printed the hash"
      end
    end

    test "what a template may read of a user still prints", %{user: user} do
      entry = %Page{title: "T", language: :en, creator: user}
      html = render(block(module!(user, "{{ entry.creator.name }}|{{ entry.creator.last_login }}"), []), entry)

      assert html =~ user.name <> "|"
    end

    test "a camelCase key from JSON is hidden too, and a word that only holds one is not" do
      view = TemplateView.wrap(%{"accessToken" => "t", "clientSecret" => "s", "apiKey" => "k", "secretary" => "n"})
      context = Villain.create_context(%{"x" => view})
      eval = fn key -> Liquex.Argument.eval({:field, [key: "x", key: key]}, context) |> elem(0) end

      assert eval.("accessToken") == nil
      assert eval.("clientSecret") == nil
      assert eval.("apiKey") == nil
      assert eval.("secretary") == "n"
    end

    test "no struct shows a field named like a credential" do
      view = TemplateView.wrap(%{api_key: "k", name: "n", access_token: "t", nested: %{client_secret: "s"}})
      context = Villain.create_context(%{"x" => view})

      eval = fn keys ->
        keys |> Enum.map(&{:key, &1}) |> then(&Liquex.Argument.eval({:field, [{:key, "x"} | &1]}, context)) |> elem(0)
      end

      assert eval.(["name"]) == "n"
      assert eval.(["api_key"]) == nil
      assert eval.(["access_token"]) == nil
      assert eval.(["nested", "client_secret"]) == nil
      assert TemplateView.unwrap(view).api_key == nil
    end
  end

  describe "entry data in Liquid" do
    @markup ~s(<img src=x onerror="document.title=1">)

    test "prints as text in a module and in the final pass", %{user: user} do
      entry = %Page{title: "#{@markup} {{ 1 | plus: 1 }}", language: :en}

      for html <- in_module_and_final_pass(user, "<h1>{{ entry.title }}</h1>", entry) do
        assert active_elements(html) == []
        assert Floki.text(Floki.parse_fragment!(html)) =~ "#{@markup} {{ 1 | plus: 1 }}"
      end
    end

    test "stays text through filters, assign and loops", %{user: user} do
      child = %Page{title: @markup, language: :en}
      entry = %Page{title: @markup, language: :en, children: [child]}

      for code <- [
            "{{ entry.title | upcase }}",
            "{% assign t = entry.title %}{{ t }}",
            "{% for c in entry.children %}{{ c.title }}{% endfor %}",
            "{{ entry.children | map: 'title' | join: ',' }}",
            "{% assign c = entry.children | first %}{{ c.title }}",
            "{{ entry.children | sort: 'title' | map: 'title' }}"
          ],
          html <- in_module_and_final_pass(user, code, entry) do
        assert active_elements(html) == [], "#{code} made markup"
      end
    end

    test "a character reference in a title is the character it names", %{user: user} do
      entry = %Page{title: "Fjell&shy;vann &amp; sjø", language: :en}
      html = render(block(module!(user, "{{ entry.title }}"), []), entry)

      assert html == "Fjell\u00ADvann &amp; sjø"
    end

    test "escape never escapes twice", %{user: user} do
      entry = %Page{title: ~s(R&D "x"), language: :en}
      html = render(block(module!(user, "{{ entry.title | escape }}"), []), entry)

      assert Floki.text(Floki.parse_fragment!("<p>#{html}</p>")) == ~s(R&D "x")
    end

    test "the raw filter is the opt-in, and Liquid stays text", %{user: user} do
      entry = %Page{title: "<em>Hi</em> {{ 1 | plus: 1 }}", language: :en}

      for html <- in_module_and_final_pass(user, "{{ entry.title | raw }}", entry) do
        assert html =~ "<em>Hi</em> &#123;{ 1 | plus: 1 }}"
      end
    end

    test "raw keeps Liquid in a script element from running", %{user: user} do
      entry = %Page{title: "<script>{{ 1 | plus: 1 }}</script>", language: :en}
      html = render(block(module!(user, "{{ entry.title | raw }}"), []), entry)

      refute html =~ "{{"
      refute html =~ ">2<"
    end

    test "a rich-text field prints its markup, sanitized and without running Liquid", %{user: user} do
      assert :meta_description not in Page.__rich_text_fields__()
      field = hd(Page.__rich_text_fields__() ++ [:not_declared])

      if field != :not_declared do
        entry =
          Map.put(%Page{language: :en}, field, ~s(<p>Text <strong>bold</strong> <script>x</script>{{ 1 | plus: 1 }}</p>))

        html = render(block(module!(user, "{{ entry.#{field} }}"), []), entry)

        assert html =~ "<strong>bold</strong>"
        refute html =~ "<script"
        assert html =~ "&#123;&#123; 1"
      end
    end

    test "identity and refs read as data print as text", %{user: user} do
      Brando.Cache.Identity.set()
      identity = Brando.Cache.get_site(:identity)
      updated = put_in(identity["en"].name, @markup)
      Brando.Cache.put(:identity, updated, :infinite)
      on_exit(fn -> Brando.Cache.put(:identity, identity, :infinite) end)

      html = render(block(module!(user, "{{ identity.name }}"), []))
      assert active_elements(html) == []
      assert Floki.text(Floki.parse_fragment!(html)) == @markup

      refs = [
        ref("h", %Brando.Villain.Blocks.HeaderBlock{
          type: "header",
          data: %Brando.Villain.Blocks.HeaderBlock.Data{text: @markup, level: 2}
        }),
        text_ref("<p>rich <strong>text</strong></p>")
      ]

      html = render(block(module!(user, "{{ refs.h.data.data.text }}|{{ refs.text.data.data.text }}"), refs: refs))
      assert active_elements(html) == []
      assert html =~ "|<p>rich <strong>text</strong></p>"
    end

    test "navigation and request print as text", %{user: user} do
      conn = %Plug.Conn{path_params: %{"slug" => @markup}, request_path: "/x"}
      code = "{{ request.params.slug }}"
      html = Villain.parse([%{block: block(module!(user, code), [])}], %Page{language: :en}, conn: conn)

      assert active_elements(html) == []
      assert Floki.text(Floki.parse_fragment!(html)) == @markup
    end

    test "a block's description and anchor print as text", %{user: user} do
      html =
        render(
          block(module!(user, "{{ block.description }}{{ block.anchor }}"),
            description: @markup,
            anchor: "{{ 1 | plus: 1 }}"
          )
        )

      assert active_elements(html) == []
      refute html =~ "{{"
    end
  end

  describe "second review" do
    test "strip_html keeps a value inside its attribute", %{user: user} do
      entry = %Page{title: ~s(" onmouseover="document.title=1), language: :en}
      html = render(block(module!(user, ~s(<a title="{{ entry.title | strip_html }}">x</a>)), []), entry)

      assert html |> Floki.parse_fragment!() |> Floki.find("a[onmouseover]") == []
    end

    test "strip_html keeps text a rich-text field wrote as entities", %{user: user} do
      refs = [text_ref("<p>Use the &lt;title&gt; element</p>")]
      html = render(block(module!(user, "{{ refs.text.data.data.text | strip_html }}"), refs: refs))

      assert html =~ "title"
      assert html =~ "element"
    end

    test "raw leaves script, style and JSON working", %{user: user} do
      for value <- ["<style>.x{color:red}</style>", ~s(<script type="application/ld+json">{"a":{"b":1}}</script>)] do
        html = render(block(module!(user, "{{ entry.title | raw }}"), []), %Page{title: value, language: :en})

        assert html == value
      end
    end

    test "the strictest view decides what a filter's result prints as", %{user: user} do
      row = %Brando.Content.TableRow{vars: []}
      child = %Page{title: ~s(<img src=x onerror="document.title=1">), language: :en}
      entry = %Page{language: :en, children: [child]}
      code = ~s({{ block.table_rows | concat: entry.children | map: "title" | join: "" }})
      html = render(block(module!(user, code), table_rows: [row]), entry)

      assert active_elements(html) == []
    end

    test "truncate drops only a partial character reference", %{user: user} do
      code = ~s({{ "AT&T Mobile" | truncate: 7 }}|{{ entry.title | truncate: 7 }})
      html = render(block(module!(user, code), []), %Page{title: "AB & CD EF", language: :en})

      assert html == "AT&T...|AB ..."
    end

    test "other spellings of a credential are hidden" do
      keys =
        ~w(passwordhash hashedpassword accesstoken authtoken clientsecret secretkey secrets api_keys api-key x-api-key)

      view = TemplateView.wrap(Map.new(keys, &{&1, "v"}))
      context = Villain.create_context(%{"x" => view})

      for key <- keys do
        assert Liquex.Argument.eval({:field, [key: "x", key: key]}, context) |> elem(0) == nil, key
      end
    end
  end

  describe "what keeps working" do
    test "picture and video tags read the record, not escaped text", %{user: user} do
      image = Factory.insert(:image, creator: user, alt: %{"en" => "A & B"})
      entry = %Page{title: "T", language: :en} |> Map.put(:cover, image)

      html = render(block(module!(user, "{% picture entry.cover { lazyload: false, alt: entry.title } %}"), []), entry)

      assert [_ | _] = html |> Floki.parse_fragment!() |> Floki.find("img")
      refute html =~ "&amp;amp;"
    end

    test "a filter on a record gets the record", %{user: user} do
      image = Factory.insert(:image, creator: user, alt: %{"en" => "Alt <b>"})
      entry = Map.put(%Page{title: "T", language: :en}, :cover, image)

      html =
        render(
          block(module!(user, "{{ entry.cover | media_url }}|{{ entry.cover.alt | i18n }}|{{ entry.cover.width }}"), []),
          entry
        )

      assert html =~ image.path
      assert html =~ "|Alt &lt;b&gt;|"
    end

    test "route tags read the value, for the helper to encode", %{user: user} do
      entry = %Page{uri: "it's", language: :en}

      html = render(block(module!(user, "{% route page_path show { entry.uri } %}"), []), entry)

      refute html =~ "&#39;"
      refute html =~ "%26"
    end

    test "route_i18n reads the entry's language and value", %{user: user} do
      entry = %Page{uri: "about", language: :en}

      html = render(block(module!(user, "{% route_i18n entry.language page_path show { entry.uri } %}"), []), entry)

      assert html =~ "about"
    end

    test "a video tag reads the record", %{user: user} do
      video =
        Factory.insert(:video,
          creator: user,
          type: :bunny,
          status: :ready,
          meta: %{"bunny" => %{"video_guid" => "guid-for-a-test"}},
          title: "R&D"
        )

      entry = Map.put(%Page{title: "T", language: :en}, :video, video)

      html = render(block(module!(user, "{% video entry.video { autoplay: true } %}"), []), entry)

      assert html =~ "guid-for-a-test"
      refute html =~ "&amp;amp;"
    end

    test "a t tag and a form tag read as before", %{user: user} do
      html = render(block(module!(user, "{% t en 'Read more' %}{% t no 'Les mer' %}"), []))

      assert html == "Read more"
    end

    test "a datasource's entries print as text, and read as records", %{user: user} do
      child = %Page{id: 9, title: ~s(<img src=x onerror="document.title=1">), uri: "x", language: :en, creator: user}
      context = Villain.get_base_context(%Page{language: :en})
      entries = TemplateView.wrap_for([child], context)

      {:ok, parsed} =
        Liquex.parse(
          ~s({% for e in entries %}{{ e.title }}{{ e.creator.password }}{% endfor %}{{ entries \| map: 'uri' \| join: ',' }}),
          Brando.Villain.LiquexParser
        )

      {result, _} = Liquex.Render.render!([], parsed, Liquex.Context.assign(context, :entries, entries))
      html = Enum.join(result)

      assert active_elements(html) == []
      assert html =~ "&lt;img"
      assert html =~ "x"
      refute html =~ @hash
    end

    test "json_ld reads the records it is given", %{user: _user} do
      context = Villain.get_base_context(%Page{language: :en})
      entries = TemplateView.wrap_for([%Page{id: 1, title: "A", uri: "a", language: :en}], context)

      html = Brando.Villain.Filters.apply(entries, {:filter, ["json_ld", {:arguments, []}]}, context)

      assert html =~ "application/ld+json"
    end

    test "a published fragment's Liquid has had its pass: it prints as text in the page", %{user: user} do
      {:ok, fragment} =
        Brando.Pages.create_fragment(
          %{parent_key: "p", key: "k", language: "en", status: :published, creator_id: user.id, entry_blocks: []},
          user
        )

      {:ok, fragment} =
        fragment |> Ecto.Changeset.change(rendered_blocks: "<p>{{ 1 | plus: 41 }}</p>") |> Brando.Repo.update()

      html =
        render(%Block{
          type: :fragment,
          active: true,
          fragment_id: fragment.id,
          uid: Utils.generate_uid(),
          vars: [],
          refs: []
        })

      refute html =~ "42"
      assert Floki.text(Floki.parse_fragment!(html)) == "{{ 1 | plus: 41 }}"
    end

    test "an HTML ref's template still runs its own Liquid", %{user: user} do
      data = %Brando.Villain.Blocks.HtmlBlock{
        type: "html",
        data: %Brando.Villain.Blocks.HtmlBlock.Data{text: ~s(<div data-t="{{ entry.title }}"></div>)}
      }

      entry = %Page{title: "Mine", language: :en}

      assert render(block(module!(user, "{% ref refs.embed %}"), refs: [ref("embed", data)]), entry) =~ ~s(data-t="Mine")

      heex = module!(user, ~S|<.ref block={@block} ref={:embed} />|, %{type: :heex})
      assert render(block(heex, refs: [ref("embed", data)]), entry) =~ ~s(data-t="Mine")
    end

    test "dates, comparisons, numbers and booleans read as they are", %{user: user} do
      entry = %Page{
        title: "Same",
        language: :en,
        status: :published,
        id: 7,
        publish_at: ~U[2026-01-02 03:04:05Z],
        updated_by: nil
      }

      code =
        ~s({{ entry.publish_at | date: "%Y" }}|) <>
          ~s({% if entry.title == "Same" %}eq{% endif %}|) <>
          ~s({% if entry.id > 6 %}gt{% endif %}|) <>
          ~s({% if entry.updated_by %}user{% else %}none{% endif %}|) <>
          ~s({% if entry.title contains "am" %}has{% endif %}|{{ entry.status }}|{{ entry.title | size }}|{{ entry.title.size }})

      assert render(block(module!(user, code), []), entry) == "2026|eq|gt|none|has|published|4|4"
    end

    test "url_encode and slugify read escaped text as what it stands for", %{user: user} do
      entry = %Page{title: "R&D søk", language: :en}
      code = "{{ entry.title | url_encode }}|{{ entry.title | slugify }}"

      assert render(block(module!(user, code), []), entry) == "R%26D+s%C3%B8k|r-d-sok"
    end

    test "i18n reads a map field in the page's language, escaped", %{user: user} do
      entry = Map.put(%Page{language: :en}, :meta, %{"en" => "<b>En</b>", "no" => "No"})

      assert render(block(module!(user, "{{ entry.meta | i18n }}"), []), entry) == "&lt;b&gt;En&lt;/b&gt;"
    end

    test "a map field loops as pairs", %{user: user} do
      entry = Map.put(%Page{language: :en}, :meta, %{"a" => "<b>"})
      code = "{% for p in entry.meta %}{{ p[0] }}={{ p[1] }}{% endfor %}"

      assert render(block(module!(user, code), []), entry) == "a=&lt;b&gt;"
    end

    test "an entry's URL and identifier templates read the plain value" do
      context = Villain.plain_context(%Page{title: "R&D", uri: "a&b", language: :en})

      assert Liquex.Argument.eval({:field, [key: "entry", key: "title"]}, context) |> elem(0) == "R&D"
    end

    test "HEEx reads entry data unescaped and escapes it once", %{user: user} do
      module = module!(user, ~S|<p>{@entry.title}</p>|, %{type: :heex})
      html = render(block(module, []), %Page{title: "R&D <b>", language: :en})

      assert html == "<p>R&amp;D &lt;b&gt;</p>"
    end
  end

  describe "HEEx" do
    defp heex!(user, code), do: module!(user, code, %{type: :heex})

    test "Liquid in a string var prints as text", %{user: user} do
      var = %Var{key: "title", label: "T", type: :string, value: @payload}
      html = render(block(heex!(user, ~S|<h1>{@title}</h1>|), vars: [var]))

      assert active_elements(html) == []
      refute html =~ "Error parsing"
      assert Floki.text(Floki.parse_fragment!(html)) =~ "url_decode"
    end

    test "Liquid in a rich_text var prints as text", %{user: user} do
      var = %Var{key: "body", label: "T", type: :rich_text, value: "<p>#{@payload}</p>"}
      html = render(block(heex!(user, ~S|<div>{Phoenix.HTML.raw(@body)}</div>|), vars: [var]))

      assert active_elements(html) == []
      assert Floki.text(Floki.parse_fragment!(html)) =~ "url_decode"
    end

    test "Liquid in a global prints as text", %{user: user} do
      Brando.Cache.Globals.set()
      globals = Brando.Cache.get_site(:globals)
      updated = Map.put(globals || %{}, "en", %{"site" => %{"name" => %{type: :string, value: @payload}}})
      Brando.Cache.put(:globals, updated, :infinite)
      on_exit(fn -> Brando.Cache.put(:globals, globals, :infinite) end)

      html = render(block(heex!(user, ~S|<p>{@globals["site"]["name"]}</p>|), []))

      assert active_elements(html) == []
      assert Floki.text(Floki.parse_fragment!(html)) =~ "url_decode"
    end

    test "Liquid in a value printed inside script or style does not run", %{user: user} do
      var = %Var{key: "title", label: "T", type: :string, value: "{{ 1 | plus: 41 }}"}

      for code <- [
            ~S|<script>const t = "<%= @title %>"</script>|,
            ~S|<style>/* <%= @title %> */</style>|
          ] do
        html = render(block(heex!(user, code), vars: [var]))

        refute html =~ "42"
        refute html =~ "{{"
        assert html =~ "plus: 41"
      end
    end

    test "two values cannot make a delimiter between them", %{user: user} do
      vars = [
        %Var{key: "a", label: "A", type: :string, value: "{"},
        %Var{key: "b", label: "B", type: :string, value: "{ 1 | plus: 41 }}"}
      ]

      html = render(block(heex!(user, ~S|<p>{@a}{@b}</p>|), vars: vars))

      refute html =~ "42"
      assert Floki.text(Floki.parse_fragment!(html)) == "{{ 1 | plus: 41 }}"
    end

    test "printed JSON stays JSON", %{user: user} do
      code = ~S|<script type="application/ld+json"><%= Phoenix.HTML.raw(Jason.encode!(%{a: %{b: 1}})) %></script>|
      html = render(block(heex!(user, code), []))

      assert html =~ ~s({"a":{"b":1}})
    end

    test "Liquid the module's own code holds still runs, at any depth", %{user: user} do
      own = ~S|<p title="{{ entry.title }}" phx-no-curly-interpolation>{{ entry.title }}</p>|
      entry = %Page{title: "Mine <b>", language: :en}

      assert render(block(heex!(user, own), []), entry) =~ ~s(<p title="Mine &lt;b&gt;")

      parent = module!(user, ~S|<section><.content /></section>|, %{type: :heex})
      child = block(heex!(user, own), type: :module_entry)
      html = render(block(parent, multi: true, children: [child]), entry)

      assert html =~ "Mine &lt;b&gt;"
      refute html =~ "{{"
    end
  end

  describe "Markdown alternates" do
    test "a Markdown template prints text as typed, and no credential", %{user: user} do
      module =
        module!(user, "<p>html</p>", %{
          markdown_code: "{{ entry.title }}|{{ title }}|{{ body }}|{{ entry.updated_by.password }}|{% ref refs.text %}"
        })

      vars = [
        %Var{key: "title", label: "T", type: :string, value: "A & {{ b }}"},
        %Var{key: "body", label: "B", type: :rich_text, value: "<p>c {{ d }}</p>"}
      ]

      entry = %Page{title: "R&D {{ x }}", language: :en, updated_by: user}
      md = Villain.Markdown.render([%{block: block(module, vars: vars, refs: [text_ref("<p>e {{ f }}</p>")])}], entry)

      assert md =~ "R&D {{ x }}|A & {{ b }}"
      assert md =~ "c {{ d }}"
      assert md =~ "e {{ f }}"
      refute md =~ "&#123;"
      refute md =~ @hash
    end

    test "strip_html keeps quotes as typed in a Markdown template", %{user: user} do
      module = module!(user, "<p>html</p>", %{markdown_code: "{{ entry.title | strip_html }}"})
      md = Villain.Markdown.render([%{block: block(module, [])}], %Page{title: ~s(Say "hello" it's R&D), language: :en})

      assert md =~ ~s(Say "hello" it's R&D)
      refute md =~ "&quot;"
      refute md =~ "&#39;"
    end

    test "a module without one renders its HTML, and braces come through as text", %{user: user} do
      module = module!(user, "<p>{{ entry.title }}</p>{% ref refs.text %}")
      entry = %Page{title: "R&D {{ x }}", language: :en}
      md = Villain.Markdown.render([%{block: block(module, refs: [text_ref("<p>e {{ f }}</p>")])}], entry)

      assert md =~ ~S(R\&D {{ x }})
      assert md =~ "e {{ f }}"
      refute md =~ "&#123;"
    end
  end

  describe "what a filter gives back" do
    test "a filter's text starts no Liquid, whatever it was given", %{user: user} do
      delimited = "{{ 1 | plus: 41 }}"
      child = %Page{id: 1, title: delimited, uri: "a", language: :en}
      entry = %Page{id: 2, title: delimited, language: :en, children: [child]}

      for code <- [
            "{{ entry.title | strip_html }}",
            "{{ '%7B%7B 1 | plus: 41 %7D%7D' | url_decode }}",
            "{{ entry.children | json_ld }}"
          ] do
        html = render(block(module!(user, code), []), entry)

        refute html =~ "42", "#{code} ran Liquid"
        assert html =~ "plus: 41", "#{code} printed nothing"
      end
    end

    test "{:safe, html} starts no Liquid either" do
      context = Villain.create_context(%{})

      assert TemplateView.filter_result({:safe, ["<b>", "x"]}, :x, :escape, context) == "<b>x"
      assert TemplateView.filter_result({:safe, ["<b>", "{{ x }}"]}, :x, nil, context) == "<b>&#123;{ x }}"
    end

    test "a Markdown template keeps its braces through a filter", %{user: user} do
      module = module!(user, "<p>html</p>", %{markdown_code: "{{ '%7B%7B x %7D%7D' | url_decode }}"})
      md = Villain.Markdown.render([%{block: block(module, [])}], %Page{title: "T", language: :en})

      assert md =~ "{{ x }}"
    end

    test "size, srcset, large and xlarge print picture markup", %{user: user} do
      image = Factory.insert(:image, creator: user)
      entry = Map.put(%Page{title: "T", language: :en}, :cover, image)

      for code <- [
            ~s({{ entry.cover | size: "large" }}),
            ~s({{ entry.cover | srcset: "Brando.Users.User:avatar" }}),
            "{{ entry.cover | large }}",
            "{{ entry.cover | xlarge }}"
          ] do
        html = render(block(module!(user, code), []), entry)

        assert [_ | _] = html |> Floki.parse_fragment!() |> Floki.find("picture"), "#{code} printed #{html}"
        refute html =~ "&lt;picture"
      end
    end

    test "raw on a record or a list keeps its protection", %{user: user} do
      child = %Page{title: @markup_title, language: :en, creator: user}
      entry = %Page{title: "T", language: :en, creator: user, children: [child]}

      for code <- [
            "{% assign e = entry | raw %}{{ e.creator.password }}",
            "{% assign u = entry.creator | raw %}{{ u.password }}",
            "{% assign l = entry.children | raw %}{% for c in l %}{{ c.creator.password }}{% endfor %}",
            "{% assign e = entry | raw %}{% inspect e %}"
          ] do
        html = render(block(module!(user, code), []), entry)

        refute html =~ @hash, "#{code} printed the hash"
      end

      html =
        render(
          block(module!(user, "{% assign l = entry.children | raw %}{% for c in l %}{{ c.title }}{% endfor %}"), []),
          entry
        )

      assert active_elements(html) == []
    end

    test "a filter on rows keeps how rows read", %{user: user} do
      row = %TableRow{
        vars: [
          %Var{key: "body", label: "B", type: :rich_text, value: "<p>Rich <strong>text</strong></p>"},
          %Var{key: "title", label: "T", type: :string, value: "R&D"}
        ]
      }

      code = "{% assign rows = block.table_rows | reverse %}{% for r in rows %}{{ r.body }}|{{ r.title }}{% endfor %}"

      assert render(block(module!(user, code), table_rows: [row])) == "<p>Rich <strong>text</strong></p>|R&amp;D"
    end

    test "a filter given a string that returns a record gives a view" do
      user = Factory.insert(:random_user)
      {:ok, _} = user |> Ecto.Changeset.change(password: @hash) |> Brando.Repo.update()
      user = Brando.Repo.get!(Brando.Users.User, user.id)
      Process.put(:project_filter_page, %Page{title: @markup_title, language: :en, creator: user})

      context = %{Villain.get_base_context(%Page{language: :en}) | filter_module: ProjectFilters}

      for code <- [
            ~s({% assign p = "about" | load_page %}{{ p.creator.password }}{{ p.title }}),
            ~s({% assign l = "about" | load_pages %}{% for p in l %}{{ p.creator.password }}{{ p.title }}{% endfor %})
          ] do
        {:ok, parsed} = Liquex.parse(code, Brando.Villain.LiquexParser)
        {result, _} = Liquex.Render.render!([], parsed, context)
        html = Enum.join(result)

        refute html =~ @hash
        assert active_elements(html) == []
        assert html =~ "&lt;img"
      end
    end

    # As guides/block_editor.md ("What templates read") says: a map built after
    # reading `block` comes back as the block's processed data, so the filter wraps it
    test "a plain map a filter builds from block reads as entry data once wrapped" do
      Process.put(:project_filter_settings, [%{"password" => @hash, "title" => @markup_title}])

      context =
        %{Villain.get_base_context(%Page{language: :en}) | filter_module: ProjectFilters}
        |> Liquex.Context.assign(:block, TemplateView.wrap(%{uid: "x"}, :processed))

      render = fn filter ->
        code = "{% assign l = block | #{filter} %}{% for s in l %}{{ s.password }}{{ s.title }}{% endfor %}"
        {:ok, parsed} = Liquex.parse(code, Brando.Villain.LiquexParser)
        {result, _} = Liquex.Render.render!([], parsed, context)
        IO.iodata_to_binary(result)
      end

      assert render.("settings_for") == @hash <> @markup_title

      html = render.("wrapped_settings_for")
      refute html =~ @hash
      assert active_elements(html) == []
      assert html =~ "&lt;img"
    end

    test "a plain map a filter returns reads as entry data does" do
      settings = %{
        "accessToken" => @hash,
        "title" => @markup_title,
        "nested" => %{"api_key" => @hash, "title" => @markup_title},
        "items" => [%{"password" => @hash, "title" => @markup_title}],
        atom_secret: @hash
      }

      Process.put(:project_filter_settings, settings)
      context = %{Villain.get_base_context(%Page{language: :en}) | filter_module: ProjectFilters}

      for code <- [
            ~s({% assign s = "x" | load_settings %}{{ s.accessToken }}{{ s.atom_secret }}{{ s.title }}),
            ~s({% assign s = "x" | load_settings %}{{ s.nested.api_key }}{{ s.nested.title }}),
            ~s({% assign s = "x" | load_settings %}{% for i in s.items %}{{ i.password }}{{ i.title }}{% endfor %}),
            ~s({% assign s = "x" | load_settings %}{{ s }}),
            ~s({% assign s = "x" | load_settings %}{% inspect s %}),
            ~s({% assign s = "x" | load_settings %}{% for p in s %}{{ p[0] }}{{ p[1] }}{% endfor %})
          ] do
        {:ok, parsed} = Liquex.parse(code, Brando.Villain.LiquexParser)
        {result, _} = Liquex.Render.render!([], parsed, context)
        html = IO.iodata_to_binary(result)

        refute html =~ @hash, "#{code} printed the credential: #{html}"
        assert active_elements(html) == [], "#{code} printed markup: #{html}"
      end

      Process.put(:project_filter_settings, [settings])

      code = ~s({% assign l = "x" | load_settings %}{% for s in l %}{{ s.accessToken }}{{ s.title }}{% endfor %})
      {:ok, parsed} = Liquex.parse(code, Brando.Villain.LiquexParser)
      {result, _} = Liquex.Render.render!([], parsed, context)
      html = IO.iodata_to_binary(result)

      refute html =~ @hash
      assert active_elements(html) == []
      assert html =~ "&lt;img"
    end

    test "a date a filter returns stays a date" do
      context = Villain.create_context(%{})

      assert TemplateView.filter_result(~D[2026-01-02], :x, nil, context) == ~D[2026-01-02]
    end
  end

  describe "table rows" do
    test "what a row's records hold prints as text", %{user: user} do
      image = Factory.insert(:image, creator: user, title: "#{@markup_title} {{ 1 | plus: 41 }}")

      row = %TableRow{
        vars: [
          %Var{
            key: "cta",
            label: "C",
            type: :link,
            link_type: :url,
            value: "/a",
            link_text: "#{@markup_title} {{ 1 | plus: 41 }}"
          },
          %Var{key: "pic", label: "P", type: :image, image_id: image.id, image: image}
        ]
      }

      code = "{% for row in block.table_rows %}{{ row.cta.link_text }}|{{ row.pic.title }}{% endfor %}"
      html = render(block(module!(user, code), table_rows: [row]))

      assert active_elements(html) == []
      refute html =~ "42"
      assert html =~ "&lt;img"
    end

    test "a row's rich_text var reads as markup by key and by position", %{user: user} do
      row = %TableRow{vars: [%Var{key: "body", label: "B", type: :rich_text, value: "<p>Rich</p>"}]}
      code = "{% for row in block.table_rows %}{{ row.body }}|{{ row.vars[0].value }}{% endfor %}"

      assert render(block(module!(user, code), table_rows: [row])) == "<p>Rich</p>|<p>Rich</p>"
    end

    test "a row's record still hides a password", %{user: user} do
      row = %TableRow{vars: [%Var{key: "cta", label: "C", type: :link, link_type: :url, value: "/a", creator: user}]}

      code =
        "{% for row in block.table_rows %}{{ row.cta.creator.password }}{{ row.vars[0].creator.password }}{% endfor %}"

      refute render(block(module!(user, code), table_rows: [row])) =~ @hash
    end

    test "a Markdown template reads a row's text as typed", %{user: user} do
      row = %TableRow{vars: [%Var{key: "title", label: "T", type: :string, value: "R&D"}]}
      code = "{% for row in block.table_rows %}{{ row.title }}|{{ row.vars[0].value }}{% endfor %}"
      module = module!(user, "<p>html</p>", %{markdown_code: code})
      md = Villain.Markdown.render([%{block: block(module, table_rows: [row])}], %Page{title: "T", language: :en})

      assert md =~ "R&D|R&D"
    end
  end

  describe "a map field's pairs" do
    test "leave out credentials", %{user: user} do
      entry = Map.put(%Page{language: :en}, :configs, %{"api_key" => "hiddenmarker", "a" => "shown"})

      for code <- [
            "{% for pair in entry.configs %}{% inspect pair %}{% endfor %}",
            "{% for p in entry.configs %}{{ p[0] }}{{ p[1] }}{% endfor %}",
            "{% for p in entry.configs %}{{ p }}{% endfor %}"
          ] do
        html = render(block(module!(user, code), []), entry)

        refute html =~ "hiddenmarker", "#{code} printed it"
        assert html =~ "shown"
      end
    end

    test "escape the key and read the value as a view", %{user: user} do
      child = %Page{title: @markup_title, language: :en, creator: user}
      entry = Map.put(%Page{language: :en}, :configs, %{"<k>" => "v", "c" => child})

      html =
        render(
          block(
            module!(
              user,
              "{% for p in entry.configs %}{{ p[0] }}={{ p[1].title }}{{ p[1].creator.password }}{% endfor %}"
            ),
            []
          ),
          entry
        )

      assert html =~ "&lt;k&gt;="
      assert active_elements(html) == []
      refute html =~ @hash
    end

    test "print as a pair", %{user: user} do
      entry = Map.put(%Page{language: :en}, :configs, %{"a" => "<b>"})

      assert render(block(module!(user, "{% for p in entry.configs %}{{ p }}{% endfor %}"), []), entry) == "a&lt;b&gt;"
    end
  end

  describe "a form tag" do
    test "prints a label's Liquid as text and keeps the CSRF placeholder", %{user: user} do
      {:ok, _} =
        Brando.Forms.create_form(
          %{
            "title" => "Contact",
            "key" => "inert-contact",
            "language" => "en",
            "status" => "published",
            "fields" => [%{"key" => "email", "type" => "email", "label" => "{{ 1 | plus: 41 }}"}]
          },
          user
        )

      html = render(block(module!(user, "{% form 'inert-contact' %}"), []))

      assert html =~ "<form"
      refute html =~ "42"
      assert html =~ "plus: 41"
      assert html =~ ~s(value="$csrftoken")
    end
  end

  describe "names an author chose" do
    test "a ref, a field, a var and a row var named near a credential print", %{user: user} do
      assert render(
               block(module!(user, "{% ref refs.secret_heading %}"),
                 refs: [%{text_ref("<p>Shown</p>") | name: "secret_heading"}]
               )
             ) =~ "Shown"

      entry = Map.put(%Page{language: :en}, :secretary, "Anna")
      assert render(block(module!(user, "{{ entry.secretary }}"), []), entry) == "Anna"

      var = %Var{key: "token_label", label: "L", type: :string, value: "Shown"}
      parent = module!(user, "{{ content }}{% for e in entries %}{{ e.vars.token_label }}{% endfor %}")
      child = block(module!(user, "x"), type: :module_entry, vars: [var])
      assert render(block(parent, multi: true, children: [child])) =~ "Shown"

      row = %TableRow{vars: [%Var{key: "password_hint", label: "L", type: :string, value: "Shown"}]}

      for code <- [
            "{% for row in block.table_rows %}{{ row.password_hint }}{% endfor %}",
            "{% assign rows = block.table_rows | reverse %}{% for row in rows %}{{ row.password_hint }}{% endfor %}"
          ] do
        assert render(block(module!(user, code), table_rows: [row])) == "Shown"
      end

      entry_ref = %{text_ref("<p>Shown</p>") | name: "token_box"}
      parent = module!(user, "{{ content }}{% for e in entries %}{{ e.refs.token_box.name }}{% endfor %}")
      child = block(module!(user, "x"), type: :module_entry, refs: [entry_ref])
      assert render(block(parent, multi: true, children: [child])) =~ "token_box"
    end

    test "a credential word is a whole word of the key" do
      context = Villain.create_context(%{})

      read = fn value, key ->
        case TemplateView.fetch(TemplateView.wrap(value), key, context) do
          {:ok, text} -> text
          :error -> nil
        end
      end

      for key <- ~w(password passwd secret token credential credentials api_key apikey totp recovery_code recovery_codes
                    lockdown_password token_hash totp_secret secret_ciphertext credential_id reset_password_on_first_login
                    client-secret access_token API_KEY Password) do
        assert read.(%{key => "x"}, key) == nil, "#{key} was shown"
        assert read.(Map.put(%Page{}, String.to_atom(key), "x"), key) == nil, "#{key} was shown on a struct"
      end

      for key <- ~w(secretary tokens input_tokens tokenizer passwordless totpal credentialed recovery_codex) do
        assert read.(%{key => "x"}, key) == "x", "#{key} was hidden"
      end
    end
  end

  describe "truncate" do
    test "cuts no character reference in two", %{user: user} do
      entry = %Page{title: "AB & CD and more text", language: :en}

      for length <- 4..12 do
        html = render(block(module!(user, "{{ entry.title | truncate: #{length} }}"), []), entry)

        refute html =~ ~r/&[#\w]*\.\.\.$/, "cut at #{length}: #{html}"
      end
    end

    test "strip_html reads an escaped field's tags as tags, and stays text", %{user: user} do
      entry = %Page{title: ~s(<b>Bold</b> R&D &amp;lt;img src=x onerror=1&amp;gt;), language: :en}
      html = render(block(module!(user, "{{ entry.title | strip_html }}"), []), entry)

      refute html =~ "<b>"
      refute html =~ "&lt;b"
      assert html =~ "Bold"
      assert active_elements(html) == []

      entry = %Page{title: "a < b &lt;img src=x onerror=1", language: :en}
      html = render(block(module!(user, "{{ entry.title | strip_html }}"), []), entry)
      assert active_elements(html) == []
      refute html =~ "<img"
    end
  end

  describe "HEEx comprehensions and split delimiters" do
    test "the module's own Liquid in a comprehension runs, a value's does not", %{user: user} do
      var = %Var{key: "title", label: "T", type: :string, value: "{{ 1 | plus: 41 }}"}

      code = ~S"""
      <p :for={x <- [1, 2]} phx-no-curly-interpolation>{{ entry.title }}</p><i :for={x <- [@title]}>{x}</i>
      """

      html = render(block(module!(user, code, %{type: :heex}), vars: [var]), %Page{title: "Mine", language: :en})

      assert html =~ "<p>Mine</p>"
      refute html =~ "{{ entry"
      refute html =~ "42"
      assert html =~ "plus: 41"
    end

    test "a value cannot complete a delimiter a static part started", %{user: user} do
      for {value, code} <- [
            {"{ 1 | plus: 41 }}", ~S|<style>.a {<%= @css %>}</style>|},
            {"% if true %}41{% endif %}", ~S|<style>.a {<%= @css %>}</style>|},
            {"{ 1 | plus: 41 }}", ~S|<style>.a {<%= @empty %><%= @css %>}</style>|}
          ] do
        vars = [
          %Var{key: "css", label: "C", type: :string, value: value},
          %Var{key: "empty", label: "E", type: :string, value: ""}
        ]

        html = render(block(module!(user, code, %{type: :heex}), vars: vars))

        refute html =~ "42", "#{code} ran #{value}"
        assert html =~ ~r/\.a \{(&#123; 1|&#37; if)/, "#{code} printed #{html}"
      end
    end

    test "a value cannot complete a delimiter a nested part started", %{user: user} do
      for code <- [
            ~S|<style><%= if true do %>.a {<% end %><%= @css %>}</style>|,
            ~S|<style><%= if true do %>.a {<% end %><%= if true do %><%= @css %><% end %>}</style>|,
            ~S|<style><%= if true do %><%= if true do %>.a {<% end %><% end %><%= @empty %><%= @css %>}</style>|,
            ~S|<style>.a {<%= if true do %><%= @empty %><% end %><%= @css %>}</style>|,
            ~S|<style><%= for _ <- [1] do %>.a {<% end %><%= @css %>}</style>|,
            ~S|<style><%= for x <- [1, 2] do %><%= if x == 1, do: @css %>.a {<% end %><%= @css %>}</style>|,
            ~S|<style><%= for v <- ["", @css] do %>.a {<%= v %><% end %>}</style>|,
            ~S|<style>.a {<%= for v <- ["", @css] do %><%= v %><% end %>}</style>|,
            ~S|<style>.a {<%= for _ <- [] do %>x<% end %><%= @css %>}</style>|
          ],
          value <- ["{ 1 | plus: 41 }}", "% if true %}41{% endif %}"] do
        vars = [
          %Var{key: "css", label: "C", type: :string, value: value},
          %Var{key: "empty", label: "E", type: :string, value: ""}
        ]

        html = render(block(module!(user, code, %{type: :heex}), vars: vars))

        assert html =~ ~r/plus: 41|if true/, "#{code} ran #{value}: #{html}"
      end
    end

    test "a value cannot complete a delimiter the block before it left open", %{user: user} do
      before = block(module!(user, ".a {"), [])

      for value <- ["{ 1 | plus: 41 }}", "% if true %}41{% endif %}"] do
        var = %Var{key: "css", label: "C", type: :string, value: value}
        html = render([before, block(module!(user, "<%= @css %>", %{type: :heex}), vars: [var])])

        assert html =~ ~r/plus: 41|if true/, "#{value} ran: #{html}"
      end
    end

    test "a value after a block ending in a brace reads as itself", %{user: user} do
      var = %Var{key: "title", label: "T", type: :string, value: "% off"}
      html = render([block(module!(user, ".a {"), []), block(module!(user, "{{ title }}"), vars: [var])])

      assert html |> Floki.parse_fragment!() |> Floki.text() == ".a {% off"
    end

    test "a module's first value stays JSON inside its container's script", %{user: user} do
      code = ~S|<%= Phoenix.HTML.raw(Jason.encode!(%{a: 1})) %>|

      {:ok, container} =
        Content.create_container(
          %{
            name: "Script",
            namespace: "all",
            help_text: "x",
            code: ~S|<script type="application/json">{{ content }}</script>|
          },
          user
        )

      html =
        render(%Block{
          type: :container,
          active: true,
          container_id: container.id,
          uid: Utils.generate_uid(),
          children: [block(module!(user, code, %{type: :heex}), [])],
          vars: [],
          refs: []
        })

      assert html =~ ~S|{"a":1}|
    end

    test "a first value's leading brace or percent still reads as the same text", %{user: user} do
      var = %Var{key: "css", label: "C", type: :string, value: "% off"}
      html = render(block(module!(user, "<%= @css %>", %{type: :heex}), vars: [var]))

      assert html |> Floki.parse_fragment!() |> Floki.text() == "% off"

      md = Villain.Markdown.render([%{block: block(module!(user, "<%= @css %>", %{type: :heex}), vars: [var])}], %Page{})

      assert md =~ "% off"
    end

    test "a template's own Liquid across parts still runs", %{user: user} do
      code =
        ~S|<style><%= if true do %>{<% end %>{ entry.title }}<%= for _ <- [1] do %>{<% end %>% if true %}ok{% endif %}</style>|

      html = render(block(module!(user, code, %{type: :heex}), []), %Page{title: "Mine", language: :en})

      assert html == "<style>Mineok</style>"
    end
  end

  describe "globals through a filter" do
    test "a rich-text global keeps its markup", %{user: user} do
      preserve_cache(:globals)

      {:ok, set} =
        Brando.Sites.create_global_set(
          %{
            label: "Site",
            key: "site",
            language: "en",
            vars: [%{key: "body", label: "B", type: "rich_text", value: "<p>Hi</p>"}]
          },
          user
        )

      Brando.Cache.Globals.update({:ok, set})

      html = render(block(module!(user, ~S({% assign g = globals.site | default: "" %}{{ g.body }})), []))

      assert html =~ "<p>Hi</p>"
    end
  end

  describe "a value after a template's literal brace" do
    test "a brace written right before a tag does not parse" do
      for code <- ["{{{ entry.title }}", "{{% if true %}x{% endif %}"] do
        refute match?({:ok, _}, Liquex.parse(code, Brando.Villain.LiquexParser)), "#{code} parsed"
      end
    end

    test "whitespace control keeps the space after a template's brace", %{user: user} do
      value = "{ 1 | plus: 41 }}"
      var = %Var{key: "title", label: "T", type: :string, value: value}
      entry = %Page{title: value, language: :en}

      for code <- [
            ".a { {{- entry.title | raw }}",
            ".a {\n  {{- title | raw }}",
            ".a { {%- if true %}{{ entry.title | raw }}{% endif %}"
          ] do
        html = render(block(module!(user, code), vars: [var]), entry)

        refute html =~ ~r/^\.a\s*42/, "#{code} ran: #{html}"
        assert html =~ "plus: 41", "#{code} printed #{html}"
      end

      assert render(block(module!(user, "<p>  {{- entry.title | upcase }}</p>"), []), %Page{title: "x", language: :en}) ==
               "<p>X</p>"
    end

    test "a slot's child ending in a brace completes no delimiter with the next", %{user: user} do
      var = %Var{key: "css", label: "C", type: :string, value: "{ 1 | plus: 41 }}"}

      slot = %Block{
        type: :slot,
        active: true,
        uid: Utils.generate_uid(),
        vars: [],
        refs: [],
        children: [block(module!(user, ".a {"), []), block(module!(user, "<%= @css %>", %{type: :heex}), vars: [var])]
      }

      html = render(slot)

      assert html =~ "plus: 41", "ran: #{html}"
    end

    test "stripping what the final pass strips completes no delimiter", %{user: user} do
      for {type, marker} <- [
            {:heex, ~S| data-identifier-id="1"|},
            {:heex, ~S|<span data-brando-note="1"></span>|},
            {:liquid, ~S| data-identifier-id="1"|}
          ],
          tail <- ["{ 1 | plus: 41 }}", "% if true %}41{% endif %}"] do
        value = "{" <> marker <> tail

        {attrs, code} =
          case type do
            :heex ->
              {%{type: :heex},
               ~S|<%= Phoenix.HTML.raw(@body) %><style phx-no-curly-interpolation>{{ entry.title }}</style>|}

            :liquid ->
              {%{}, "{{ body | raw }}"}
          end

        var = %Var{key: "body", label: "B", type: :string, value: value}
        html = render(block(module!(user, code, attrs), vars: [var]))

        assert html =~ ~r/plus: 41|if true/, "#{marker}#{tail} ran: #{html}"
      end
    end

    test "a rich-text var printed by HEEx completes no delimiter through the strip", %{user: user} do
      var = %Var{key: "body", label: "B", type: :rich_text, value: ~S(<p>{ data-identifier-id="1"{ 1 | plus: 41 }}</p>)}
      html = render(block(module!(user, ~S|<%= Phoenix.HTML.raw(@body) %>|, %{type: :heex}), vars: [var]))

      refute html =~ ~r/>\s*42/, "ran: #{html}"
    end

    test "stripping a note mark leaves a brace before any other span alone" do
      html = ~S|<script>const a = "{<span>";</script><span data-brando-note="1">Text</span>|

      assert Brando.Notes.strip_marks(html) == ~S|<script>const a = "{<span>";</script>Text|
    end

    test "a multi module's last child ending in a brace completes no delimiter", %{user: user} do
      child_module = module!(user, ".a {")
      parent = module!(user, "{{ content }}{{ body | raw }}")
      var = %Var{key: "body", label: "B", type: :string, value: "{ 1 | plus: 41 }}"}

      html = render(block(parent, multi: true, vars: [var], children: [block(child_module, type: :module_entry)]))

      assert html =~ "plus: 41", "ran: #{html}"
    end

    test "a real identifier attribute is still stripped", %{user: user} do
      html = render(block(module!(user, ~S(<a href="/" data-identifier-id="1">x</a>{{ entry.title }})), []))

      refute html =~ "data-identifier-id"
    end

    test "a container's brace before its content completes no delimiter", %{user: user} do
      var = %Var{key: "css", label: "C", type: :string, value: "{ 1 | plus: 41 }}"}

      {:ok, container} =
        Content.create_container(%{name: "B", namespace: "all", help_text: "x", code: ".a {{{ content }}"}, user)

      html =
        render(%Block{
          type: :container,
          active: true,
          container_id: container.id,
          uid: Utils.generate_uid(),
          children: [block(module!(user, "<%= @css %>", %{type: :heex}), vars: [var])],
          vars: [],
          refs: []
        })

      assert html =~ "plus: 41", "ran: #{html}"
    end

    @tag :capture_log
    test "a filter that decodes text completes no delimiter", %{user: user} do
      for code <- [
            ".a { {{- entry.title | strip_html }}",
            ".a { {{- title | strip_html }}",
            ~S({{ "{" }}{{ title | strip_html }}),
            ".a { {{- encoded | url_decode }}",
            ".a { {{- encoded | url_decode | strip }}",
            ~S({{ "{" }}{{ encoded | url_decode | strip }}),
            ".a { {{- title | strip_html | strip }}"
          ],
          value <- ["{ 1 | plus: 41 }}", " { 1 | plus: 41 }}", "% if true %}42{% endif %}"] do
        vars = [
          %Var{key: "title", label: "T", type: :string, value: value},
          %Var{key: "encoded", label: "E", type: :string, value: URI.encode(value, &URI.char_unreserved?/1)}
        ]

        html = render(block(module!(user, code), vars: vars), %Page{title: value, language: :en})

        refute html =~ ~r/^(\.a )?42/, "#{code} ran #{value}: #{html}"
        if value =~ "plus", do: assert(html =~ "plus: 41", "#{code} printed #{html}")
      end
    end

    test "a template that makes no HTML keeps a decoding filter's text" do
      entry = %Page{title: "{Draft} \"x\"", language: :en}
      {:ok, parsed} = Liquex.parse("{{ entry.title | strip_html }}", Brando.Villain.LiquexParser)
      {result, _} = Liquex.Render.render!([], parsed, Villain.plain_context(entry))

      assert IO.iodata_to_binary(result) == ~s({Draft} "x")
    end

    test "a text filter's result reads as the same text", %{user: user} do
      entry = %Page{title: "% off {x}", language: :en}
      html = render(block(module!(user, "<a title=\"{{ entry.title | strip_html }}\">x</a>"), []), entry)

      assert html |> Floki.parse_fragment!() |> Floki.attribute("title") == ["% off {x}"]
    end
  end

  describe "edges after the first round" do
    test "a chained replace matches a placeholder after the first", %{user: user} do
      code =
        ~S({{ "Hi {{a}} and {{b}}" | replace: "{{a}}", "A" | replace: "{{b}}", "B" }}|) <>
          ~S({{ "{{a}}{%b%}" | remove: "{{a}}" | remove_first: "{%b%}" }}|) <>
          ~S({{ "{{a}} {{b}}" | replace_first: "{{a}}", "A" | replace_first: "{{b}}", "B" }}|) <>
          ~S({{ entry.title | replace: "{{a}}", "A" | replace: "{{b}}", "B" }})

      entry = %Page{title: "{{a}} {{b}}", language: :en}

      assert render(block(module!(user, code), []), entry) == "Hi A and B||A B|A B"
    end

    test "a replaced placeholder starts no Liquid", %{user: user} do
      code = ~S({{ "{{a}} 1 | plus: 41 }}" | replace: "x", "y" | replace: "{{a}}", "{{" }})
      html = render(block(module!(user, code), []))

      assert html =~ "plus: 41"
    end

    test "map reads a rich-text field as markup", %{user: user} do
      vars = [
        %Var{key: "body", label: "B", type: :rich_text, value: ~s(<p>One <strong>b</strong></p>)},
        %Var{key: "unsafe", label: "U", type: :rich_text, value: ~s(<p>x</p><script>document.title=1</script>)},
        %Var{key: "title", label: "T", type: :string, value: @markup_title}
      ]

      entry = %Page{title: "T", language: :en, vars: vars}

      for code <- [~S({{ entry.vars | map: "value" | first }}), ~S({{ entry.vars | map: "value" | join: "" }})] do
        html = render(block(module!(user, code), []), entry)

        assert html =~ "<p>One <strong>b</strong></p>", "#{code} printed #{html}"
        assert active_elements(html) == [], "#{code} printed #{html}"
      end

      html = render(block(module!(user, ~S({{ entry.vars | map: "value" | last }})), []), entry)
      assert Floki.text(Floki.parse_fragment!(html)) == @markup_title
    end

    test "map leaves credentials out, as reading the field does", %{user: user} do
      entry = %Page{title: "T", language: :en, children: [%Page{title: "C", creator: user}]}
      code = ~S({{ entry.children | map: "creator" | map: "password" | join: "" }}|{{ entry.children | map: "title" }})

      assert render(block(module!(user, code), []), entry) == "|C"
    end

    test "size and truncate count a brace a filter encoded as one character", %{user: user} do
      entry = %Page{title: "{abcdef}", language: :en}

      for {code, expected} <- [
            {"{{ entry.title | strip_html | size }}", "8"},
            {"{{ '%7Babcdef%7D' | url_decode | size }}", "8"},
            {"{{ entry.title | size }}", "8"},
            {"{{ entry.title | strip_html | truncate: 5 }}", "&#123;a..."},
            {"{{ '%7Babcdef%7D' | url_decode | truncate: 5 }}", "&#123;a..."},
            {"{{ '{abcdef}' | truncate: 5 }}", "{a..."}
          ] do
        assert render(block(module!(user, code), []), entry) == expected, code
      end
    end

    @tag :capture_log
    test "a value after a literal brace prints as text, also starting with a percent sign", %{user: user} do
      for code <- [
            ~S({{ "{" }}{{ entry.title }}),
            ~S({{ "{" }}{{ entry.title | upcase | downcase }}),
            ~S({{ "{" }}{{ title }}),
            ~S({{ "{" }}{{ title | strip }}),
            ~S({{ "{" }}{% echo entry.title %}),
            ~S({% assign b = "{" %}{{ b }}{{ entry.title }}),
            ~S({{ "{" }}{% if true %}{{ entry.title }}{% endif %}),
            ~S({{ "{" -}}  {{ entry.title }}),
            ~S({{ "{" }}  {{- entry.title }}),
            ~S|{% for i in (1..2) %}{{ "{" }}{% endfor %}{{ entry.title }}|
          ],
          value <- ["% if true %}42{% endif %}", "% if x", " % if true %}42{% endif %}", "{ 1 | plus: 41 }}"] do
        var = %Var{key: "title", label: "T", type: :string, value: value}

        html = render(block(module!(user, code), vars: [var]), %Page{title: value, language: :en})

        refute html =~ "Error parsing", "#{code} with #{value}: #{html}"
        assert Floki.text(Floki.parse_fragment!(html)) =~ ~r/\{ ?(% if|\{ 1 \| plus: 41)/, "#{code} ran #{value}: #{html}"
      end
    end

    @tag :capture_log
    test "raw after a literal brace completes no delimiter", %{user: user} do
      for code <- [~S({{ "{" }}{{ title | raw }}), ~S({{ "{" }}{{ entry.title | raw }})],
          value <- ["{ 1 | plus: 41 }}", "% if true %}42{% endif %}"] do
        var = %Var{key: "title", label: "T", type: :string, value: value}

        html = render(block(module!(user, code), vars: [var]), %Page{title: value, language: :en})

        refute html =~ "Error parsing", "#{code} with #{value}: #{html}"
        assert html =~ ~r/plus: 41|if true/, "#{code} ran #{value}: #{html}"
      end
    end

    @tag :capture_log
    test "a brace stays open through an output or tag that prints nothing", %{user: user} do
      for code <- [
            ~S({{ "{" }}{{ missing }}{{ entry.title | raw }}),
            ~S({{ "{" }}{% capture unused %}{{ "x" }}{% endcapture %}{{ entry.title | raw }}),
            ~S({{ "{" }}{% if false %}x{% endif %}{{ entry.title | raw }}),
            ~S({{ "{" }}{% assign a = "x" %}{{ entry.title }}),
            ~S({{ "{" }}{% if true %}{% endif %}{{ entry.title }}),
            ~S({{ "{" }}{% capture c %}{{ entry.title | raw }}{% endcapture %}{{ c }})
          ],
          value <- ["{ 1 | plus: 41 }}", "% if true %}42{% endif %}"] do
        html = render(block(module!(user, code), []), %Page{title: value, language: :en})

        refute html =~ "Error parsing", "#{code} with #{value}: #{html}"
        assert html =~ ~r/plus: 41|if true/, "#{code} ran #{value}: #{html}"
      end
    end

    test "a ref that prints nothing renders as nothing", %{user: user} do
      svg = ref("svg", %Brando.Villain.Blocks.SvgBlock{data: %Brando.Villain.Blocks.SvgBlock.Data{code: nil}})
      input = ref("input", %Brando.Villain.Blocks.InputBlock{data: %Brando.Villain.Blocks.InputBlock.Data{value: nil}})
      code = "<h2>{% ref refs.svg %}</h2><p>{% ref refs.input %}</p>"

      assert render(block(module!(user, code), refs: [svg, input])) == "<h2></h2><p></p>"
    end

    defmodule CharlistTag do
      @moduledoc false
      def render(_contents, context), do: {[~c"Ĭ", "x"], context}
    end

    test "a tag's text prints as the joined document read it" do
      contents = [tag: CharlistTag, contents: [], after_text: false, before_text: false]

      assert {"Ĭx", _} = Brando.Villain.Tags.Output.render(contents, Villain.get_base_context())
    end

    test "a literal brace keeps JSON printed through raw working", %{user: user} do
      var = %Var{key: "json", label: "J", type: :string, value: ~s({"b":1})}
      key = %Var{key: "key", label: "K", type: :string, value: "k"}

      for {code, expected} <- [
            {~S(<script>{{ "{" }}"a": {{ json | raw }}}</script>), ~S(<script>{"a": {"b":1}}</script>)},
            {~S(<script>{{ "{" }}"{{ key }}": {{ json | raw }}}</script>), ~S(<script>{"k": {"b":1}}</script>)},
            {~S(<script>{{ "{" }}{{ "x" }}{{ json | raw }}</script>), ~S(<script>{x{"b":1}</script>)},
            {~S(<script>{{ json | raw }}{{ json | raw }}</script>), ~S(<script>{"b":1}{"b":1}</script>)},
            {~S(<script>{{ "{" }}"a": 1}{% if true %}{{ json | raw }}{% endif %}</script>),
             ~S(<script>{"a": 1}{"b":1}</script>)},
            {~S(<script>{{ "{" }}{% if true %}"a": {% endif %}{{ json | raw }}}</script>),
             ~S(<script>{"a": {"b":1}}</script>)},
            {~S[<script>{{ "{" }}{% for i in (1..1) %}"a": {% endfor %}{{ json | raw }}}</script>],
             ~S(<script>{"a": {"b":1}}</script>)},
            {~S(<script>{{ "{" }}{% if true %}"a": {% if true %}{{ json | raw }}{% endif %}{% endif %}}</script>),
             ~S(<script>{"a": {"b":1}}</script>)},
            {~S(<script>{{ "{" }}{% capture j %}{{ json | raw }}{% endcapture %}"a": {{ j }}}</script>),
             ~S(<script>{"a": {"b":1}}</script>)},
            {~S[<script>{{ "{" }}{% tablerow i in (1..1) %}{{ json | raw }}{% endtablerow %}</script>],
             ~s(<script>{<tr class="row1">\n<td class="col1">{"b":1}</td></tr>\n</script>)}
          ] do
        assert render(block(module!(user, code), vars: [var, key])) == expected, code
      end
    end

    test "every tablerow cell starts after its cell's markup", %{user: user} do
      vars = [
        %Var{key: "json", label: "J", type: :string, value: ~s({"b":1})},
        %Var{key: "pct", label: "P", type: :string, value: "%x"}
      ]

      cases = [
        {~S[<script>{% tablerow i in (1..2) %}{{ json | raw }}{{ "{" }}{% endtablerow %}</script>],
         ~s(<script><tr class="row1">\n<td class="col1">{"b":1}{</td><td class="col2">{"b":1}{</td></tr>\n</script>)},
        {~S[{% tablerow i in (1..2) cols:1 %}{% if i == 1 %}{{ "{" }}{% else %}{{ pct | raw }}{% endif %}{% endtablerow %}],
         ~s(<tr class="row1">\n<td class="col1">{</td></tr>\n<tr class="row2"><td class="col1">%x</td></tr>\n)},
        {~S[{% tablerow i in (1..2) %}{% assign a = i %}{% if i == 1 %}{{ "{" }}{% else %}{{ pct | raw }}{% endif %}{% endtablerow %}],
         ~s(<tr class="row1">\n<td class="col1">{</td><td class="col2">%x</td></tr>\n)}
      ]

      rendered = Enum.map(cases, fn {code, _} -> {code, render(block(module!(user, code), vars: vars))} end)

      assert rendered -- cases == []
    end
  end
end
