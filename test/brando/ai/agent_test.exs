defmodule Brando.AI.AgentTest do
  use Brando.ConnCase, async: false
  alias Brando.AI.Agent
  alias Brando.AI.Agent.{Message, Run}
  alias Brando.AIStub
  alias Brando.Content.Proposals
  alias Brando.Content.Transfer.Catalog
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Page

  setup do
    AIStub.configure()
    c = Brando.ProposalFixtures.context()
    Brando.Content.create_identifier(Page, c.identity)
    {:ok, conversation} = Agent.start_conversation(c.user)
    put_config([])
    Map.put(c, :conversation, conversation)
  end

  defp put_config(opts) do
    previous = Application.get_env(:brando, Agent)
    Application.put_env(:brando, Agent, opts)

    on_exit(fn ->
      if previous, do: Application.put_env(:brando, Agent, previous), else: Application.delete_env(:brando, Agent)
    end)
  end

  defp roles(c), do: Enum.map(Agent.messages(c.conversation.id, c.user), & &1.role)
  defp blocks(c), do: length(Catalog.load!(Page, c.identity.id, c.user).entry_blocks)

  defp insert_op(c, media \\ %{"cover" => "image1"}) do
    %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "module" => "local:#{c.case_module.id}",
      "values" => %{"heading" => "Lobby"},
      "media" => media
    }
  end

  test "a run reads content, prepares a proposal with an attachment and answers", c do
    assert {:ok, "image1"} = Agent.attach(c.conversation.id, {:image, c.image.id}, c.user)
    Agent.subscribe(c.conversation.id)

    AIStub.script([
      {:tools, [{"search_entries", %{"query" => "Ident", "content_type" => "Brando.Pages.Page"}}]},
      {:tools, [{"prepare_proposal", %{"summary" => "Lobby on Identity", "operations" => [insert_op(c)]}}]},
      {:text, "I prepared a proposal that adds the lobby photo to Identity. It goes live when you apply it."}
    ])

    assert {:ok, %Run{status: "completed", steps: 3} = run} =
             Agent.send_message(c.conversation.id, "Put the lobby photo on Identity", c.user, sync: true)

    assert run.input_tokens == 201
    assert run.output_tokens == 41

    assert roles(c) == ~w(user assistant tool assistant tool assistant)

    # The model saw the tools, then the results of its calls.
    assert_received {:ai_request, first}
    assert Enum.any?(first["tools"], &(&1["name"] == "prepare_proposal"))
    assert_received {:ai_request, second}
    assert Enum.any?(second["input"], &(&1["type"] == "function_call_output" and &1["output"] =~ "Identity"))

    {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
    assert {:ok, proposal} = Proposals.get(conversation.proposal_id, c.user)
    assert proposal.status == "pending"
    assert proposal.summary == "Lobby on Identity"
    assert [%{media: %{"cover" => {:image, id}}}] = proposal.operations
    assert id == c.image.id
    assert_received {:agent, _, {:proposal, _}}
    assert_received {:agent, _, {:progress, "Checking the proposal"}}

    # Preparing wrote nothing; the user applies in the admin.
    assert blocks(c) == 3

    # A follow-up refines the proposal under review.
    AIStub.script([
      {:tools, [{"prepare_proposal", %{"summary" => "Lobby, refined", "operations" => [insert_op(c)]}}]},
      {:text, "Updated."}
    ])

    assert {:ok, %{status: "completed"}} = Agent.send_message(c.conversation.id, "Refine it", c.user, sync: true)
    {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
    assert {:ok, %{version: 2}} = Proposals.get(conversation.proposal_id, c.user)
  end

  test "attachment aliases follow attach order and survive detaching others", c do
    video = Factory.insert(:video)
    other = Factory.insert(:image, creator_id: c.user.id, path: "images/other.jpg")

    assert {:ok, "image1"} = Agent.attach(c.conversation.id, {:image, c.image.id}, c.user)
    assert {:ok, "video1"} = Agent.attach(c.conversation.id, {:video, video.id}, c.user)
    assert {:ok, "image2"} = Agent.attach(c.conversation.id, {:image, other.id}, c.user)
    assert {:ok, "image1"} = Agent.attach(c.conversation.id, {:image, c.image.id}, c.user)

    assert :ok = Agent.detach(c.conversation.id, "image1", c.user)
    assert {:ok, "image3"} = Agent.attach(c.conversation.id, {:image, c.image.id}, c.user)

    {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
    assert Enum.map(conversation.attachments, & &1["alias"]) == ~w(video1 image2 image3)

    assert {:error, _} = Agent.attach(c.conversation.id, {:image, -1}, c.user)
    assert {:error, _} = Agent.attach(c.conversation.id, {:image, c.image.id}, Factory.insert(:random_user))
  end

  test "conversations belong to their user", c do
    other = Factory.insert(:random_user)
    assert {:error, _} = Agent.get_conversation(c.conversation.id, other)
    assert {:error, _} = Agent.send_message(c.conversation.id, "Hi", other, sync: true)
    assert Agent.list_conversations(other) == []
    assert [%{id: id}] = Agent.list_conversations(c.user)
    assert id == c.conversation.id
  end

  test "a run stops when its token budget is spent, before calling the model", c do
    put_config(run_token_budget: 100)
    AIStub.script([{:text, "never"}])

    assert {:ok, %Run{status: "budget_exhausted", steps: 0}} =
             Agent.send_message(c.conversation.id, "Hello", c.user, sync: true)

    refute_received {:ai_request, _}
    assert roles(c) == ~w(user assistant)
  end

  test "the monthly budget counts other runs in the site/environment", c do
    put_config(monthly_token_budget: 10_000)
    {:ok, other} = Agent.start_conversation(c.user)

    Repo.insert!(%Run{
      conversation_id: other.id,
      scope: Brando.Content.Transfer.scope(),
      status: "completed",
      input_tokens: 9_000,
      output_tokens: 900
    })

    AIStub.script([{:text, "never"}])
    assert {:ok, %{status: "budget_exhausted"}} = Agent.send_message(c.conversation.id, "Hello", c.user, sync: true)
    refute_received {:ai_request, _}
  end

  test "cancelling stops the run before its next call", c do
    conversation_id = c.conversation.id
    user = c.user

    AIStub.script([
      {:tools, [{"list_content_types", %{}}]},
      {:text, "never reached"}
    ])

    # Cancel while the first model call is in flight.
    Req.Test.stub(Brando.AI, fn conn ->
      :ok = Agent.cancel(conversation_id, user)

      Req.Test.json(conn, %{
        "id" => "resp_0",
        "object" => "response",
        "status" => "completed",
        "model" => "gpt-4o-mini",
        "output" => [
          %{
            "type" => "function_call",
            "id" => "fc_0",
            "call_id" => "call_0",
            "name" => "list_content_types",
            "arguments" => "{}",
            "status" => "completed"
          }
        ],
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5, "total_tokens" => 15}
      })
    end)

    assert {:ok, %Run{status: "cancelled", input_tokens: 10}} =
             Agent.send_message(conversation_id, "Hello", user, sync: true)

    assert [_, _, %Message{role: "tool", content: ~s({"error":"cancelled"})}] = Agent.messages(conversation_id, user)
  end

  test "provider errors fail the run with a message", c do
    AIStub.script([{:error, 500}])
    assert {:ok, %Run{status: "failed"}} = Agent.send_message(c.conversation.id, "Hello", c.user, sync: true)

    assert [_, %Message{role: "assistant", content: "Something went wrong" <> _}] =
             Agent.messages(c.conversation.id, c.user)
  end

  test "configured prices estimate a run's cost", c do
    put_config(prices: [input: 2.0, output: 10.0])
    AIStub.script([{:text, "Hi"}])
    assert {:ok, %Run{cost: cost}} = Agent.send_message(c.conversation.id, "Hello", c.user, sync: true)
    assert_in_delta cost, (1 * 2.0 + 1 * 10.0) / 1_000_000, 1.0e-12
  end

  test "the step limit ends a run that keeps calling tools", c do
    put_config(max_steps: 2)
    AIStub.script(List.duplicate({:tools, [{"list_content_types", %{}}]}, 5))

    assert {:ok, %Run{status: "completed", steps: 2, error: "step limit"}} =
             Agent.send_message(c.conversation.id, "Loop", c.user, sync: true)
  end

  test "one run at a time, unless the previous one died", c do
    run =
      Repo.insert!(%Run{conversation_id: c.conversation.id, scope: Brando.Content.Transfer.scope(), status: "running"})

    assert {:error, message} = Agent.send_message(c.conversation.id, "Hello", c.user, sync: true)
    assert message =~ "still working"

    run |> Ecto.Changeset.change(updated_at: DateTime.add(DateTime.utc_now(), -3600)) |> Repo.update!()
    AIStub.script([{:text, "Hi"}])
    assert {:ok, %{status: "completed"}} = Agent.send_message(c.conversation.id, "Hello", c.user, sync: true)
    assert Repo.get!(Run, run.id).status == "interrupted"
  end

  test "an unconfigured site says so" do
    Application.put_env(:brando, Brando.AI, enabled: false)
    user = Factory.insert(:random_user)
    {:ok, conversation} = Agent.start_conversation(user)
    refute Agent.available?()
    assert {:error, message} = Agent.send_message(conversation.id, "Hello", user)
    assert message =~ "no AI model"
  end

  test "the Anthropic tool exchange round-trips through ReqLLM", c do
    Application.put_env(:brando, Brando.AI,
      enabled: true,
      default_model: "anthropic:claude-opus-5-5",
      providers: [anthropic: [api_key: "test-key"]],
      default_opts: [req_http_options: [plug: {Req.Test, Brando.AI}, retry: false]]
    )

    test = self()
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

    Req.Test.stub(Brando.AI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:anthropic, Jason.decode!(body)})

      content =
        case Elixir.Agent.get_and_update(counter, &{&1, &1 + 1}) do
          0 -> [%{"type" => "tool_use", "id" => "toolu_1", "name" => "list_content_types", "input" => %{}}]
          _ -> [%{"type" => "text", "text" => "Pages have blocks."}]
        end

      Req.Test.json(conn, %{
        "id" => "msg_1",
        "type" => "message",
        "role" => "assistant",
        "model" => "claude-opus-5-5",
        "content" => content,
        "stop_reason" => if(match?([%{"type" => "tool_use"}], content), do: "tool_use", else: "end_turn"),
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      })
    end)

    assert {:ok, %Run{status: "completed", steps: 2, model: "anthropic:claude-opus-5-5"}} =
             Agent.send_message(c.conversation.id, "What can I edit?", c.user, sync: true)

    assert_received {:anthropic, first}
    assert first["system"] |> inspect() =~ "content assistant"
    assert Enum.any?(first["tools"], &(&1["name"] == "entry_outline"))

    assert_received {:anthropic, second}

    assert Enum.any?(second["messages"], fn message ->
             is_list(message["content"]) and
               Enum.any?(message["content"], &(&1["type"] == "tool_result" and &1["tool_use_id"] == "toolu_1"))
           end)

    assert List.last(Agent.messages(c.conversation.id, c.user)).content == "Pages have blocks."
  end

  test "runs execute in the background and report over PubSub", c do
    AIStub.configure(shared: true)
    AIStub.script([{:text, "Hello there"}])
    Agent.subscribe(c.conversation.id)

    assert {:ok, %Run{status: "running", id: id}} = Agent.send_message(c.conversation.id, "Hi", c.user)
    assert_receive {:agent, _, {:run, %Run{id: ^id, status: "completed"}}}, 5_000
    assert List.last(Agent.messages(c.conversation.id, c.user)).content == "Hello there"
  end
end
