defmodule BrandoAdmin.LockedBlockMoveTest do
  # A synchronized translation's blocks follow its source: moving a child,
  # from the block menu or by a drag's `reposition`, is refused with a
  # notice, and the order the editor sees is the order that stays.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations

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

    {:ok, source} =
      SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published", year: 2020}, user)

    child = fn text, sequence ->
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => module.id,
        "creator_id" => user.id,
        "sequence" => sequence,
        "source" => to_string(Article.Blocks),
        "refs" => [
          %{
            "uid" => Brando.Utils.generate_uid(),
            "name" => "body",
            "data" => %{"type" => "text", "data" => %{"text" => text}}
          }
        ]
      }
    end

    container =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "container",
          "creator_id" => user.id,
          "source" => to_string(Article.Blocks),
          "children" => [child.("Første", 0), child.("Andre", 1)]
        },
        user
      )
      |> Repo.insert!()

    struct(Article.Blocks, %{entry_id: source.id, block_id: container.id, sequence: 0}) |> Repo.insert!()
    {:ok, target} = Translations.create_target(Article, source.id, :en, user)

    %{target: target}
  end

  defp children(target_id) do
    {:ok, entry} =
      SyncTest.get_article(%{matches: %{id: target_id}, preload: Brando.Blueprint.preloads_for(Article)})

    [join] = entry.entry_blocks
    {join.block.uid, join.block.children |> Enum.sort_by(& &1.sequence) |> Enum.map(& &1.uid)}
  end

  defp shown(view, uids) do
    ~r/id="child-([^"]+)"/
    |> Regex.scan(render(view))
    |> Enum.map(&List.last/1)
    |> Enum.filter(&(&1 in uids))
  end

  defp open(conn, id) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{id}", "article_form")
    await_selector(view, ".blocks-wrapper.is-source-locked")
    view
  end

  test "Move up on a child is refused, and the order stays", %{conn: conn, current_user: user, target: target} do
    {_container, [first, second] = uids} = children(target.id)
    view = open(conn, target.id)
    Brando.endpoint().subscribe("user:#{user.id}")

    view |> element("#block-#{second}-dropdown [data-block-move=up]") |> render_click()

    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Blocks in this translation" <> _}},
                   2_000

    assert shown(view, uids) == [first, second]
  end

  test "a drag's reposition of a child is refused, and the order stays",
       %{conn: conn, current_user: user, target: target} do
    {container, [first, second] = uids} = children(target.id)
    view = open(conn, target.id)
    Brando.endpoint().subscribe("user:#{user.id}")

    # What the container's sortable list sends when a child is dropped
    view
    |> with_target("#base-#{container} > div")
    |> render_hook("reposition", %{"uid" => second, "old" => 1, "new" => 0, "parent_uid" => container})

    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}, 2_000
    assert shown(view, uids) == [first, second]
  end
end
