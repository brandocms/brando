defmodule BrandoAdmin.MediaSlotFileTest do
  # A media ref is a slot: the editor picks what it holds. A module can offer
  # a file there, next to pictures and videos (an animation file, a PDF).
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  setup %{current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Media"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.media %}",
          refs: [
            %{
              name: "media",
              uid: Brando.Utils.generate_uid(),
              data: %{
                type: "media",
                data: %{available_blocks: ["picture", "file"], template_file: %{class: "animation", download: false}}
              }
            }
          ]
        ),
        user
      )

    {:ok, article} =
      SyncTest.create_article(
        %{title: "An article", slug: "an-article", language: "en", status: "published", year: 2020},
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
              "name" => "media",
              "data" => %{
                "type" => "media",
                "data" => %{
                  "available_blocks" => ["picture", "file"],
                  "template_file" => %{"class" => "animation", "download" => false}
                }
              }
            }
          ]
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(struct(Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: 0}))

    %{article: article, block: block}
  end

  test "the slot offers the file, and choosing it makes the ref a file with the module's settings",
       %{conn: conn} = c do
    {view, _html} = live_form(conn, "/admin/articles/update/#{c.article.id}", "article_form")
    await_selector(view, "button[phx-value-block=file]")

    assert has_element?(view, "button[phx-value-block=picture]")
    refute has_element?(view, "button[phx-value-block=video]")

    view |> element("button[phx-value-block=file]") |> render_click()
    await_selector(view, ".file-block")
    refute has_element?(view, "button[phx-value-block=file]")

    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)

    {:ok, saved} =
      SyncTest.get_article(%{matches: %{id: c.article.id}, preload: Brando.Blueprint.preloads_for(Article)})

    assert [%{block: %{refs: [ref]}}] = saved.entry_blocks
    assert ref.data.type == "file"
    assert ref.data.data.class == "animation"
    assert ref.data.data.download == false
  end
end
