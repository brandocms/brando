defmodule BrandoAdmin.BlockMoveBetweenRowsTest do
  # A multi module's entry moves to another block of the same multi module:
  # dragged on the canvas (the source row's `reposition`, with the row it
  # was dropped in) or in the Outline (`outline_reposition`). The store takes
  # the move before either row shows it, so a move it refuses leaves the
  # entry in its own row, never in both and never in neither.
  # Grouped, one at a time: ProposalFixtures.context/0 inserts the pages "identity" and
  # "naming", whose URIs concurrent transactions would wait on
  use Brando.LiveCase, async: true, group: :shared_locks

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Pages.Page

  setup do
    c = Brando.ProposalFixtures.context()
    c = Brando.ProposalFixtures.multi_context(c)
    row = Brando.ProposalFixtures.root_block!(c, :module, c.projects_module, 2)
    delta = entry!(c, row, 0)
    Map.merge(c, %{row_uid: row.uid, delta_uid: delta.uid})
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # The children a row shows, in order.
  defp shown(view, row_uid) do
    html = view |> element(children(row_uid)) |> render()

    ~r/<div[^>]+id="child-([^"]+)"[^>]+data-parent_uid="#{row_uid}"/
    |> Regex.scan(html)
    |> Enum.map(&List.last/1)
  end

  defp children(row_uid), do: ~s(.block-children[data-parent-uid="#{row_uid}"])

  defp drop_on_canvas(view, uid, from_uid, old, to_uid, new) do
    view
    |> with_target(cid_of(view, children(from_uid)))
    |> render_hook("reposition", %{
      "uid" => uid,
      "parent_uid" => from_uid,
      "old" => old,
      "new" => new,
      "from" => %{"parentUid" => from_uid},
      "to" => %{"parentUid" => to_uid}
    })

    render(view)
  end

  defp drop_in_outline(view, uid, from_uid, old, to_uid, new) do
    view
    |> with_target(cid_of(view, "#block-field-blocks"))
    |> render_hook("outline_reposition", %{
      "uid" => uid,
      "old" => old,
      "new" => new,
      "from" => %{"parentUid" => from_uid},
      "to" => %{"parentUid" => to_uid}
    })

    render(view)
  end

  defp save(view) do
    view |> element("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> element("#page_form_form") |> render_submit()
  end

  defp saved_children(parent_uid) do
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

  test "an entry dragged into another row on the canvas moves there, and is saved there", %{conn: conn} = c do
    view = open(conn, c.work)
    [alpha, beta, gamma] = c.child_uids

    drop_on_canvas(view, beta, c.multi_uid, 1, c.row_uid, 1)

    assert shown(view, c.multi_uid) == [alpha, gamma]
    assert shown(view, c.row_uid) == [c.delta_uid, beta]

    save(view)

    assert_eventually(fn -> saved_children(c.row_uid) == [c.delta_uid, beta] end)
    assert saved_children(c.multi_uid) == [alpha, gamma]
    # it went with its content
    assert [%{refs: refs}] = Repo.all(from(b in Block, where: b.uid == ^beta, preload: :refs))
    assert Enum.any?(refs, &(&1.name == "info" and &1.data.data.text == "<p>Beta</p>"))
  end

  test "an entry dragged into another row in the Outline moves there", %{conn: conn} = c do
    view = open(conn, c.work)
    [alpha, beta, gamma] = c.child_uids

    drop_in_outline(view, alpha, c.multi_uid, 0, c.row_uid, 0)

    assert shown(view, c.multi_uid) == [beta, gamma]
    assert shown(view, c.row_uid) == [alpha, c.delta_uid]
  end

  # The row is gone from the store (another editor deleted it) while this
  # editor still showed it. The move used to let the entry go from its row
  # before the store refused it, and the entry was shown nowhere.
  test "a move the store refuses leaves the entry in its row", %{conn: conn} = c do
    view = open(conn, c.work)
    [alpha, beta, gamma] = c.child_uids

    drop_in_outline(view, beta, c.multi_uid, 1, "gone", 0)
    assert shown(view, c.multi_uid) == [alpha, beta, gamma]

    drop_on_canvas(view, beta, c.multi_uid, 1, "gone", 0)
    assert shown(view, c.multi_uid) == [alpha, beta, gamma]
    assert shown(view, c.row_uid) == [c.delta_uid]
  end

  # The outline used to tell the rows by the id a root's component has, and
  # missed a row inside a container: the entry was let go and shown nowhere.
  test "an entry moves into a multi block inside a container, and back out", %{conn: conn} = c do
    container = Brando.ProposalFixtures.root_block!(c, :container, nil, 3)

    nested =
      block!(c, %{"type" => "module", "module_id" => c.projects_module.id, "multi" => true, "parent_id" => container.id})

    epsilon = entry!(c, nested, 0)
    [alpha, beta, gamma] = c.child_uids

    view = open(conn, c.work)

    drop_in_outline(view, alpha, c.multi_uid, 0, nested.uid, 1)
    assert shown(view, c.multi_uid) == [beta, gamma]
    assert shown(view, nested.uid) == [epsilon.uid, alpha]

    drop_on_canvas(view, epsilon.uid, nested.uid, 0, c.multi_uid, 0)
    assert shown(view, c.multi_uid) == [epsilon.uid, beta, gamma]
    assert shown(view, nested.uid) == [alpha]
  end

  # The rows that take an entry are the ones the canvas and the Outline drag
  # it to (`Block.multi_children_group/2`). An event written by hand, naming
  # any other block of the field, used to move the entry there: it was saved
  # under a plain module or a container, and shown nowhere.
  test "a block that does not take the entry is refused, on the canvas and in the Outline", %{conn: conn} = c do
    container = Brando.ProposalFixtures.root_block!(c, :container, nil, 3)

    other_multi =
      Brando.ProposalFixtures.module!(c.user, "Other projects", ~s(<section>{{ content }}</section>), multi: true)

    other_row = Brando.ProposalFixtures.root_block!(c, :module, other_multi, 4)
    [alpha, beta, gamma] = c.child_uids
    view = open(conn, c.work)

    for to_uid <- [c.intro_uid, container.uid, other_row.uid] do
      drop_on_canvas(view, beta, c.multi_uid, 1, to_uid, 0)
      drop_in_outline(view, alpha, c.multi_uid, 0, to_uid, 0)
    end

    assert shown(view, c.multi_uid) == [alpha, beta, gamma]

    save(view)

    assert_eventually(fn -> saved_children(c.row_uid) == [c.delta_uid] end)
    assert saved_children(c.multi_uid) == [alpha, beta, gamma]
    assert saved_children(c.intro_uid) == []
    assert saved_children(container.uid) == []
    assert saved_children(other_row.uid) == []
  end

  defp assert_eventually(fun, tries \\ 50) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition never held")

      true ->
        Process.sleep(50)
        assert_eventually(fun, tries - 1)
    end
  end

  defp entry!(c, row, sequence) do
    block!(c, %{
      "type" => "module_entry",
      "module_id" => c.project_module.id,
      "parent_id" => row.id,
      "sequence" => sequence,
      "refs" => [
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "info",
          "data" => %{"type" => "text", "data" => %{"text" => "<p>Delta</p>"}}
        }
      ]
    })
  end

  defp block!(c, attrs) do
    %Block{}
    |> Block.recursive_block_changeset(
      Map.merge(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "sequence" => 0,
          "creator_id" => c.user.id,
          "source" => to_string(Page.Blocks)
        },
        attrs
      ),
      c.user
    )
    |> Repo.insert!()
  end
end
