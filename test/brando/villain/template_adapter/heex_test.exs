defmodule Brando.Villain.TemplateAdapter.HeexTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Module, as: ContentModule
  alias Brando.Content.Var
  alias Brando.Villain.TemplateAdapter.Heex

  defp module(code, attrs \\ %{}) do
    Map.merge(
      %ContentModule{
        id: System.unique_integer([:positive]),
        type: :heex,
        class: "heex-test",
        code: code,
        datasource: false
      },
      attrs
    )
  end

  defp block(attrs \\ %{}) do
    Map.merge(
      %{
        active: true,
        anchor: nil,
        block_identifiers: [],
        collapsed: false,
        description: nil,
        module_id: 123,
        refs: [],
        sequence: 0,
        table_rows: [],
        type: :module,
        uid: "heex-test-block",
        vars: []
      },
      attrs
    )
  end

  defp opts(context) do
    %{
      context: context,
      parser_module: Brando.Villain.Parser
    }
  end

  test "module assigns include vars and the complete Villain context" do
    context =
      Liquex.Context.new(%{
        "configs" => %{lockdown_enabled: true},
        "entry" => %{title: "Entry title"},
        "globals" => %{"site" => %{"name" => "Global name"}},
        "identity" => %{name: "Identity name"},
        "language" => "en",
        "links" => %{"docs" => %{url: "/docs"}},
        "locale" => "en",
        "navigation" => %{"main" => %{title: "Main menu"}}
      })

    code = """
    <article
      data-config={@configs.lockdown_enabled}
      data-entry={@entry.title}
      data-global={@globals["site"]["name"]}
      data-identity={@identity.name}
      data-language={@language}
      data-link={@links["docs"].url}
      data-locale={@locale}
      data-navigation={@navigation["main"].title}
      data-request-missing={is_nil(@request)}
      data-url-missing={is_nil(@url)}
    >
      {@headline}
    </article>
    """

    html =
      Heex.render_module(
        module(code),
        block(),
        %{"headline" => "Hello"},
        %{},
        opts(context)
      )

    assert html =~ ~s(data-config)
    assert html =~ ~s(data-entry="Entry title")
    assert html =~ ~s(data-global="Global name")
    assert html =~ ~s(data-identity="Identity name")
    assert html =~ ~s(data-language="en")
    assert html =~ ~s(data-link="/docs")
    assert html =~ ~s(data-navigation="Main menu")
    assert html =~ "Hello"
  end

  describe "link globals" do
    defp link_globals_context do
      email = %Var{
        type: :link,
        key: "email",
        label: "E-mail",
        link_type: :url,
        value: "mailto:booking@example.com?subject=a&b",
        link_text: "Book us",
        link_target_blank: true
      }

      unsafe = %Var{type: :link, key: "unsafe", label: "Unsafe", link_type: :url, value: "javascript:alert(1)"}
      empty = %Var{type: :link, key: "empty", label: "Empty", link_type: :url, value: nil, link_text: "Nowhere"}
      title = %Var{type: :text, key: "title", label: "Title", value: "Footer"}

      %{}
      |> Brando.Villain.create_context()
      |> Brando.Villain.add_to_context("globals", %{
        "footer" => %{"email" => email, "unsafe" => unsafe, "empty" => empty, "title" => title}
      })
    end

    defp render_with_globals(code),
      do: Heex.render_module(module(code), block(), %{}, %{}, opts(link_globals_context()))

    test "entry_link renders a link global with its text and target" do
      html = render_with_globals(~S(<.entry_link var={@globals["footer"]["email"]} />))

      assert html =~ ~s(href="mailto:booking@example.com?subject=a&amp;b")
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(class="link")
      assert html =~ "Book us"
    end

    test "a printed link global gives its URL, escaped, and text globals stay values" do
      html =
        render_with_globals(~S"""
        <p data-href={@globals["footer"]["email"]}>
          {@globals["footer"]["email"]}|{@globals["footer"]["title"]}
        </p>
        """)

      assert html =~ ~s(data-href="mailto:booking@example.com?subject=a&amp;b")
      assert html =~ "mailto:booking@example.com?subject=a&amp;b|Footer"
    end

    # As its empty value was before HEEx got the var
    test "a link global with no safe address is nil, so :if and || skip it" do
      html =
        render_with_globals(~S"""
        <a :if={@globals["footer"]["empty"]} class="empty">x</a>
        <a :if={@globals["footer"]["unsafe"]} class="unsafe">x</a>
        <span data-fallback={@globals["footer"]["empty"] || "/contact"}></span>
        """)

      refute html =~ ~s(class="empty")
      refute html =~ ~s(class="unsafe")
      refute html =~ "javascript:"
      assert html =~ ~s(data-fallback="/contact")
    end

    test "an interpolated link global gives its URL, not the struct" do
      html = render_with_globals(~S|<a href={"#{@globals["footer"]["email"]}&cc=x"}>x</a>|)

      assert html =~ ~s(href="mailto:booking@example.com?subject=a&amp;b&amp;cc=x")
      refute html =~ "Brando.Content.Var"
    end

    test "a link var printed in Liquid gives its URL, not the struct" do
      link = %Var{type: :link, key: "cta", label: "CTA", link_type: :url, value: "/contact?a=1&b=2"}
      context = Brando.Villain.create_context(%{"cta" => Brando.Villain.Parser.escape_link_var(link)})

      assert Brando.Villain.parse_and_render("<a href=\"{{ cta }}\">x</a>", context) ==
               ~s(<a href="/contact?a=1&amp;b=2">x</a>)
    end

    test "Liquid still reads a link global as its URL" do
      context = link_globals_context()

      assert Brando.Villain.parse_and_render("{{ globals.footer.email }}", context) ==
               "mailto:booking@example.com?subject=a&amp;b"
    end
  end

  test "single modules receive safe defaults for assigns only used by multi and datasource modules" do
    code = """
    <span data-content={@content} data-entries={length(@entries)} data-forloop={inspect(@forloop)}>
      ok
    </span>
    """

    html = Heex.render_module(module(code), block(), %{}, %{}, opts(nil))

    assert html =~ ~s(data-content="")
    assert html =~ ~s(data-entries="0")
    assert html =~ ~s(data-forloop="nil")
  end

  test "HEEx containers receive the same global context as Liquid containers" do
    context = Liquex.Context.new(%{"globals" => %{"site" => %{"name" => "Brando"}}})

    container = %{
      id: System.unique_integer([:positive]),
      code: ~S(<section data-site={@globals["site"]["name"]}><.content /></section>)
    }

    html = Heex.render_container(container, "<strong>Child</strong>", block(), opts(context))

    assert html =~ ~s(data-site="Brando")
    assert html =~ "<strong>Child</strong>"
  end

  test "multi modules and child modules receive content and forloop assigns" do
    context = Liquex.Context.new(%{"language" => "en"})

    parent = module("<section><.content /></section>")

    parent_html =
      Heex.render_multi_module(
        parent,
        block(),
        %{},
        %{},
        [%{uid: "child"}],
        "<strong>Rendered child</strong>",
        opts(context)
      )

    child = module(~S(<span data-index={@forloop["index"]}>{@label}</span>))

    child_html =
      Heex.render_child_module(
        child,
        block(%{uid: "child", module_id: child.id}),
        %{"label" => "Child label"},
        %{},
        %{"index" => 1},
        parent.id,
        opts(context)
      )

    assert parent_html =~ "<strong>Rendered child</strong>"
    assert child_html =~ ~s(data-index="1")
    assert child_html =~ "Child label"
  end

  test "HEEx reserved assigns include every renderer-owned key" do
    reserved = ContentModule.reserved_heex_assigns()

    assert "_heex_ctx" in reserved
    assert "configs" in reserved
    assert "entries_with_meta" in reserved
  end

  test "renderer-owned var keys are rejected for HEEx modules" do
    changeset =
      %ContentModule{type: :heex}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:vars, [
        Ecto.Changeset.change(%Var{key: "_heex_ctx", label: "Internal", type: :string})
      ])
      |> ContentModule.validate_var_keys()

    assert {message, _} = Keyword.fetch!(changeset.errors, :vars)
    assert message =~ "_heex_ctx"
  end
end
