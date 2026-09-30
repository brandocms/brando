defmodule BrandoAdmin.StartFromTemplateTest do
  # An empty block field offers the content templates of its namespace (here
  # the one named after the schema, "articles"). Choosing one fills the field
  # with copies of the template's blocks.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Content.StartingTemplates
  alias Brando.Content.Template
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

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

    template = template!("Article start", "articles", ["From the template", "And a second block"], module, user)
    _other = template!("Project start", "projects", ["Not for articles"], module, user)

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Empty article", slug: "empty-article", language: "en", status: "published", year: 2020},
        user
      )

    %{article: article, template: template}
  end

  defp template!(name, namespace, texts, module, user) do
    template =
      Repo.insert!(%Template{name: name, namespace: namespace, instructions: "A good start", creator_id: user.id})

    texts
    |> Enum.with_index()
    |> Enum.each(fn {text, sequence} ->
      block =
        %Block{}
        |> Block.recursive_block_changeset(
          %{
            "uid" => Brando.Utils.generate_uid(),
            "type" => "module",
            "module_id" => module.id,
            "creator_id" => user.id,
            "source" => to_string(Template.Blocks),
            "refs" => [
              %{
                "uid" => Brando.Utils.generate_uid(),
                "name" => "body",
                "data" => %{"type" => "text", "data" => %{"text" => text}}
              }
            ]
          },
          user
        )
        |> Repo.insert!()

      Repo.insert!(struct(Template.Blocks, %{entry_id: template.id, block_id: block.id, sequence: sequence}))
    end)

    template
  end

  test "the templates of the schema's namespace are listed, with their blocks", c do
    assert [%{name: "Article start", block_count: 2, instructions: "A good start", modules: [_, _]} = summary] =
             StartingTemplates.list(Article)

    assert summary.id == c.template.id
    assert [%{name: "Project start"}] = StartingTemplates.list(Article, "Projects")
    assert StartingTemplates.list(Article, "nothing-here") == []
  end

  test "an empty field offers the template; choosing it fills the field with copies", %{conn: conn} = c do
    {view, _html} = live_form(conn, "/admin/articles/update/#{c.article.id}", "article_form")
    await_selector(view, "[data-testid=blocks-welcome]")

    html = render(view)
    assert html =~ "Article start"
    refute html =~ "Project start"

    view |> element("[data-testid=start-from-template]") |> render_click()
    await_selector(view, "[data-block-uid]")
    refute has_element?(view, "[data-testid=blocks-welcome]")

    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)

    {:ok, saved} =
      SyncTest.get_article(%{matches: %{id: c.article.id}, preload: Brando.Blueprint.preloads_for(Article)})

    blocks = saved.entry_blocks |> Enum.sort_by(& &1.sequence) |> Enum.map(& &1.block)
    assert ["From the template", "And a second block"] = Enum.map(blocks, &hd(&1.refs).data.data.text)
    assert Enum.map(blocks, & &1.source) == [Article.Blocks, Article.Blocks]

    # Copies: the template keeps its own blocks.
    template_block_ids = Enum.map(StartingTemplates.blocks(c.template.id), & &1.id)
    assert length(template_block_ids) == 2
    assert Enum.all?(blocks, &(&1.id not in template_block_ids))
  end
end
