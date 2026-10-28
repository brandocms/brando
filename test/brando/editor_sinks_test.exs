defmodule Brando.EditorSinksTest do
  # Text an editor saves reaches the site's pages, where markup in it would
  # run with the cookies of whoever views them (#3354). The payloads in
  # `test/fixtures/editor_sinks/payloads.json` would each only set the page's
  # title; `active/1` counts what in a rendering a browser would run.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Villain.Parser

  @payloads "test/fixtures/editor_sinks/payloads.json" |> File.read!() |> Jason.decode!()
  @handler @payloads["handler"]
  @script @payloads["script"]

  setup do
    preserve_cache(:globals)
    %{user: Factory.insert(:random_user)}
  end

  # Elements with an event handler, scripts, and addresses a browser runs
  defp active(html) do
    doc = html |> IO.iodata_to_binary() |> LazyHTML.from_fragment()
    handlers = doc |> LazyHTML.query("[onerror],[onclick],[onload],script") |> Enum.count()

    addresses =
      for attr <- ["href", "src"],
          value <- doc |> LazyHTML.query("[#{attr}]") |> LazyHTML.attribute(attr),
          String.match?(value, ~r/^\s*(javascript|vbscript|data:text)/i),
          do: value

    handlers + length(addresses)
  end

  defp var(type, key, value), do: %Var{type: type, key: key, label: %{"en" => key}, value: value}

  defp render_module(user, code, vars, type \\ :liquid, refs \\ []) do
    {:ok, module} = Content.create_module(Factory.params_for(:module, %{type: type, code: code}), user)

    block = %{
      block: %Block{type: :module, module_id: module.id, uid: Brando.Utils.generate_uid(), vars: vars, refs: refs}
    }

    # An entry whose title holds markup, which Liquid prints as it is stored
    Brando.Villain.parse([block], %Brando.Pages.Page{title: @handler})
  end

  describe "the rich_text var type" do
    test "reads its old name, html, and writes rich_text" do
      assert Var.Type.cast("html") == {:ok, :rich_text}
      assert Var.Type.cast(:html) == {:ok, :rich_text}
      assert Var.Type.load("html") == {:ok, :rich_text}
      assert Var.Type.dump(:html) == {:ok, "rich_text"}
      assert Var.Type.cast("rich_text") == {:ok, :rich_text}
      assert Var.Type.cast("nope") == :error

      changeset = Block.var_changeset(%Var{}, %{"type" => "html", "key" => "body", "label" => "Body"}, nil)
      assert Ecto.Changeset.get_field(changeset, :type) == :rich_text

      # A struct built with the old name, as a module export or an older
      # revision holds it
      var = Brando.Repo.insert!(var(:html, "body", "<p>Body</p>"))
      assert Brando.Repo.get!(Var, var.id).type == :rich_text

      # A pending translation stored before the rename decodes with the new name
      stored = %Brando.Pages.Page{
        title: "Old",
        vars: [var(:html, "intro", "<p>Intro</p>")],
        inserted_at: ~N[2026-01-01 00:00:00]
      }

      payload = :erlang.term_to_binary(stored)
      decoded = Brando.Translations.decode_payload(%Brando.Translations.PendingVersion{payload: payload})
      assert [%Var{type: :rich_text, value: "<p>Intro</p>"}] = decoded.vars
      assert decoded.inserted_at == ~N[2026-01-01 00:00:00]

      assert %{rows: [["rich_text"]]} =
               Ecto.Adapters.SQL.query!(BrandoIntegration.Repo, "SELECT type FROM content_vars WHERE id = $1", [var.id])
    end

    test "a value is sanitized on save, and unsafe markup refused", %{user: user} do
      params = fn value -> %{"type" => "rich_text", "key" => "body", "label" => "Body", "value" => value} end

      safe = Block.var_changeset(%Var{}, params.("<p>Hi <strong>there</strong></p>"), user)
      assert safe.valid?
      assert Ecto.Changeset.get_change(safe, :value) == "<p>Hi <strong>there</strong></p>"

      for payload <- [@handler, @script, @payloads["script_link"]] do
        unsafe = Block.var_changeset(%Var{}, params.("<p>Hi</p>" <> payload), user)
        refute unsafe.valid?
        assert Keyword.has_key?(unsafe.errors, :value)
      end

      # Saved with its owner (a global set here) it goes through the same check
      assert {:error, _changeset} =
               Brando.Sites.create_global_set(
                 %{
                   "label" => "System",
                   "key" => "system",
                   "language" => "en",
                   "vars" => [%{"type" => "rich_text", "label" => "Body", "key" => "body", "value" => @handler}]
                 },
                 user
               )

      # A string var keeps what was typed: it is escaped where it is printed
      assert Block.var_changeset(%Var{}, %{params.(@handler) | "type" => "string"}, user).valid?
    end

    test "a value saved before renders without its unsafe markup" do
      stored = "<p>Kept text</p>" <> @handler <> @script

      for type <- [:rich_text, :html] do
        %{"body" => html} = Parser.process_vars([var(type, "body", stored)])
        assert active(html) == 0
        assert html =~ "Kept text"

        assert active(Content.render_var(var(type, "body", stored))) == 0
        assert active(to_string(var(type, "body", stored))) == 0
      end

      assert Parser.process_vars([var(:rich_text, "body", "<p>A <em>b</em></p>")]) == %{"body" => "<p>A <em>b</em></p>"}
    end
  end

  describe "vars in Liquid" do
    test "string and text vars are printed escaped, rich text sanitized", %{user: user} do
      html =
        render_module(
          user,
          ~s(<h2 title="{{ title }}">{{ title }}</h2><p>{{ intro }}</p><div>{{ body }}</div><div>{{ old }}</div>),
          [
            var(:string, "title", ~s(Tom & "Jerry" ) <> @handler),
            var(:text, "intro", @script),
            var(:rich_text, "body", "<p>Body <em>text</em></p>"),
            # Saved before values were checked
            var(:rich_text, "old", "<p>Old body</p>" <> @handler)
          ]
        )

      assert active(html) == 0
      assert html =~ ~s(title="Tom &amp; &quot;Jerry&quot; &lt;img)
      assert html =~ "<p>&lt;script&gt;"
      assert html =~ "<div><p>Body <em>text</em></p></div>"
      assert html =~ "<div>Old body</div>"
    end

    test "escape, url_encode and markdown read an escaped var as typed", %{user: user} do
      html =
        render_module(
          user,
          ~s(<a href="/s?q={{ q | url_encode }}">{{ q | escape }}</a>{{ md | markdown }}),
          [var(:string, "q", "Tom & Jerry"), var(:text, "md", "> quoted\n\n`a & b` " <> @handler)]
        )

      assert html =~ ~s(href="/s?q=Tom+%26+Jerry")
      assert html =~ ">Tom &amp; Jerry</a>"
      assert html =~ "<blockquote>"
      assert html =~ "<code>a &amp; b</code>"
      assert active(html) == 0
    end

    test "HEEx modules escape a var once", %{user: user} do
      html = render_module(user, "<p>{@title}</p>", [var(:string, "title", "Tom & Jerry " <> @handler)], :heex)

      assert html =~ "<p>Tom &amp; Jerry &lt;img"
      assert active(html) == 0
    end

    test "a table row's vars are escaped or sanitized by key and in its vars" do
      row = %{vars: [var(:string, "city", @handler), var(:rich_text, "note", "<p>Note</p>" <> @handler)]}
      block = %{uid: "b", type: :module, table_rows: [row]}

      %{table_rows: [liquid]} = Brando.Villain.TemplateAdapter.simple_block(%{class: nil}, block, escape: true)
      assert active(liquid.city) == 0
      assert active(liquid.note) == 0
      assert Enum.all?(liquid.vars, &(active(&1.value) == 0))

      %{table_rows: [heex]} = Brando.Villain.TemplateAdapter.simple_block(%{class: nil}, block)
      assert heex.city == @handler
      assert [%{value: @handler}, %{value: note}] = heex.vars
      assert active(note) == 0
    end

    test "Liquid typed into a string var or a heading is printed, not run", %{user: user} do
      header = %Brando.Content.Ref{
        name: "heading",
        uid: Brando.Utils.generate_uid(),
        data: %Brando.Villain.Blocks.HeaderBlock{
          data: %Brando.Villain.Blocks.HeaderBlock.Data{text: "{{ entry.title }}", level: 2}
        }
      }

      html =
        render_module(
          user,
          "<p>{{ headline }}</p><p>{{ headline | escape }}</p>{% ref refs.heading %}",
          [var(:string, "headline", "{{ entry.title }}")],
          :liquid,
          [header]
        )

      assert active(html) == 0
      assert html =~ "<p>&#123;&#123; entry.title &#125;&#125;</p><p>&#123;&#123; entry.title &#125;&#125;</p>"
      assert html =~ "<h2>&#123;&#123; entry.title &#125;&#125;</h2>"
    end

    test "HEEx reads globals unescaped, and escapes them once", %{user: user} do
      {:ok, _} =
        Brando.Sites.create_global_set(
          %{
            "label" => "System",
            "key" => "system",
            "language" => "en",
            "vars" => [%{"type" => "string", "label" => "Name", "key" => "name", "value" => "Tom & Jerry"}]
          },
          user
        )

      html = render_module(user, "<p>{@globals[\"system\"][\"name\"]}</p>", [], :heex)
      assert html =~ "<p>Tom &amp; Jerry</p>"
    end

    test "globals are escaped as vars are", %{user: user} do
      {:ok, _} =
        Brando.Sites.create_global_set(
          %{
            "label" => "System",
            "key" => "system",
            "language" => "en",
            "vars" => [
              %{"type" => "string", "label" => "Name", "key" => "name", "value" => @handler},
              %{"type" => "rich_text", "label" => "Body", "key" => "body", "value" => "<p>Global</p>"}
            ]
          },
          user
        )

      html =
        Brando.Villain.parse_and_render(
          "<b>{{ globals.system.name }}</b>{{ globals.system.body }}",
          Brando.Villain.get_base_context()
        )

      assert html =~ "<b>&lt;img"
      assert html =~ "<p>Global</p>"
      assert active(html) == 0
    end

    test "identity links print their name and address escaped, and no script address" do
      links = [
        %Brando.Sites.Link{name: "Shop", url: ~s(https://shop.example/?a=1&b="2")},
        %Brando.Sites.Link{name: "Bad", url: "javascript:document.title='MARKER'"}
      ]

      context = Brando.Villain.add_to_context(Brando.Villain.create_context(%{}), "links", %{links: links})

      html =
        Brando.Villain.parse_and_render(
          ~s(<a href="{{ links.shop.url }}">S</a><a href="{{ links.bad.url }}">B</a>),
          context
        )

      assert html =~ ~s(href="https://shop.example/?a=1&amp;b=&quot;2&quot;")
      assert html =~ ~s(<a href="">B</a>)

      # HEEx reads them unescaped, the address still checked
      raw = Brando.Villain.raw_context(context, "links")
      assert raw["shop"].url == ~s(https://shop.example/?a=1&b="2")
      assert raw["bad"].url == ""

      heex = fn link -> Phoenix.HTML.Safe.to_iodata(link) |> IO.iodata_to_binary() end
      [shop, bad] = links
      assert heex.(shop) == "https://shop.example/?a=1&amp;b=&quot;2&quot;"
      assert heex.(bad) == ""
    end

    test "link filters print their text and address escaped" do
      link = %Var{type: :link, link_type: :url, value: ~s(/a?b=1&c="2"), link_text: @handler}
      context = Brando.Villain.create_context(%{"cta" => link})

      html = Brando.Villain.parse_and_render(~s(<a href="{{ cta | link_url }}">{{ cta | link_text }}</a>), context)
      assert html =~ ~s(href="/a?b=1&amp;c=&quot;2&quot;")
      assert active(html) == 0

      # An entry's title, which a HEEx identifier stores escaped, is escaped once
      entry_link = %Var{
        type: :link,
        link_type: :identifier,
        link_text: nil,
        identifier: %Brando.Content.Identifier{
          schema: Brando.JSONLDTest.Person,
          url: "/rooms",
          title: "Rooms &amp; suites"
        }
      }

      context = Brando.Villain.create_context(%{"cta" => entry_link})
      assert Brando.Villain.parse_and_render("{{ cta | link_text }}", context) == "Rooms &amp; suites"
    end
  end

  describe "refs" do
    test "a heading's text is escaped, its line breaks kept" do
      html = Parser.header(%{text: "First line\n" <> @handler, level: 2}, %{}) |> IO.iodata_to_binary()

      assert html =~ "<h2>First line<br>&lt;img"

      # A character reference typed into a heading is the character it names
      assert Parser.header(%{text: "Fjell&shy;vandring &amp; mer", level: 2}, %{}) |> IO.iodata_to_binary() ==
               "<h2>Fjell­vandring &amp; mer</h2>"

      assert active(html) == 0

      linked = Parser.header(%{text: @script, level: 3, link: "/about"}, %{}) |> IO.iodata_to_binary()
      assert active(linked) == 0
    end

    test "a picture's own title and credits are escaped, a placement caption sanitized" do
      picture = fn attrs ->
        :image |> Factory.build(Map.merge(%{alt: nil}, attrs)) |> Parser.picture([])
      end

      library = picture.(%{title: @handler, credits: @script})
      assert active(library) == 0
      assert library =~ "<figcaption>&lt;img"

      placement = picture.(%{title: "<p>Placement <em>caption</em></p>" <> @handler, credits: nil})
      assert active(placement) == 0
      assert placement =~ "<em>caption</em>"
    end

    test "Markdown renders no raw HTML and no script addresses" do
      html = Parser.markdown(%{text: @payloads["markdown_html"]}, %{})
      assert active(html) == 0
      assert html =~ "Before"
      refute html =~ "MARKER"

      links = Parser.markdown(%{text: @payloads["markdown_links"]}, %{})
      assert active(links) == 0
      assert links =~ ~s(href="https://example.com/?a=1&amp;b=2")
    end
  end

  describe "AI translation" do
    test "stores a translated rich_text var or rich-text field as an editor's would be", %{user: user} do
      page = Factory.insert(:page, creator: user)
      var = Brando.Repo.insert!(%{var(:rich_text, "body", "<p>Source</p>") | page_id: page.id})
      plain = Brando.Repo.insert!(%{var(:string, "title", "Source") | page_id: page.id})

      Brando.AI.Translation.apply_translations(
        [{:var, var.id, "<p>Kilde</p>" <> @handler}, {:var, plain.id, "Tom & Jerry"}],
        page,
        Brando.Pages.Page
      )

      # Refused: the copy keeps the source text
      assert Brando.Repo.get!(Var, var.id).value == "<p>Source</p>"
      assert Brando.Repo.get!(Var, plain.id).value == "Tom & Jerry"

      Brando.AI.Translation.apply_translations([{:var, var.id, "<p>Kilde<br/></p>"}], page, Brando.Pages.Page)
      assert Brando.Repo.get!(Var, var.id).value == "<p>Kilde<br></p>"

      entry = Brando.Repo.insert!(%Brando.LinkTest.Case{title: "Case", slug: "case", summary: "<p>Source</p>"})

      Brando.AI.Translation.apply_translations(
        [{:field, :summary, "<p>Kilde</p>" <> @script}],
        entry,
        Brando.LinkTest.Case
      )

      assert Brando.Repo.get!(Brando.LinkTest.Case, entry.id).summary == "<p>Source</p>"
    end
  end

  describe "media" do
    setup do
      media_path = Path.join(System.tmp_dir!(), "brando-editor-sinks-#{System.unique_integer([:positive])}")
      put_test_env(:media_path, media_path)
      File.mkdir_p!(Path.join(media_path, "files"))

      for name <- ~w(drawing.svg page.html report.pdf),
          do: File.write!(Path.join([media_path, "files", name]), @script)

      on_exit(fn -> File.rm_rf(media_path) end)
    end

    defp serve(path) do
      opts = Brando.Plug.Media.init(at: "/media")
      :get |> Plug.Test.conn(path) |> Brando.Plug.Media.call(opts)
    end

    test "a media file is served sandboxed and as the type its name gives" do
      for name <- ~w(drawing.svg page.html) do
        conn = serve("/media/files/#{name}")
        assert conn.status == 200
        assert Plug.Conn.get_resp_header(conn, "content-security-policy") == ["sandbox"]
        assert Plug.Conn.get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      end

      # Browsers show no PDF in a sandboxed document
      pdf = serve("/media/files/report.pdf")
      assert Plug.Conn.get_resp_header(pdf, "content-security-policy") == []
      assert Plug.Conn.get_resp_header(pdf, "x-content-type-options") == ["nosniff"]

      missing = serve("/media/files/missing.svg")
      assert missing.status == 404
      assert Plug.Conn.get_resp_header(missing, "content-security-policy") == ["sandbox"]
    end
  end
end
