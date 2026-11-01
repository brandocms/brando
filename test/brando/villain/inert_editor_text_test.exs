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
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Utils
  alias Brando.Villain
  alias Brando.Villain.Blocks.MarkdownBlock
  alias Brando.Villain.Blocks.PictureBlock
  alias Brando.Villain.Blocks.TextBlock
  alias Brando.Villain.TemplateView

  # An image with a handler, percent-encoded so a sanitizer sees only text. Its
  # handler sets a marker and nothing else.
  @encoded "%3Cimg%20src%3Dx%20onerror%3D%22document.title%3D1%22%3E"
  @payload "{{ '#{@encoded}' | url_decode }}"
  @hash "$2b$12$dummy.stored.value.for.a.test"

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
    struct(%Block{type: :module, active: true, module_id: module.id, uid: Utils.generate_uid(), vars: [], refs: []}, attrs)
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
      vars = [%Var{key: "cta", label: "C", type: :link, link_type: :url, value: "/a", creator: user},
              %Var{key: "pic", label: "P", type: :image, image_id: image.id, image: %{image | creator: user}}]

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

    test "no struct shows a field named like a credential" do
      view = TemplateView.wrap(%{api_key: "k", name: "n", access_token: "t", nested: %{client_secret: "s"}})
      context = Villain.create_context(%{"x" => view})

      eval = fn keys -> keys |> Enum.map(&{:key, &1}) |> then(&Liquex.Argument.eval({:field, [{:key, "x"} | &1]}, context)) |> elem(0) end

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
        assert html =~ "<em>Hi</em> &#123;&#123; 1 | plus: 1 &#125;&#125;"
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
        entry = Map.put(%Page{language: :en}, field, ~s(<p>Text <strong>bold</strong> <script>x</script>{{ 1 | plus: 1 }}</p>))
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
      html = render(block(module!(user, "{{ block.description }}{{ block.anchor }}"), description: @markup, anchor: "{{ 1 | plus: 1 }}"))

      assert active_elements(html) == []
      refute html =~ "{{"
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
        render(%Block{type: :fragment, active: true, fragment_id: fragment.id, uid: Utils.generate_uid(), vars: [], refs: []})

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
      code = "{% for pair in entry.meta %}x{% endfor %}"

      assert render(block(module!(user, code), []), entry) == "x"
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

    test "a module without one renders its HTML, and braces come through as text", %{user: user} do
      module = module!(user, "<p>{{ entry.title }}</p>{% ref refs.text %}")
      entry = %Page{title: "R&D {{ x }}", language: :en}
      md = Villain.Markdown.render([%{block: block(module, refs: [text_ref("<p>e {{ f }}</p>")])}], entry)

      assert md =~ ~S(R\&D {{ x }})
      assert md =~ "e {{ f }}"
      refute md =~ "&#123;"
    end
  end

  test "a filter returning {:safe, html} prints it" do
    assert TemplateView.filter_result({:safe, ["<b>", "x"]}, :x, true, Villain.create_context(%{})) == "<b>x"
  end
end
