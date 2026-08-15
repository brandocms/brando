defmodule Brando.Villain.TemplateAdapter.HeexTest do
  use ExUnit.Case, async: false

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
