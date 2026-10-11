defmodule BrandoAdmin.BlockMoveMenuTest do
  # "Move up" and "Move down" in a block's menu move it among its siblings
  # through the parent's `reposition`, the path a drag takes: root blocks in
  # the block field, children in their container or multi module. A move
  # past either end does nothing.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Form.Block, as: BlockComponent

  setup do
    c = Brando.ProposalFixtures.context()
    Brando.ProposalFixtures.multi_context(c)
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp move(view, uid, direction) do
    view |> element("#block-#{uid}-dropdown [data-block-move=#{direction}]") |> render_click()
    render(view)
  end

  defp order(html, prefix, uids) do
    ~r/id="#{prefix}-([^"]+)"/
    |> Regex.scan(html)
    |> Enum.map(&List.last/1)
    |> Enum.filter(&(&1 in uids))
  end

  defp save(view) do
    view |> element("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> element("#page_form_form") |> render_submit()
  end

  defp saved_root_order(page) do
    Repo.all(
      from(pb in Page.Blocks,
        join: b in Block,
        on: b.id == pb.block_id,
        where: pb.entry_id == ^page.id,
        order_by: [asc: pb.sequence, asc: pb.id],
        select: b.uid
      )
    )
  end

  defp saved_child_order(parent_uid) do
    Repo.all(
      from(b in Block,
        join: p in Block,
        on: p.id == b.parent_id,
        where: p.uid == ^parent_uid,
        order_by: [asc: b.sequence, asc: b.id],
        select: b.uid
      )
    )
  end

  test "finds where a block goes, and stops at either end" do
    assert BlockComponent.move_positions(~w(a b c), "b", -1) == {1, 0}
    assert BlockComponent.move_positions(~w(a b c), "b", 1) == {1, 2}
    assert BlockComponent.move_positions(~w(a b c), "a", -1) == nil
    assert BlockComponent.move_positions(~w(a b c), "c", 1) == nil
    assert BlockComponent.move_positions(~w(a b c), "x", 1) == nil
  end

  test "root blocks move up and down, and the order is saved", %{conn: conn} = c do
    view = open(conn, c.work)
    roots = [c.intro_uid, c.multi_uid]

    html = move(view, c.multi_uid, "up")
    assert order(html, "base", roots) == [c.multi_uid, c.intro_uid]

    # Already first: nothing moves
    html = move(view, c.multi_uid, "up")
    assert order(html, "base", roots) == [c.multi_uid, c.intro_uid]

    html = move(view, c.multi_uid, "down")
    assert order(html, "base", roots) == [c.intro_uid, c.multi_uid]

    # Already last
    html = move(view, c.multi_uid, "down")
    assert order(html, "base", roots) == [c.intro_uid, c.multi_uid]

    move(view, c.intro_uid, "down")
    save(view)
    assert saved_root_order(c.work) == [c.multi_uid, c.intro_uid]
  end

  test "a multi module's entries move among themselves, and the order is saved", %{conn: conn} = c do
    view = open(conn, c.work)
    [alpha, beta, gamma] = c.child_uids

    html = move(view, gamma, "up")
    assert order(html, "child", c.child_uids) == [alpha, gamma, beta]

    html = move(view, alpha, "down")
    assert order(html, "child", c.child_uids) == [gamma, alpha, beta]

    html = move(view, beta, "down")
    assert order(html, "child", c.child_uids) == [gamma, alpha, beta]

    save(view)
    assert saved_child_order(c.multi_uid) == [gamma, alpha, beta]
  end

  test "a container's children move among themselves", %{conn: conn} = c do
    container = Brando.ProposalFixtures.root_block!(c, :container, nil, 2)
    first = child_of(c, container, 0)
    second = child_of(c, container, 1)

    view = open(conn, c.work)
    html = move(view, second.uid, "up")
    assert order(html, "child", [first.uid, second.uid]) == [second.uid, first.uid]

    save(view)
    assert saved_child_order(container.uid) == [second.uid, first.uid]
  end

  defp child_of(c, container, sequence) do
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => c.text_module.id,
        "parent_id" => container.id,
        "sequence" => sequence,
        "creator_id" => c.user.id,
        "source" => to_string(Page.Blocks),
        "refs" => [
          %{
            "uid" => Brando.Utils.generate_uid(),
            "name" => "body",
            "data" => %{"type" => "text", "data" => %{"text" => "<p>Child #{sequence}</p>"}}
          }
        ]
      },
      c.user
    )
    |> Repo.insert!()
  end
end
