defmodule BrandoAdmin.EditSessionLiveTest do
  # Two editors with one entry open, through real LiveViews: the edit session
  # (`Brando.EditSession`) orders their block ops, gives a joiner the unsaved
  # state, survives being killed, and takes an applied Assistant proposal in
  # without a reload.
  use Brando.LiveCase

  import Brando.EditSessionEditors

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.EditSession
  alias Brando.Pages.Page

  setup %{current_user: user} do
    c = Brando.ProposalFixtures.context()
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
    uids = c.identity |> rows() |> Enum.map(& &1.block.uid)
    Map.merge(c, %{other_conn: other_conn, uids: uids, me: user})
  end

  defp texts(page), do: Enum.map(rows(page), &hd(&1.block.refs).data.data.text)

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp save(view) do
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#page_form_form") |> render_submit()
    assert_redirect(view, 3_000)
  end

  defp session(page), do: EditSession.whereis(EditSession.ref(Page, page.id, page.language))

  test "a joiner sees the unsaved edit, and the first editor's later edits arrive live", c do
    [first, second | _] = c.uids
    a = open(c.conn, c.identity)
    type(a, first, "<p>Unsaved by A</p>")

    b = open(c.other_conn, c.identity)
    assert shown_text(b, first) == "<p>Unsaved by A</p>"

    type(a, second, "<p>Typed while B watches</p>")
    await(fn -> shown_text(b, second) == "<p>Typed while B watches</p>" end)

    # Nothing was written.
    assert hd(texts(c.identity)) == "<p>Identity 0</p>"
  end

  test "a save keeps the other editor's unsaved work and moves both onto the saved rows", c do
    [first, second | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)

    type(b, second, "<p>B, unsaved</p>")
    type(a, first, "<p>A saves this</p>")
    await(fn -> shown_text(a, second) == "<p>B, unsaved</p>" end)

    save(a)

    # The save read the session, so B's edit went in with A's.
    assert Enum.take(texts(c.identity), 2) == ["<p>A saves this</p>", "<p>B, unsaved</p>"]

    type(b, second, "<p>B, after A's save</p>")
    save(b)

    assert texts(c.identity) == ["<p>A saves this</p>", "<p>B, after A's save</p>", "<p>Identity 2</p>"]
    assert length(rows(c.identity)) == 3
  end

  test "killing the session loses nothing: the editors re-seed a new one", c do
    [first, second | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    type(a, first, "<p>Before the crash</p>")
    await(fn -> shown_text(b, first) == "<p>Before the crash</p>" end)

    old = session(c.identity)
    Process.exit(old, :kill)
    await(fn -> session(c.identity) not in [nil, old] end)

    # Both editors still edit together, through the new session.
    type(b, second, "<p>After the crash</p>")
    await(fn -> shown_text(a, second) == "<p>After the crash</p>" end)
    assert shown_text(b, first) == "<p>Before the crash</p>"

    save(a)
    assert Enum.take(texts(c.identity), 2) == ["<p>Before the crash</p>", "<p>After the crash</p>"]
  end

  test "an Assistant proposal applied while the entry is open arrives without a reload", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    type(a, first, "<p>Unsaved while the assistant works</p>")

    op = %InsertBlock{
      target: {Page, c.identity.id},
      module: c.case_module.id,
      placement: {:after, first},
      values: %{heading: "From the assistant"}
    }

    {:ok, proposal} = Proposals.propose([op], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _receipt} = Proposals.apply(proposal.id, proposal.version, c.user)

    [_first, inserted | _] = rows(c.identity)
    await(fn -> render(a) =~ ~s(data-block-uid="#{inserted.block.uid}") end)

    # The editor's own unsaved text survived, and the same LiveView is live.
    assert shown_text(a, first) == "<p>Unsaved while the assistant works</p>"

    save(a)
    saved = rows(c.identity)
    assert length(saved) == 4
    assert Enum.map(saved, & &1.block.uid) |> Enum.at(1) == inserted.block.uid

    assert hd(saved).block.refs |> hd() |> Map.get(:data) |> Map.get(:data) |> Map.get(:text) ==
             "<p>Unsaved while the assistant works</p>"
  end
end
