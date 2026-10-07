defmodule Brando.Content.Proposals.ExternalTest do
  # Proposals from a tool connected over MCP: prepared through the same
  # `Proposals.Tools` as the admin's agent, as BrandoMCP calls them, but with
  # no conversation. They record their origin and are reviewed in the Assistant
  # under "From connected tools".
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Preview
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

  # What `BrandoMCP.Content` builds for a call: the actor and no conversation.
  defp mcp(c, fields \\ []), do: struct(%Context{actor: c.user, origin: :mcp, client: "Claude Code"}, fields)

  defp insert_op(c, heading) do
    %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "module" => "local:#{c.case_module.id}",
      "values" => %{"heading" => heading}
    }
  end

  defp prepare!(c, context, summary \\ "Add the lobby") do
    assert {:ok, result} =
             Tools.call("prepare_proposal", %{"summary" => summary, "operations" => [insert_op(c, summary)]}, context)

    assert {:ok, _} = Jason.encode(result)
    result
  end

  defp blocks(c), do: length(Catalog.load!(Page, c.identity.id, c.user).entry_blocks)

  test "a proposal from MCP records its origin and is listed for review, previewed and applied", c do
    result = prepare!(c, mcp(c))
    assert %{applicable: true, version: 1, review_url: url} = result
    assert url =~ "/admin/assistant/connected/#{result.proposal_id}"
    assert result.note =~ "From connected tools"

    assert {:ok, proposal} = Proposals.get(result.proposal_id, c.user)
    assert %{origin: "mcp", client: "Claude Code", conversation_id: nil, status: "pending"} = proposal

    assert [%Record{id: id, origin: "mcp", client: "Claude Code", summary: "Add the lobby"}] =
             Proposals.list_external(c.user)

    assert id == proposal.id
    assert Proposals.count_external(c.user) == 1

    # Previewed like the Assistant's own, without writing.
    assert {:ok, %{key: key, html: html}} =
             Preview.render(proposal, {Page, c.identity.id}, c.user, preview_target: :blocks)

    assert html =~ "Add the lobby"
    Preview.discard([key])
    assert blocks(c) == 3

    assert {:ok, _} = Proposals.approve(proposal.id, 1, c.user)
    assert {:ok, _receipt} = Proposals.apply(proposal.id, 1, c.user)
    assert blocks(c) == 4

    # Applied: still listed, no longer waiting.
    assert [%Record{status: "applied"}] = Proposals.list_external(c.user)
    assert Proposals.count_external(c.user) == 0
  end

  test "applying records the tool in Activity, with the reviewer as the person", c do
    %{proposal_id: id} = prepare!(c, mcp(c))
    assert {:ok, _} = Proposals.approve(id, 1, c.user)
    assert {:ok, _} = Proposals.apply(id, 1, c.user)

    [event] =
      Repo.all(from(e in Event, where: e.schema == ^to_string(Page) and e.entry_id == ^c.identity.id))

    assert event.source == :mcp
    assert event.user_id == c.user.id
    assert event.details["client"] == "Claude Code"

    # Without a client name, the source is still MCP.
    %{proposal_id: id} = prepare!(c, mcp(c, client: nil), "Another")
    assert {:ok, _} = Proposals.approve(id, 1, c.user)
    assert {:ok, _} = Proposals.apply(id, 1, c.user)

    [_, event] =
      Repo.all(from(e in Event, where: e.schema == ^to_string(Page) and e.entry_id == ^c.identity.id, order_by: e.id))

    assert event.source == :mcp
    refute Map.has_key?(event.details, "client")
  end

  test "rejecting discards it: it leaves the list and nothing is written", c do
    %{proposal_id: id} = prepare!(c, mcp(c))
    assert :ok = Proposals.cancel(id, c.user)
    assert Proposals.list_external(c.user) == []
    assert Proposals.count_external(c.user) == 0
    assert {:ok, %{status: "cancelled"}} = Proposals.get(id, c.user)
    assert {:error, _} = Proposals.approve(id, 1, c.user)
    assert blocks(c) == 3
  end

  test "a refinement over MCP, or leaving a change out in the admin, keeps the origin", c do
    first = prepare!(c, mcp(c))
    second = prepare!(c, mcp(c, proposal_id: first.proposal_id), "The lobby, again")
    assert second.version == 2
    assert [%Record{version: 2, origin: "mcp", client: "Claude Code"}] = Proposals.list_external(c.user)

    two = [insert_op(c, "One"), insert_op(c, "Two")]
    {:ok, result} = Tools.call("prepare_proposal", %{"summary" => "Two", "operations" => two}, mcp(c))
    assert {:ok, narrowed} = Proposals.leave_out(result.proposal_id, 1, [0], c.user)
    assert %{origin: "mcp", client: "Claude Code", conversation_id: nil, version: 2} = narrowed
  end

  test "without a named origin, a call outside a conversation is MCP, and the agent's is the Assistant's", c do
    %{proposal_id: id} = prepare!(c, %Context{actor: c.user})
    assert {:ok, %{origin: "mcp", client: nil}} = Proposals.get(id, c.user)

    conversation = %Context{actor: c.user, conversation_id: Ecto.UUID.generate()}
    result = prepare!(c, conversation)
    refute Map.has_key?(result, :review_url)
    assert {:ok, %{origin: "assistant"}} = Proposals.get(result.proposal_id, c.user)
    # A conversation's proposals are not listed with the connected tools'.
    assert [%Record{id: ^id}] = Proposals.list_external(c.user)
  end

  test "the client's name is one short line, and the origin must be known", c do
    %{proposal_id: id} = prepare!(c, mcp(c, client: "  Claude\n  Code  " <> String.duplicate("x", 200)))
    assert {:ok, %{client: client}} = Proposals.get(id, c.user)
    assert String.starts_with?(client, "Claude Code x")
    assert String.length(client) == 80

    assert {:error, message} =
             Tools.call(
               "prepare_proposal",
               %{"summary" => "x", "operations" => [insert_op(c, "x")]},
               mcp(c, origin: :telnet)
             )

    assert message =~ "origin"
  end

  test "another user can neither see nor apply it", c do
    %{proposal_id: id} = prepare!(c, mcp(c))
    other = Factory.insert(:random_user)

    assert Proposals.list_external(other) == []
    assert Proposals.count_external(other) == 0
    assert {:error, message} = Proposals.get(id, other)
    assert message =~ "another user"
    assert {:error, _} = Proposals.approve(id, 1, other)
    assert {:error, _} = Proposals.cancel(id, other)
    assert {:ok, %{status: "pending"}} = Proposals.get(id, c.user)
    assert blocks(c) == 3
  end

  test "a proposal made in another site or environment is not listed or opened here", c do
    %{proposal_id: id} = prepare!(c, mcp(c))
    Repo.update_all(from(r in Record, where: r.id == ^id), set: [scope: "acme:staging"])

    assert Proposals.list_external(c.user) == []
    assert Proposals.count_external(c.user) == 0
    assert {:error, _} = Proposals.get(id, c.user)
    assert {:error, _} = Proposals.approve(id, 1, c.user)
  end
end
