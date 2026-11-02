defmodule BrandoAdmin.AssistantUnloadableProposalTest do
  # A proposal stored before the content type catalogue was checked can name
  # a type outside it, such as a global set. It is refused at review, approve
  # and apply, and before, the review showed the empty state: no reason and
  # no Discard, so an MCP proposal stayed listed and counted until it expired
  # a day later. Its owner sees why and can discard it; nobody else can.
  use Brando.LiveCase
  use Brando.Test
  import Ecto.Query, only: [from: 2]

  alias Brando.AI.Agent
  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{Record, Tools}
  alias Brando.Test.Users, as: TestUsers

  setup do
    Brando.ProposalFixtures.context()
  end

  # As an earlier version stored it, before the catalogue was checked: a page
  # proposal from a tool connected over MCP, its content type swapped.
  defp crafted(actor, opts \\ []) do
    context = %Tools.Context{
      actor: actor,
      origin: if(opts[:conversation_id], do: :assistant, else: :mcp),
      client: "Claude Code",
      conversation_id: opts[:conversation_id]
    }

    op = %{
      "op" => "create_entry",
      "content_type" => "Brando.Pages.Page",
      "ref" => "rooms",
      "fields" => %{"title" => "Rooms", "uri" => "rooms-stored", "language" => "en"}
    }

    {:ok, %{proposal_id: id}} = Tools.call("prepare_proposal", %{"summary" => "Planted", "operations" => [op]}, context)
    record = Repo.get!(Record, id)
    [stored] = record.operations
    fields = %{"label" => "Planted", "key" => "planted", "language" => "en"}

    record
    |> Ecto.Changeset.change(operations: [%{stored | "content_type" => "Brando.Sites.GlobalSet", "fields" => fields}])
    |> Repo.update!()
  end

  defp status(record), do: Repo.get!(Record, record.id).status

  defp shows_refusal_and_discards(conn, owner, record) do
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{record.id}")
    assert has_element?(view, ~s(#assistant-connected-list a[data-proposal-id="#{record.id}"]))
    assert has_element?(view, "#assistant-unloadable [role=alert]", "list_content_types")
    assert Proposals.count_external(owner) == 1

    view |> element("#assistant-unloadable button[phx-click=cancel_proposal]") |> render_click()

    assert status(record) == "cancelled"
    refute has_element?(view, "#assistant-unloadable")
    refute has_element?(view, ~s(#assistant-connected-list a[data-proposal-id="#{record.id}"]))
    assert Proposals.count_external(owner) == 0
    refute Repo.exists?(from(s in Brando.Sites.GlobalSet, where: s.key == "planted"))
  end

  # Another user who may use the Assistant opens the owner's proposal.
  defp cannot_discard(conn, record) do
    {:ok, view, _} = live(conn, "/admin/assistant/connected/#{record.id}")
    refute has_element?(view, "#assistant-unloadable")
    refute has_element?(view, ~s(button[phx-click="cancel_proposal"]))

    render_click(view, "cancel_proposal", %{})
    assert status(record) == "pending"
  end

  describe "legacy authorization" do
    test "the owner sees why an MCP proposal cannot be applied, and discards it" do
      editor = TestUsers.insert_user(role: :editor)
      record = crafted(editor)
      shows_refusal_and_discards(log_in_user(build_conn(), editor), editor, record)
    end

    test "an approved one too" do
      editor = TestUsers.insert_user(role: :editor)
      record = crafted(editor)
      record |> Ecto.Changeset.change(status: "approved") |> Repo.update!()
      shows_refusal_and_discards(log_in_user(build_conn(), editor), editor, record)
    end

    test "another editor can neither see nor discard it" do
      record = crafted(TestUsers.insert_user(role: :editor))
      other = TestUsers.insert_user(role: :editor)

      cannot_discard(log_in_user(build_conn(), other), record)
      refute Proposals.discardable?(record.id, other)
      assert {:error, _} = Proposals.cancel(record.id, other)
      assert status(record) == "pending"
    end

    test "a conversation's proposal shows the reason and Discard in its conversation" do
      editor = TestUsers.insert_user(role: :editor)
      {:ok, conversation} = Agent.start_conversation(editor)
      record = crafted(editor, conversation_id: conversation.id)

      Repo.update_all(from(cv in Agent.Conversation, where: cv.id == ^conversation.id),
        set: [proposal_id: record.id]
      )

      {:ok, view, _} = live(log_in_user(build_conn(), editor), "/admin/assistant/#{conversation.id}")
      assert has_element?(view, "#assistant-unloadable [role=alert]", "list_content_types")
      view |> element("#assistant-unloadable button[phx-click=cancel_proposal]") |> render_click()

      assert status(record) == "cancelled"
      refute has_element?(view, "#assistant-unloadable")
    end

    test "a discarded one shows no Discard", %{conn: conn, current_user: user} do
      record = crafted(user)
      :ok = Proposals.cancel(record.id, user)

      {:ok, view, _} = live(conn, "/admin/assistant/connected/#{record.id}")
      refute has_element?(view, "#assistant-unloadable")
      refute Proposals.discardable?(record.id, user)
    end
  end

  describe "groups authorization" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      {:ok, _} = Migration.run()
      Map.put(c, :scope, Scope.standalone(c.current_user))
    end

    defp member(c, keys) do
      user = TestUsers.insert_user(role: :editor)
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      user
    end

    defp assistant_member(c), do: member(c, Catalog.preset_permissions(:editor, :standalone) ++ ["brando.assistant.use"])

    test "an Editor-preset member with the Assistant sees why and discards their MCP proposal", c do
      editor = assistant_member(c)
      record = crafted(editor)
      shows_refusal_and_discards(log_in_user(build_conn(), editor), editor, record)
    end

    test "another member with the Assistant can neither see nor discard it", c do
      record = crafted(assistant_member(c))
      other = assistant_member(c)

      cannot_discard(log_in_user(build_conn(), other), record)
      assert {:error, _} = Proposals.cancel(record.id, other)
      assert status(record) == "pending"
    end

    test "a member without the Assistant cannot open the review", c do
      record = crafted(assistant_member(c))
      editor =
        member(c, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:read, Brando.Pages.Page).key,
          Catalog.get(:update, Brando.Pages.Page).key
        ])

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} =
               live(log_in_user(build_conn(), editor), "/admin/assistant/connected/#{record.id}")

      assert status(record) == "pending"
    end
  end
end
