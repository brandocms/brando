defmodule BrandoAdmin.StartingModulesTest do
  # An empty block field offers the modules it usually starts with. Clicking
  # one inserts it as the first block, through the module picker's insert.
  use Brando.LiveCase

  alias Brando.Content.StartingModules
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  setup %{current_user: user} do
    Brando.Cache.del(StartingModules.cache_key(Article.Blocks, "en"))

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Opening text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          class: "opening",
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Empty article", slug: "empty-article", language: "en", status: "published", year: 2020},
        user
      )

    %{article: article, module: module}
  end

  test "an empty field offers its modules, and a tile inserts the module first", %{conn: conn} = c do
    {view, _html} = live_form(conn, "/admin/articles/update/#{c.article.id}", "article_form")
    await_selector(view, "[data-testid=blocks-welcome]")

    ref = "local:#{c.module.id}"
    assert has_element?(view, "[data-testid=starting-module][data-module-ref='#{ref}']")
    assert has_element?(view, "[data-testid=all-modules]")
    # Too little content to count: no "first in" counts.
    refute has_element?(view, "[data-testid=starting-module-count]")
    # The superuser is told where templates are added.
    assert has_element?(view, ".blocks-welcome-note a[href='/admin/config/content/templates']")

    view |> element("[data-testid=starting-module][data-module-ref='#{ref}']") |> render_click()
    await_selector(view, "[data-block-uid]")
    refute has_element?(view, "[data-testid=blocks-welcome]")

    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)

    {:ok, saved} =
      SyncTest.get_article(%{matches: %{id: c.article.id}, preload: Brando.Blueprint.preloads_for(Article)})

    assert [%{block: %{module_id: module_id, type: :module}}] = saved.entry_blocks
    assert module_id == c.module.id
  end

  test "a module the field does not offer is not inserted", %{conn: conn} = c do
    {view, _html} = live_form(conn, "/admin/articles/update/#{c.article.id}", "article_form")
    await_selector(view, "[data-testid=blocks-welcome]")

    view
    |> element("[data-testid=starting-module][data-module-ref='local:#{c.module.id}']")
    |> render_click(%{"module" => "local:999999"})

    assert has_element?(view, "[data-testid=blocks-welcome]")
    refute has_element?(view, "[data-block-uid]")
  end
end
