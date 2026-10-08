defmodule BrandoAdmin.AssistantAppliedLiveTest do
  # An applied or undone proposal shows what was applied: its changes against
  # the entries as they were before, not once more on top of the result.
  use Brando.LiveCase
  alias Brando.AI.Agent
  alias Brando.Content.Proposals
  alias Brando.Content.Transfer.Catalog
  alias Brando.Pages.Page

  setup %{current_user: user} do
    Brando.AIStub.configure()
    c = Brando.ProposalFixtures.context()
    Brando.Content.create_identifier(Page, c.identity)
    Brando.ProposalFixtures.multi_context(Map.merge(c, %{current_user: user, user: user}))
  end

  defp open(%{conn: conn, current_user: user}, ops) do
    {:ok, conversation} = Agent.start_conversation(user)
    {:ok, proposal} = Proposals.propose(ops, user, conversation_id: conversation.id)
    conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()
    path = "/admin/assistant/#{conversation.id}"
    {:ok, view, _html} = live(conn, path)
    {view, path}
  end

  defp apply!(view) do
    view |> element("button.assistant-apply") |> render_click()
    assert has_element?(view, "h2", "Applied")
    view
  end

  defp undo!(view) do
    view |> element("button.assistant-undo") |> render_click()
    assert has_element?(view, "h2", "Undone")
    view
  end

  # The proposal loaded again: what an editor sees coming back to it.
  defp reload(path, %{conn: conn}) do
    {:ok, view, _html} = live(conn, path)
    view
  end

  defp card(page), do: ~s([id="card-#{Proposals.Proposal.key({Page, page.id})}"])

  defp order(view, _c, page),
    do: view |> render() |> Floki.parse_document!() |> Floki.find(card(page) <> " .assistant-order li")

  defp names(items), do: Enum.map(items, &(&1 |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()))

  defp new_items(items),
    do: Enum.filter(items, &("is-new" in (&1 |> Floki.attribute("class") |> Enum.flat_map(fn c -> String.split(c) end))))

  defp first_uid(c, page), do: hd(Catalog.load!(Page, page.id, c.current_user).entry_blocks).block.uid

  describe "a copy from another entry" do
    setup c do
      op = %Proposals.CopyBlock{
        target: {Page, c.identity.id},
        block_uid: first_uid(c, c.identity),
        to_target: {Page, c.work.id},
        to_field: "blocks",
        placement: {:before, c.intro_uid}
      }

      Map.put(c, :ops, [op])
    end

    test "is shown once after apply, after undo, and when the entry changes after undo", c do
      {view, path} = open(c, c.ops)
      reviewed = order(view, c, c.work)
      assert length(reviewed) == 3
      assert length(new_items(reviewed)) == 1

      apply!(view)
      assert length(Catalog.load!(Page, c.work.id, c.current_user).entry_blocks) == 3
      applied = order(view, c, c.work)
      assert names(applied) == names(reviewed)
      assert length(new_items(applied)) == 1
      assert names(order(reload(path, c), c, c.work)) == names(reviewed)

      undo!(view)
      assert names(order(view, c, c.work)) == names(reviewed)

      # Removing the intro after the undo does not change what was applied.
      [intro | _] = Catalog.load!(Page, c.work.id, c.current_user).entry_blocks
      Brando.Repo.delete!(intro)
      assert names(order(reload(path, c), c, c.work)) == names(reviewed)
    end
  end

  test "a copy in the same entry is shown once after apply", c do
    [alpha | _] = c.child_uids
    {view, _} = open(c, [%Proposals.CopyBlock{target: {Page, c.work.id}, block_uid: alpha}])
    reviewed = order(view, c, c.work)
    assert length(reviewed) == 4

    apply!(view)
    applied = order(view, c, c.work)
    assert names(applied) == names(reviewed)
    assert length(new_items(applied)) == 1
  end

  test "settings, moves and removals show what they were before", c do
    [alpha, beta, gamma] = c.child_uids
    target = {Page, c.work.id}

    {view, _} =
      open(c, [
        %Proposals.SetBlockValues{target: target, block_uid: beta, values: %{size: "50"}},
        %Proposals.MoveBlock{target: target, block_uid: gamma, placement: {:before, beta}},
        %Proposals.DeleteBlock{target: target, block_uid: alpha}
      ])

    reviewed = order(view, c, c.work)
    apply!(view)

    assert has_element?(view, ".assistant-change-title", "Change settings of “Project” · 2 of 3 in “Projects” · Beta")
    assert has_element?(view, ".assistant-fields del", "Full (100)")
    assert has_element?(view, ".assistant-fields ins", "Half (50)")
    assert has_element?(view, ".assistant-change-title.is-removal", "Remove “Project” · 1 of 3 in “Projects” · Alpha")
    assert names(order(view, c, c.work)) == names(reviewed)
    assert has_element?(view, ".assistant-order li.is-moved", "Gamma")

    undo!(view)
    assert has_element?(view, ".assistant-fields del", "Full (100)")
    assert has_element?(view, ".assistant-change-title.is-removal", "Remove “Project” · 1 of 3 in “Projects” · Alpha")
  end

  test "a field shows its value before", c do
    {view, _} = open(c, [%Proposals.SetFields{target: {Page, c.work.id}, fields: %{"title" => "Work, renamed"}}])
    apply!(view)

    assert has_element?(view, ".assistant-fields del", ~r/^\s*Work\s*$/)
    assert has_element?(view, ".assistant-fields ins", "Work, renamed")
  end

  test "a block inserted into a container is placed among the blocks that were there", c do
    [alpha | _] = c.child_uids

    {view, _} =
      open(c, [
        %Proposals.InsertBlock{
          target: {Page, c.work.id},
          module: c.project_module.id,
          parent: c.multi_uid,
          placement: {:before, alpha}
        }
      ])

    placement = "Before “Project” · 1 of 3 in “Projects” · Alpha"
    assert has_element?(view, ".assistant-placement", placement)

    apply!(view)
    [_, multi] = Catalog.load!(Page, c.work.id, c.current_user).entry_blocks
    assert length(multi.block.children) == 4
    assert has_element?(view, ".assistant-placement", placement)
  end

  describe "the card's address" do
    setup c do
      draft = Brando.Factory.insert(:page, creator: c.user, title: "Draft", uri: "draft", status: :draft)
      norsk = Brando.Factory.insert(:page, creator: c.user, title: "Norsk", uri: "norsk", language: :no)

      ops =
        for page <- [c.work, draft, norsk],
            do: %Proposals.SetFields{target: {Page, page.id}, fields: %{"title" => "#{page.title}!"}}

      Map.merge(c, %{draft: draft, norsk: norsk, ops: ops})
    end

    test "a published entry links to its public URL in its own language, a draft to its preview", c do
      {view, _} = open(c, c.ops)
      host = Brando.Utils.hostname()
      work_url = Path.join(host, Brando.Blueprint.URL.resolve(c.work))

      assert has_element?(view, card(c.work) <> ~s( a.assistant-address[href="#{work_url}"][target="_blank"]))
      refute work_url =~ "/no/"
      assert has_element?(view, card(c.norsk) <> ~s( a.assistant-address[href="#{host}/no/norsk"]))

      refute has_element?(view, card(c.draft) <> " a.assistant-address")
      assert has_element?(view, card(c.draft) <> " .assistant-draft")

      # The test app's default Page view cannot render pages (see
      # AssistantLiveTest's page preview): the editor is told. The E2E spec
      # opens the preview.
      Brando.endpoint().subscribe("user:#{c.current_user.id}")
      view |> element(card(c.draft) <> " button.assistant-saved-preview") |> render_click()
      assert_receive %{event: "toast", payload: %{payload: "The page could not be rendered: " <> _}}

      # After apply, the card links to the page as it is now.
      apply!(view)
      assert has_element?(view, card(c.work) <> ~s( a.assistant-address[href="#{work_url}"]))
      assert has_element?(view, card(c.draft) <> " button.assistant-saved-preview")
    end

    test "a draft published as it is applied links to its page", c do
      {view, _} = open(c, c.ops)

      view
      |> element(~s(input[phx-click="toggle_publish"][phx-value-key="#{Proposals.Proposal.key({Page, c.draft.id})}"]))
      |> render_click()

      apply!(view)

      assert has_element?(view, card(c.draft) <> ~s( a.assistant-address[href="#{Brando.Utils.hostname()}/en/draft"]))
      refute has_element?(view, card(c.draft) <> " .assistant-draft")
    end
  end
end
