defmodule Brando.Content.Proposals.ConnectionTest do
  # A connected tool's own proposals: `list_proposals` and `cancel_proposal`,
  # as `Brando.MCP.Tools` calls them, and whose proposals they are
  # (`Proposals.connection_proposal/4`): the same person, a client with the
  # same name, over MCP, in this site and environment.
  # Grouped, one at a time: ProposalFixtures.context/0 inserts the pages "identity" and
  # "naming", whose URIs concurrent transactions would wait on
  use Brando.ConnCase, async: true, group: :shared_locks

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Content.Transfer.Catalog
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    c = Brando.ProposalFixtures.context()
    Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))
    c
  end

  # What `Brando.MCP.Tools` builds for a call: the actor, no conversation.
  defp mcp(c, fields \\ []), do: struct(%Context{actor: c.user, origin: :mcp, client: "Claude Code"}, fields)

  defp insert_op(c, page, heading) do
    %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => page.id},
      "module" => "local:#{c.case_module.id}",
      "values" => %{"heading" => heading}
    }
  end

  defp create_op(ref, uri) do
    %{
      "op" => "create_entry",
      "content_type" => "Brando.Pages.Page",
      "ref" => ref,
      "fields" => %{"title" => "Lobby", "uri" => uri, "language" => "en", "template" => "default.html"}
    }
  end

  defp prepare!(context, operations, summary \\ "Add the lobby") do
    assert {:ok, %{proposal_id: id}} =
             Tools.call("prepare_proposal", %{"summary" => summary, "operations" => operations}, context)

    id
  end

  defp list!(context, args \\ %{}) do
    assert {:ok, %{proposals: proposals} = result} = Tools.call("list_proposals", args, context)
    assert {:ok, _} = Jason.encode(result)
    proposals
  end

  defp ids(proposals), do: Enum.map(proposals, & &1.proposal_id)
  defp status(id), do: Repo.one!(from(r in Record, where: r.id == ^id, select: r.status))
  defp set!(id, fields), do: Repo.update_all(from(r in Record, where: r.id == ^id), set: fields)
  defp blocks(c), do: length(Catalog.load!(Page, c.identity.id, c.user).entry_blocks)

  describe "list_proposals" do
    test "lists the tool's proposal with its status, version, summary, times and entries", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])

      assert [proposal] = list!(mcp(c))

      assert %{proposal_id: ^id, version: 1, summary: "Add the lobby", status: "pending"} = proposal
      assert %DateTime{} = proposal.changed_at
      assert DateTime.compare(proposal.expires_at, DateTime.utc_now()) == :gt
      assert proposal.entries == [%{content_type: "Brando.Pages.Page", id: c.identity.id}]
      refute Map.has_key?(proposal, :expired)
      refute Map.has_key?(proposal, :changed_by)
    end

    test "after the person applies it in the admin, it is applied, with the ids of the entries it created", c do
      id = prepare!(mcp(c), [create_op("lobby", "lobby"), insert_op(c, c.identity, "Lobby")])
      assert {:ok, _} = Proposals.approve(id, 1, c.user)
      assert [%{status: "approved", changed_by: "person"} = approved] = list!(mcp(c))
      assert Enum.find(approved.entries, &Map.has_key?(&1, :ref)) == %{content_type: "Brando.Pages.Page", ref: "lobby"}

      assert {:ok, receipt} = Proposals.apply(id, 1, c.user)
      created_id = receipt.mappings["created"]["lobby"]
      assert is_integer(created_id)

      assert [%{status: "applied", changed_by: "person", entries: entries}] = list!(mcp(c))

      assert entries == [
               %{content_type: "Brando.Pages.Page", ref: "lobby", id: created_id},
               %{content_type: "Brando.Pages.Page", id: c.identity.id}
             ]
    end

    test "lists every status, superseded and cancelled too, newest first", c do
      first = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      # The same page: this one supersedes the first.
      second = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby, again")], "The lobby, again")
      third = prepare!(mcp(c), [insert_op(c, c.naming, "Name")], "Name it")
      assert :ok = Proposals.cancel(third, c.user)

      assert [
               %{proposal_id: ^third, status: "cancelled"},
               %{proposal_id: ^second, status: "pending", version: 2},
               %{proposal_id: ^first, status: "superseded", version: 1, superseded_by: ^second}
             ] = list!(mcp(c))
    end

    test "an approval withdrawn as the apply finds new problems changes changed_at", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, ~s(Lobby<img src=x onerror="x">))])
      assert [%{problems: [_ | _]}] = Repo.all(from(r in Record, where: r.id == ^id))

      # As a version stored before the check was added, approved an hour ago.
      approved_at = DateTime.add(DateTime.utc_now(), -3_600, :second)
      set!(id, problems: [], status: "approved", approved_at: approved_at, updated_at: approved_at)
      assert [%{status: "approved", changed_at: ^approved_at}] = list!(mcp(c))

      assert {:error, _} = Proposals.apply(id, 1, c.user)

      assert [%{status: "pending", changed_at: changed_at}] = list!(mcp(c))
      assert DateTime.compare(changed_at, DateTime.add(DateTime.utc_now(), -60, :second)) == :gt
    end

    test "a proposal replacing an image's file names the image and its replacement next to entries", c do
      old = Brando.ImageFileFixtures.file_image("old", {800, 600})
      new = Brando.ImageFileFixtures.file_image("new", {1600, 1200})

      op = %{
        "op" => "replace_image_file",
        "asset" => %{"kind" => "image", "id" => old.id},
        "with" => %{"kind" => "image", "id" => new.id}
      }

      id = prepare!(mcp(c), [op], "Better photo")

      assert [%{proposal_id: ^id, entries: [], replaced_images: replaced}] = list!(mcp(c))
      assert replaced == [%{kind: "image", id: old.id, with: %{kind: "image", id: new.id}}]

      # Said only of a proposal that replaces an image's file
      prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      assert [plain, _] = list!(mcp(c))
      refute Map.has_key?(plain, :replaced_images)

      [definition] = Enum.filter(Tools.definitions(:mcp), &(&1.name == "list_proposals"))
      assert definition.description =~ "replaced_images"
    end

    test "says when a pending or approved proposal has expired", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      set!(id, expires_at: DateTime.add(DateTime.utc_now(), -60, :second))

      assert [%{status: "pending", expired: true}] = list!(mcp(c))

      set!(id, status: "cancelled")
      assert [%{status: "cancelled"} = proposal] = list!(mcp(c))
      refute Map.has_key?(proposal, :expired)
    end

    test "filters by status and by proposal_id", c do
      first = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      second = prepare!(mcp(c), [insert_op(c, c.naming, "Name")], "Name it")
      assert :ok = Proposals.cancel(second, c.user)

      assert [^first] = c |> mcp() |> list!(%{"status" => "pending"}) |> ids()
      assert [^second] = c |> mcp() |> list!(%{"status" => "cancelled"}) |> ids()
      assert [] = list!(mcp(c), %{"status" => "applied"})
      assert [^second] = c |> mcp() |> list!(%{"proposal_id" => second}) |> ids()
      assert [] = list!(mcp(c), %{"proposal_id" => second, "status" => "pending"})
      assert [] = list!(mcp(c), %{"proposal_id" => "not-a-uuid"})

      assert {:error, message} = Tools.call("list_proposals", %{"status" => "rejected"}, mcp(c))
      assert message =~ "pending" and message =~ "rejected"
    end

    test "gives 20 by default, at most 50", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      record = Repo.get!(Record, id)

      for _ <- 1..55 do
        record |> Ecto.put_meta(state: :built) |> Map.put(:id, Ecto.UUID.generate()) |> Repo.insert!()
      end

      assert length(list!(mcp(c))) == 20
      assert length(list!(mcp(c), %{"limit" => 5})) == 5
      assert length(list!(mcp(c), %{"limit" => 500})) == 50
      assert length(list!(mcp(c), %{"limit" => 0})) == 1
    end

    test "leaves out another person's, another client's, the Assistant's and another site's proposals", c do
      own = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])

      other = Factory.insert(:random_user)
      prepare!(mcp(c, actor: other), [insert_op(c, c.naming, "Theirs")], "Theirs")
      prepare!(mcp(c, client: "Cursor"), [insert_op(c, c.naming, "Cursor's")], "Cursor's")
      prepare!(mcp(c, client: nil), [insert_op(c, c.naming, "Nameless")], "Nameless")

      conversation = %Context{actor: c.user, origin: :assistant, conversation_id: Ecto.UUID.generate()}
      prepare!(conversation, [insert_op(c, c.naming, "Assistant's")], "Assistant's")

      elsewhere = prepare!(mcp(c), [insert_op(c, c.naming, "Elsewhere")], "Elsewhere")
      set!(elsewhere, scope: "acme:staging")

      assert [^own] = c |> mcp() |> list!() |> ids()
      # A second connection of the same client, or the tool reconnected, sees the same.
      assert [^own] = c |> mcp(client: "  Claude   Code ") |> list!() |> ids()
      assert [_] = list!(mcp(c, client: "Cursor"))
      assert [%{summary: "Nameless"}] = list!(mcp(c, client: nil))
      assert [%{summary: "Theirs"}] = list!(mcp(c, actor: other))
    end
  end

  describe "cancel_proposal" do
    test "cancels the tool's pending proposal; content is untouched and it is listed as cancelled", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])

      assert {:ok, %{proposal_id: ^id, version: 1, status: "cancelled", note: note}} =
               Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))

      assert note =~ "untouched"
      assert status(id) == "cancelled"
      assert blocks(c) == 3
      assert [%{status: "cancelled"}] = list!(mcp(c))
      assert {:error, _} = Proposals.approve(id, 1, c.user)
    end

    test "cancels an approved proposal, and an expired one", c do
      approved = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      assert {:ok, _} = Proposals.approve(approved, 1, c.user)
      assert {:ok, %{status: "cancelled"}} = Tools.call("cancel_proposal", %{"proposal_id" => approved}, mcp(c))
      assert status(approved) == "cancelled"

      expired = prepare!(mcp(c), [insert_op(c, c.naming, "Name")], "Name it")
      set!(expired, expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      assert {:ok, %{status: "cancelled"}} = Tools.call("cancel_proposal", %{"proposal_id" => expired}, mcp(c))
      assert status(expired) == "cancelled"
    end

    test "the person's apply of an approved proposal the tool cancelled says it is no longer under review", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      assert {:error, message} = Proposals.apply(id, 1, c.user)
      assert message =~ "Approve"

      assert {:ok, _} = Proposals.approve(id, 1, c.user)
      assert {:ok, _} = Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))

      assert {:error, message} = Proposals.apply(id, 1, c.user)
      refute message =~ "Approve"
      assert message =~ "cancelled" and message =~ "no longer under review"
      assert blocks(c) == 3

      set!(id, status: "undone")
      assert {:error, message} = Proposals.apply(id, 1, c.user)
      assert message =~ "undone" and message =~ "no longer under review"

      # Applying an applied proposal gives its receipt again; approving it says so.
      set!(id, status: "applied")
      assert {:error, message} = Proposals.approve(id, 1, c.user)
      assert message =~ "applied" and message =~ "no longer under review"
    end

    test "refuses a proposal that is not under review, naming its status", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      assert {:ok, _} = Proposals.approve(id, 1, c.user)
      assert {:ok, _} = Proposals.apply(id, 1, c.user)

      assert {:error, message} = Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))
      assert message =~ "is applied"
      assert status(id) == "applied"
      assert blocks(c) == 4

      for status <- ~w(undone superseded cancelled) do
        set!(id, status: status)
        assert {:error, message} = Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))
        assert message =~ "is #{status}"
        assert status(id) == status
      end
    end

    test "another connection's proposal is not found, and stays as it was", c do
      other = Factory.insert(:random_user)
      theirs = prepare!(mcp(c, actor: other), [insert_op(c, c.naming, "Theirs")], "Theirs")
      cursors = prepare!(mcp(c, client: "Cursor"), [insert_op(c, c.naming, "Cursor's")], "Cursor's")
      nameless = prepare!(mcp(c, client: nil), [insert_op(c, c.identity, "Nameless")], "Nameless")

      conversation = %Context{actor: c.user, origin: :assistant, conversation_id: Ecto.UUID.generate()}
      assistants = prepare!(conversation, [insert_op(c, c.identity, "Assistant's")], "Assistant's")

      elsewhere = prepare!(mcp(c), [insert_op(c, c.identity, "Elsewhere")], "Elsewhere")
      set!(elsewhere, scope: "acme:staging")

      for id <- [theirs, cursors, nameless, assistants, elsewhere] do
        assert {:error, message} = Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))
        assert message =~ "no proposal"
        assert status(id) == "pending"
      end

      for id <- ["not-a-uuid", Ecto.UUID.generate(), 12, nil] do
        assert {:error, message} = Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))
        assert message =~ "no proposal"
      end

      # Each is cancelled by its own connection.
      assert {:ok, _} = Tools.call("cancel_proposal", %{"proposal_id" => nameless}, mcp(c, client: nil))
      assert {:ok, _} = Tools.call("cancel_proposal", %{"proposal_id" => cursors}, mcp(c, client: "Cursor"))
    end
  end

  test "both are offered only to a tool connected over MCP, not to the Assistant", c do
    names = Enum.map(Tools.definitions(:assistant), & &1.name)
    refute "list_proposals" in names
    refute "cancel_proposal" in names
    assert "prepare_proposal" in names

    mcp_names = Enum.map(Tools.definitions(:mcp), & &1.name)
    assert "list_proposals" in mcp_names and "cancel_proposal" in mcp_names
    refute "list_proposals" in Enum.map(Brando.AI.Agent.Loop.tools(), & &1.name)

    id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
    assistant = %Context{actor: c.user, origin: :assistant, conversation_id: Ecto.UUID.generate()}

    assert {:error, "Unknown tool" <> _} = Tools.call("list_proposals", %{}, assistant)
    assert {:error, "Unknown tool" <> _} = Tools.call("cancel_proposal", %{"proposal_id" => id}, assistant)
    assert status(id) == "pending"
  end
end
