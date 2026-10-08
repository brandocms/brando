defmodule Brando.Test.BlocksTest do
  use Brando.ConnCase, async: false
  use Brando.Test

  alias Brando.Pages.Page

  setup do
    user = insert_user()

    module =
      Brando.ProposalFixtures.module!(
        user,
        "Teaser",
        ~s(<section class="teaser{% if wide %} wide{% endif %}"><h2>{{ heading }}</h2>{% ref refs.body %}{% ref refs.cover %}</section>),
        refs: [
          Brando.ProposalFixtures.ref("body", %{type: "text", data: %{text: "<p>Default body</p>"}}),
          Brando.ProposalFixtures.ref("cover", %{type: "picture", data: %{}})
        ],
        vars: [
          %{type: "string", key: "heading", label: "Heading", value: "Default heading"},
          %{type: "boolean", key: "wide", label: "Wide", value_boolean: false}
        ]
      )

    %{user: user, module: module}
  end

  test "renders a module with its defaults", %{module: module} do
    html = render_block(module)
    assert html =~ ~s(<section class="teaser"><h2>Default heading</h2>)
    assert html =~ "<p>Default body</p>"
  end

  test "renders a module with vars and refs given", %{module: module} do
    html = render_block(module, vars: %{"heading" => "Lobby", "wide" => true}, refs: %{"body" => %{text: "<p>Hi</p>"}})
    assert html =~ ~s(<section class="teaser wide"><h2>Lobby</h2><div class="paragraph"><p>Hi</p></div>)
    refute html =~ "Default"
  end

  test "renders a block, with the entry in the template", %{module: module, user: user} do
    module = %{module | code: "<h1>{{ entry.title }}</h1>{% ref refs.body %}"}
    {:ok, module} = Brando.Content.update_module(module.id, %{code: module.code}, user)
    block = build_block(module, refs: %{"body" => false})

    # A ref switched off leaves a marker, as on the site.
    assert render_block(block, entry: %Page{title: "Identity"}) == "<h1>Identity</h1><!-- !a[body] -->"
  end

  test "names the vars and refs a module has when given others", %{module: module} do
    error = assert_raise ArgumentError, fn -> render_block(module, vars: %{"title" => "x"}) end
    assert error.message =~ ~s(no var "title")
    assert error.message =~ ~s(["heading", "wide"])

    assert_raise ArgumentError, ~r/no ref "image"/, fn -> render_block(module, refs: %{"image" => %{}}) end
  end

  test "adds a block to an entry and renders the entry", %{module: module, user: user} do
    page = insert_entry(Page, %{title: "Identity"}, user: user)
    block = insert_block(page, module, vars: %{"heading" => "Added"}, user: user)

    assert block.id
    page = Brando.Repo.get!(Page, page.id)
    assert page.rendered_blocks =~ "<h2>Added</h2>"
  end

  test "an entry can be inserted with blocks", %{module: module, user: user} do
    page = insert_entry(Page, %{}, user: user, blocks: [module, {module, vars: %{"heading" => "Second"}}])

    assert page.rendered_blocks =~ ~r/Default heading.*Second/s
    assert length(page.entry_blocks) == 2
  end
end
