defmodule BrandoAdmin.HiddenBlockFieldTest do
  # `blocks :blocks, hidden: {:title, "Hide the blocks"}` on the test article:
  # the block field follows the form, and a hidden one is still saved, since
  # the save waits for every block field's changesets.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  @wrapper "#article_form-blocks-blocks-wrapper"

  setup %{current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Hide the blocks", slug: "hide-the-blocks", language: "en", status: "published", year: 2020},
        user
      )

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Article.Blocks),
          "refs" => [
            %{
              "uid" => Brando.Utils.generate_uid(),
              "name" => "body",
              "data" => %{"type" => "text", "data" => %{"text" => "Kept"}}
            }
          ]
        },
        user
      )
      |> Repo.insert!()

    struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: 0}) |> Repo.insert!()

    %{article: article}
  end

  test "the block field is hidden while the option applies, and shown when it stops", %{conn: conn, article: article} do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")

    await_selector(view, @wrapper)
    assert has_element?(view, "#{@wrapper}[hidden]")

    view |> form("#article_form_form") |> render_change(%{"article" => %{"title" => "Show the blocks"}})
    assert has_element?(view, @wrapper)
    refute has_element?(view, "#{@wrapper}[hidden]")
  end

  test "a hidden block field still saves, keeping its blocks", %{conn: conn, article: article} do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")
    await_selector(view, "#{@wrapper}[hidden]")

    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)

    {:ok, saved} = SyncTest.get_article(%{matches: %{id: article.id}, preload: Brando.Blueprint.preloads_for(Article)})
    assert [%{block: %{refs: [%{data: %{data: %{text: "Kept"}}}]}}] = saved.entry_blocks
  end
end
