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

  # A page proposal from a tool connected over MCP, or from a conversation.
  defp prepared(actor, opts) do
    context = %Tools.Context{
      actor: actor,
      origin: if(opts[:conversation_id], do: :assistant, else: :mcp),
      client: "Claude Code",
      conversation_id: opts[:conversation_id]
    }

    uri = Keyword.get(opts, :uri, "rooms-stored")

    op = %{
      "op" => "create_entry",
      "content_type" => "Brando.Pages.Page",
      "ref" => "rooms",
      "fields" => %{"title" => "Rooms", "uri" => uri, "language" => "en"}
    }

    {:ok, %{proposal_id: id}} = Tools.call("prepare_proposal", %{"summary" => "Planted", "operations" => [op]}, context)
    Repo.get!(Record, id)
  end

  # As an earlier version stored it, before the catalogue was checked: a page
  # proposal, its content type swapped.
  defp crafted(actor, opts \\ []) do
    record = prepared(actor, opts)
    [stored] = record.operations
    fields = %{"label" => "Planted", "key" => "planted", "language" => "en"}

    record
    |> Ecto.Changeset.change(operations: [%{stored | "content_type" => "Brando.Sites.GlobalSet", "fields" => fields}])
    |> Repo.update!()
  end

  defp status(record), do: Repo.get!(Record, record.id).status

  defp set_proposal(conversation, record) do
    Repo.update_all(from(cv in Agent.Conversation, where: cv.id == ^conversation.id), set: [proposal_id: record.id])
  end

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

    render_click(view, "cancel_proposal", %{"id" => record.id})
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

    # The error belongs to the proposal it came with: after Discard, the
    # assistant's next, valid proposal shows without it.
    test "a conversation's next proposal shows no error from the discarded one" do
      editor = TestUsers.insert_user(role: :editor)
      {:ok, conversation} = Agent.start_conversation(editor)
      record = crafted(editor, conversation_id: conversation.id)
      set_proposal(conversation, record)

      {:ok, view, _} = live(log_in_user(build_conn(), editor), "/admin/assistant/#{conversation.id}")
      view |> element("#assistant-unloadable button[phx-click=cancel_proposal]") |> render_click()
      assert status(record) == "cancelled"

      next = prepared(editor, conversation_id: conversation.id, uri: "rooms-next")
      set_proposal(conversation, next)
      send(view.pid, {:agent, conversation.id, {:proposal, next.id}})

      assert has_element?(view, "#proposal-#{next.id}")
      refute has_element?(view, ".assistant-feedback.is-error")
      refute has_element?(view, "[role=alert]", "list_content_types")
    end

    # A click made before the review changed to another proposal names the
    # one it was made on; the one on screen now stays.
    test "Discard naming another proposal than the one on screen discards nothing" do
      editor = TestUsers.insert_user(role: :editor)
      unloadable = crafted(editor)
      loadable = prepared(editor, uri: "rooms-loadable")
      conn = log_in_user(build_conn(), editor)

      {:ok, view, _} = live(conn, "/admin/assistant/connected/#{loadable.id}")
      assert has_element?(view, ~s(.assistant-apply-bar button[phx-click=cancel_proposal][phx-value-id="#{loadable.id}"]))
      render_click(view, "cancel_proposal", %{"id" => unloadable.id})
      assert {status(loadable), status(unloadable)} == {"pending", "pending"}
      assert has_element?(view, "#proposal-#{loadable.id}")

      {:ok, view, _} = live(conn, "/admin/assistant/connected/#{unloadable.id}")

      assert has_element?(
               view,
               ~s(#assistant-unloadable button[phx-click=cancel_proposal][phx-value-id="#{unloadable.id}"])
             )

      render_click(view, "cancel_proposal", %{"id" => loadable.id})
      assert {status(loadable), status(unloadable)} == {"pending", "pending"}
      assert has_element?(view, "#assistant-unloadable")
    end

    test "from an unloadable proposal to a loadable one, Discard discards the one on screen" do
      editor = TestUsers.insert_user(role: :editor)
      unloadable = crafted(editor)
      loadable = prepared(editor, uri: "rooms-loadable")

      {:ok, view, _} = live(log_in_user(build_conn(), editor), "/admin/assistant/connected/#{unloadable.id}")
      assert has_element?(view, "#assistant-unloadable [role=alert]", "list_content_types")

      render_patch(view, "/admin/assistant/connected/#{loadable.id}")
      assert has_element?(view, "#proposal-#{loadable.id}")
      refute has_element?(view, "#assistant-unloadable")
      refute has_element?(view, ".assistant-feedback.is-error")

      view |> element(".assistant-apply-bar button[phx-click=cancel_proposal]") |> render_click()
      assert {status(loadable), status(unloadable)} == {"cancelled", "pending"}
      refute has_element?(view, "#assistant-unloadable")
      refute has_element?(view, ".assistant-feedback.is-error")
    end

    # The address is taken meanwhile, so applying fails and rolls back.
    defp applies_and_fails(path, editor) do
      {:ok, _} =
        Brando.Pages.create_page(
          %{title: "Taken", uri: "rooms-taken", language: "en", template: "default.html", status: :draft},
          editor
        )

      {:ok, view, _} = live(log_in_user(build_conn(), editor), path)
      view |> element("button.assistant-apply") |> render_click()
      view
    end

    test "a URL naming the proposal in upper case keeps a failed apply's error on screen" do
      editor = TestUsers.insert_user(role: :editor)
      record = prepared(editor, uri: "rooms-taken")
      view = applies_and_fails("/admin/assistant/connected/#{String.upcase(record.id)}", editor)
      assert has_element?(view, "#proposal-#{record.id} .assistant-feedback.is-error")
    end

    test "a failed apply's error goes once the proposal is discarded" do
      editor = TestUsers.insert_user(role: :editor)
      record = prepared(editor, uri: "rooms-taken")
      view = applies_and_fails("/admin/assistant/connected/#{record.id}", editor)
      assert has_element?(view, "#proposal-#{record.id} .assistant-feedback.is-error")

      view |> element(".assistant-apply-bar button[phx-click=cancel_proposal]") |> render_click()
      assert status(record) == "cancelled"
      assert has_element?(view, "#proposal-#{record.id}")
      refute has_element?(view, ".assistant-feedback.is-error")
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
