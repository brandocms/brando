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

  test "uploads keep the aliases reserved in selection order", c do
    uploads = [
      %{ref: "a", asset_type: "image", filename: "large.jpg"},
      %{ref: "b", asset_type: "video", filename: "clip.mp4"},
      %{ref: "c", asset_type: "image", filename: "small.jpg"}
    ]

    assert {:ok, ~w(image1 video1 image2)} = Agent.reserve(c.conversation.id, uploads, c.user)

    small = Factory.insert(:image, creator_id: c.user.id, title: nil, path: "images/x/small.jpg")
    assert {:ok, "image2"} = Agent.fulfil(c.conversation.id, "c", small, c.user)
    assert {:error, _} = Agent.fulfil(c.conversation.id, "missing", small, c.user)

    {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)

    assert [
             %{"alias" => "image1", "id" => nil},
             %{"alias" => "video1", "id" => nil},
             %{"alias" => "image2", "id" => id, "label" => "small.jpg"}
           ] = conversation.attachments

    assert id == small.id
  end

  test "attach_many attaches in order, keeps existing aliases and reports what it cannot attach", c do
    first = Factory.insert(:image, creator_id: c.user.id, path: "images/a/first.jpg")
    second = Factory.insert(:image, creator_id: c.user.id, path: "images/a/second.jpg")
    deleted = Factory.insert(:image, creator_id: c.user.id, deleted_at: DateTime.utc_now())
    assert {:ok, "image1"} = Agent.attach(c.conversation.id, {:image, second.id}, c.user)
    Agent.subscribe(c.conversation.id)

    assert {:ok, %{attached: attached, unavailable: unavailable}} =
             Agent.attach_many(
               c.conversation.id,
               [{:image, first.id}, {:image, deleted.id}, {:image, second.id}, {:image, -1}],
               c.user
             )

    assert Enum.map(unavailable, & &1.id) == [deleted.id, -1]
    assert Enum.all?(unavailable, &is_binary(&1.reason))
    assert [%{alias: "image2", new: true}, %{alias: "image1", new: false}] = attached
    assert_received {:agent, _, {:attachments, ~w(image2 image1)}}

    {:ok, conversation} = Agent.get_conversation(c.conversation.id, c.user)
    assert Enum.map(conversation.attachments, &{&1["alias"], &1["id"]}) == [{"image1", second.id}, {"image2", first.id}]

    # Nothing new, nothing written, nothing broadcast.
    assert {:ok, %{attached: [%{alias: "image2", new: false}]}} =
             Agent.attach_many(c.conversation.id, [{:image, first.id}], c.user)

    assert {:error, _} = Agent.attach_many(c.conversation.id, [{:image, first.id}], Factory.insert(:random_user))
  end

  describe "a conversation opened for an entry" do
    test "records the entry, its block field and its language", c do
      assert {:ok, conversation} =
               Agent.start_conversation(c.user,
                 target: %{"content_type" => "Brando.Pages.Page", "id" => to_string(c.identity.id), "field" => "blocks"}
               )

      id = c.identity.id

      assert %{"content_type" => "Brando.Pages.Page", "id" => ^id, "field" => "blocks", "title" => "Identity"} =
               conversation.target

      assert conversation.language == to_string(c.identity.language)

      # The first block field is the default.
      assert {:ok, %{"field" => "blocks"}} = Agent.target(%{content_type: "Brando.Pages.Page", id: id}, c.user)
    end

    test "rejects entries that are not saved, not changeable or not there", c do
      assert {:error, message} = Agent.target(%{"content_type" => "Brando.Pages.Page", "id" => ""}, c.user)
      assert message =~ "Save the entry"

      assert {:error, _} = Agent.target(%{"content_type" => "Brando.Pages.Page", "id" => "-1"}, c.user)
      assert {:error, _} = Agent.target(%{"content_type" => "Brando.Users.User", "id" => c.user.id}, c.user)
      assert {:error, _} = Agent.target(%{"content_type" => "Nope", "id" => 1}, c.user)

      assert {:error, message} =
               Agent.target(%{"content_type" => "Brando.Pages.Page", "id" => c.identity.id, "field" => "nope"}, c.user)

      assert message =~ "no block field nope"

      assert {:error, _} =
               Agent.start_conversation(c.user, target: %{"content_type" => "Brando.Pages.Page", "id" => "-1"})

      assert [_] = Agent.list_conversations(c.user)
    end

    test "needs permission to change the entry with groups authorization", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      alias Brando.Authorization.{Catalog, Groups, Scope}
      editor = Factory.insert(:random_user, role: :user)
      scope = Scope.standalone(c.user)
      target = %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id}

      {:ok, group} =
        Groups.create(scope, %{name: "Readers"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:use, :assistant).key,
          Catalog.get(:read, Page).key
        ])

      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      assert {:error, message} = Agent.start_conversation(editor, target: target)
      assert message =~ "permission"

      {:ok, editors} = Groups.create(scope, %{name: "Page editors"}, [Catalog.get(:update, Page).key])
      {:ok, :ok} = Groups.add_member(scope, editors.id, editor.id)
      assert {:ok, %{target: %{"title" => "Identity"}}} = Agent.start_conversation(editor, target: target)
    end
  end

  test "the assistant needs its permission when groups authorization is on", c do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    alias Brando.Authorization.{Catalog, Groups, Scope}
    editor = Factory.insert(:random_user, role: :user)
    scope = Scope.standalone(c.user)
    {:ok, group} = Groups.create(scope, %{name: "Editors"}, [Catalog.get(:access, :backend).key])
    {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)

    refute Agent.allowed?(editor)
    assert {:error, message} = Agent.start_conversation(editor)
    assert message =~ "permission"

    {:ok, assistants} = Groups.create(scope, %{name: "Assistant users"}, [Catalog.get(:use, :assistant).key])
    {:ok, :ok} = Groups.add_member(scope, assistants.id, editor.id)
    assert Agent.allowed?(editor)
    assert {:ok, _} = Agent.start_conversation(editor)
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

  test "reads from before the editor's latest message are marked stale", c do
    message = fn attrs -> Repo.insert!(struct(Message, Map.put(attrs, :conversation_id, c.conversation.id))) end
    call = %{"id" => "call_1", "name" => "entry_outline", "arguments" => "{}"}
    proposal = %{"id" => "call_2", "name" => "prepare_proposal", "arguments" => "{}"}

    message.(%{role: "user", content: "Rearrange the page"})
    message.(%{role: "assistant", content: "", tool_calls: [call]})
    message.(%{role: "tool", tool_call_id: "call_1", tool_name: "entry_outline", content: ~s({"blocks":"old"})})
    message.(%{role: "assistant", content: "", tool_calls: [proposal]})
    message.(%{role: "tool", tool_call_id: "call_2", tool_name: "prepare_proposal", content: ~s({"version":1})})
    message.(%{role: "user", content: "Switch off Deli's cover"})

    results = fn ->
      c.conversation
      |> Brando.AI.Agent.Loop.context()
      |> Map.fetch!(:messages)
      |> Enum.filter(&(&1.role == :tool))
      |> Enum.map(fn m -> m.content |> Enum.map_join(& &1.text) end)
    end

    assert [outline, proposal_result] = results.()
    assert outline =~ "stale"
    refute outline =~ "old"
    assert proposal_result =~ "version"

    # A read after the latest message is current.
    message.(%{role: "assistant", content: "", tool_calls: [%{call | "id" => "call_3"}]})
    message.(%{role: "tool", tool_call_id: "call_3", tool_name: "entry_outline", content: ~s({"blocks":"new"})})
    assert [_, _, current] = results.()
    assert current =~ "new"
  end

  test "pictures go with the latest look only, and count as a model charges for them", c do
    path = "images/looks/#{System.unique_integer([:positive])}.png"
    File.mkdir_p!(Path.dirname(Brando.Images.Utils.media_path(path)))
    Image.write!(Image.new!(600, 600, color: :blue), Brando.Images.Utils.media_path(path))
    image = Brando.Factory.insert(:image, creator_id: c.user.id, path: path, sizes: %{})
    on_exit(fn -> File.rm(Brando.Images.Utils.media_path(path)) end)

    message = fn attrs -> Repo.insert!(struct(Message, Map.put(attrs, :conversation_id, c.conversation.id))) end
    look = ~s({"look":[["image",#{image.id}]],"note":"The pictures follow, numbered in this order."})

    message.(%{role: "user", content: "Choose a cover"})

    for id <- ["call_1", "call_2"] do
      message.(%{
        role: "assistant",
        content: "",
        tool_calls: [%{"id" => id, "name" => "look_at_media", "arguments" => "{}"}]
      })

      message.(%{role: "tool", tool_call_id: id, tool_name: "look_at_media", content: look})
    end

    context = Brando.AI.Agent.Loop.context(c.conversation)
    assert [earlier, latest] = Enum.filter(context.messages, &(&1.role == :tool))
    refute Enum.any?(earlier.content, &(&1.type == :image))
    assert Enum.map_join(earlier.content, & &1.text) =~ "were shown"
    assert [%{type: :image, media_type: "image/jpeg"}] = Enum.filter(latest.content, &(&1.type == :image))

    # The picture counts as its tokens, not its bytes.
    estimate = Brando.AI.Agent.Budget.estimate(context)
    without = Brando.AI.Agent.Budget.estimate(%{context | messages: Enum.drop(context.messages, -1)})
    assert estimate - without < 200
  end

  test "a run reports progress in the editor's language", c do
    user = c.user |> Ecto.Changeset.change(language: :no) |> Repo.update!()
    Agent.subscribe(c.conversation.id)
    AIStub.script([{:text, "Hei."}])

    # The caller's locale does not matter: the run process sets its own.
    Gettext.put_locale(Brando.Gettext, "en")
    assert {:ok, %Run{status: "completed"}} = Agent.send_message(c.conversation.id, "Hei", user, sync: true)
    assert_received {:agent, _, {:progress, "Tenker"}}
  end
end
