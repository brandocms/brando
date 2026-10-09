defmodule Brando.AI.CassetteTest do
  # The cassette is scoped to the test process, so these run concurrently
  # with each other and with the rest of the suite.
  use ExUnit.Case, async: true
  use Brando.Test

  alias Brando.AI.Cassette
  alias Brando.AI.Cassette.MismatchError
  alias Brando.AIStub.ScriptedClient
  alias ReqLLM.StreamResponse

  @moduletag :tmp_dir
  # Mismatches are logged as they happen; these tests make them on purpose.
  @moduletag :capture_log

  @model "openai:gpt-4o-mini"

  defp write_cassette(dir, name, interactions) do
    path = Path.join(dir, name <> ".json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"cassette" => name, "version" => 1, "interactions" => interactions}))
    path
  end

  defp interaction(content, reply) do
    %{
      "request" => %{
        "kind" => "generate",
        "model" => @model,
        "system" => nil,
        "messages" => [%{"role" => "user", "content" => content}],
        "tools" => [],
        "params" => %{}
      },
      "response" => reply
    }
  end

  defp text({:ok, response}), do: ReqLLM.Response.text(response)

  describe "replay" do
    test "answers a matching request from the file", %{tmp_dir: dir} do
      write_cassette(dir, "greeting", [
        interaction("Say hello", %{"text" => "Hello", "usage" => %{"input_tokens" => 2, "output_tokens" => 1}}),
        interaction("Say goodbye", %{"text" => "Goodbye"})
      ])

      use_cassette "greeting", dir: dir do
        # Out of order is fine: each request finds its own recording.
        assert {:ok, response} = Cassette.generate_text(@model, "Say goodbye")
        assert ReqLLM.Response.text(response) == "Goodbye"
        assert ReqLLM.Response.finish_reason(response) == :stop

        assert {:ok, response} = Cassette.generate_text(@model, "Say hello")
        assert ReqLLM.Response.text(response) == "Hello"
        assert ReqLLM.Response.usage(response) == %{input_tokens: 2, output_tokens: 1}
      end
    end

    test "replays tool calls with the test's own ids", %{tmp_dir: dir} do
      write_cassette(dir, "tools", [
        interaction("Find the page", %{
          "tool_calls" => [
            %{"id" => "call_1", "name" => "entry_outline", "arguments" => %{"id" => "{{page}}", "ref" => "page:{{page}}"}}
          ]
        })
      ])

      use_cassette "tools", dir: dir, bindings: %{page: 42} do
        assert {:ok, response} = Cassette.generate_text(@model, "Find the page")
        assert [call] = ReqLLM.Response.tool_calls(response)
        assert %{name: "entry_outline", arguments: %{"id" => 42, "ref" => "page:42"}} = ReqLLM.ToolCall.to_map(call)
        assert ReqLLM.Response.finish_reason(response) == :tool_calls
      end
    end

    test "ignores ids, uids and timestamps in tool results", %{tmp_dir: dir} do
      result = fn id, at ->
        ReqLLM.Context.new([
          ReqLLM.Context.user("Find it"),
          ReqLLM.Context.tool_result(
            "call_#{id}",
            "search",
            Jason.encode!(%{entries: [%{id: id, title: "Home", updated_at: at}]})
          )
        ])
      end

      ScriptedClient.start([{:text, "Found Home"}])

      use_cassette "volatile", dir: dir, mode: :record, client: ScriptedClient do
        assert {:ok, _} = Cassette.generate_text(@model, result.(1, "2026-10-01T10:00:00Z"))
      end

      use_cassette "volatile", dir: dir do
        assert "Found Home" = text(Cassette.generate_text(@model, result.(99, "2026-10-08T12:30:00Z")))
      end
    end

    test "a request that matches nothing fails with the difference", %{tmp_dir: dir} do
      write_cassette(dir, "strict", [interaction("Say hello", %{"text" => "Hello"})])

      error =
        assert_raise MismatchError, fn ->
          use_cassette "strict", dir: dir do
            # The caller gets the error as it would get a provider's…
            assert {:error, %MismatchError{}} = Cassette.generate_text(@model, "Say hi")
          end
        end

      # …and the test fails with it at the end of the block.
      message = Exception.message(error)
      assert message =~ ~s(cassette "strict" has no recorded request that matches this one)
      assert message =~ "messages[0].content"
      assert message =~ ~s(recorded: "Say hello")
      assert message =~ ~s(got:      "Say hi")
      assert message =~ "BRANDO_CASSETTE_MODE=record"
    end

    test "a recording plays once", %{tmp_dir: dir} do
      write_cassette(dir, "once", [interaction("Say hello", %{"text" => "Hello"})])

      error =
        assert_raise MismatchError, fn ->
          use_cassette "once", dir: dir do
            assert {:ok, _} = Cassette.generate_text(@model, "Say hello")
            assert {:error, _} = Cassette.generate_text(@model, "Say hello")
          end
        end

      assert Exception.message(error) =~ "already played"
    end

    test "custom matchers decide what must be equal", %{tmp_dir: dir} do
      write_cassette(dir, "loose", [interaction("Say hello at 10:00", %{"text" => "Hello"})])

      greeting? = fn recorded, request ->
        hd(recorded["messages"])["content"] =~ "hello" and hd(request["messages"])["content"] =~ "hello"
      end

      use_cassette "loose", dir: dir, match_on: [:model, greeting?] do
        assert "Hello" = text(Cassette.generate_text(@model, "Say hello at 11:15"))
      end
    end

    test "a missing cassette says how to record it", %{tmp_dir: dir} do
      error = assert_raise ArgumentError, fn -> use_cassette("absent", [dir: dir], do: :ok) end
      assert Exception.message(error) =~ "does not exist"
      assert Exception.message(error) =~ "BRANDO_CASSETTE_MODE=record"
    end

    test "unplayed recordings fail the test when asked to", %{tmp_dir: dir} do
      write_cassette(dir, "unused", [interaction("Say hello", %{"text" => "Hello"})])
      assert :ok = use_cassette("unused", [dir: dir], do: :ok)

      error = assert_raise ArgumentError, fn -> use_cassette("unused", [dir: dir, allow_unused: false], do: :ok) end
      assert Exception.message(error) =~ "did not play"
    end

    test "a recorded error is returned as a provider error", %{tmp_dir: dir} do
      write_cassette(dir, "failure", [
        interaction("Say hello", %{"error" => %{"status" => 429, "message" => "Slow down"}})
      ])

      use_cassette "failure", dir: dir do
        assert {:error, %ReqLLM.Error.API.Request{status: 429, reason: "Slow down"}} =
                 Cassette.generate_text(@model, "Say hello")
      end
    end
  end

  describe "record" do
    test "writes what the client answered, and replays it", %{tmp_dir: dir} do
      ScriptedClient.start([{:tools, [{"search_entries", %{"query" => "Home", "id" => 7}}]}, {:text, "Done"}])

      tools = [
        ReqLLM.Tool.new!(
          name: "search_entries",
          description: "Search",
          parameter_schema: [query: [type: :string]],
          callback: fn _ -> {:ok, nil} end
        )
      ]

      use_cassette "recorded", dir: dir, mode: :record, client: ScriptedClient, bindings: %{home: 7} do
        assert {:ok, first} = Cassette.generate_text(@model, "Find Home", tools: tools, max_tokens: 100)
        assert [_] = ReqLLM.Response.tool_calls(first)
        assert "Done" = text(Cassette.generate_text(@model, "Thanks", system_prompt: "Be brief"))
      end

      cassette = dir |> Path.join("recorded.json") |> File.read!() |> Jason.decode!()
      assert [first, second] = cassette["interactions"]

      assert %{
               "model" => @model,
               "params" => %{"max_tokens" => 100},
               "tools" => [%{"name" => "search_entries", "digest" => _}]
             } =
               first["request"]

      assert [%{"name" => "search_entries", "arguments" => %{"id" => "{{home}}", "query" => "Home"}}] =
               first["response"]["tool_calls"]

      assert second["request"]["system"] == "Be brief"
      assert second["response"]["text"] == "Done"

      use_cassette "recorded", dir: dir, bindings: %{home: 8} do
        assert {:ok, first} = Cassette.generate_text(@model, "Find Home", tools: tools, max_tokens: 100)
        assert [%{arguments: %{"id" => 8}}] = first |> ReqLLM.Response.tool_calls() |> Enum.map(&ReqLLM.ToolCall.to_map/1)
      end
    end

    test "auto records a missing cassette, then replays it", %{tmp_dir: dir} do
      ScriptedClient.start([{:text, "First"}])

      use_cassette "auto", dir: dir, mode: :auto, client: ScriptedClient do
        assert "First" = text(Cassette.generate_text(@model, "Hello"))
      end

      assert File.exists?(Path.join(dir, "auto.json"))

      # The script is used up; only the cassette can answer now.
      use_cassette "auto", dir: dir, mode: :auto, client: ScriptedClient do
        assert "First" = text(Cassette.generate_text(@model, "Hello"))
      end
    end

    test "never writes API keys or credentials", %{tmp_dir: dir} do
      key = "sk-test-" <> String.duplicate("a1B2", 8)
      ScriptedClient.start([{:text, "Your key is #{key}. Authorization: Bearer #{key}"}])

      use_cassette "secrets", dir: dir, mode: :record, client: ScriptedClient do
        assert {:ok, _} =
                 Cassette.generate_text(@model, "What is my key? It is #{key}",
                   api_key: key,
                   provider_options: [headers: [{"authorization", "Bearer #{key}"}]],
                   req_http_options: [headers: %{"x-api-key" => key}]
                 )
      end

      json = File.read!(Path.join(dir, "secrets.json"))
      refute json =~ key
      refute json =~ "a1B2a1B2"
      assert json =~ "[REDACTED]"
    end
  end

  describe "streams" do
    test "are recorded and replayed chunk by chunk", %{tmp_dir: dir} do
      ScriptedClient.start([{:text, "A ferry leaves the harbour"}])

      use_cassette "stream", dir: dir, mode: :record, client: ScriptedClient do
        assert {:ok, stream} = Cassette.stream_text(@model, "Describe it")
        assert stream |> StreamResponse.tokens() |> Enum.join() == "A ferry leaves the harbour"
      end

      cassette = dir |> Path.join("stream.json") |> File.read!() |> Jason.decode!()
      assert [%{"request" => %{"kind" => "stream"}, "response" => %{"chunks" => chunks}}] = cassette["interactions"]
      assert length(chunks) == 5

      use_cassette "stream", dir: dir do
        assert {:ok, stream} = Cassette.stream_text(@model, "Describe it")
        assert StreamResponse.tokens(stream) |> Enum.to_list() == ["A ", "ferry ", "leaves ", "the ", "harbour"]
        assert StreamResponse.finish_reason(stream) == :stop
        assert StreamResponse.usage(stream) == %{input_tokens: 1, output_tokens: 1}
      end
    end

    test "a stream and a plain request do not answer each other", %{tmp_dir: dir} do
      write_cassette(dir, "plain", [interaction("Describe it", %{"text" => "A ferry"})])

      assert_raise MismatchError, fn ->
        use_cassette "plain", dir: dir do
          assert {:error, %MismatchError{}} = Cassette.stream_text(@model, "Describe it")
        end
      end
    end
  end

  describe "scope" do
    @tag cassette: "cassette_test/hello"
    test "a tag puts a cassette in use for the test" do
      assert Cassette.active?()
      assert "Hello from the cassette" = text(Cassette.generate_text(@model, "Say hello"))
    end

    test "tasks and the processes they start use the test's cassette", %{tmp_dir: dir} do
      write_cassette(dir, "callers", [interaction("Say hello", %{"text" => "Hello"})])

      use_cassette "callers", dir: dir do
        task = Task.async(fn -> Task.async(fn -> Cassette.generate_text(@model, "Say hello") end) |> Task.await() end)
        assert "Hello" = text(Task.await(task))
      end
    end

    test "concurrent tests each use their own cassette", %{tmp_dir: dir} do
      write_cassette(dir, "left", [interaction("Who are you?", %{"text" => "Left"})])
      write_cassette(dir, "right", [interaction("Who are you?", %{"text" => "Right"})])
      parent = self()

      # Two processes stand in for two async tests.
      for name <- ["left", "right"] do
        spawn_link(fn ->
          use_cassette name, dir: dir do
            send(parent, {:ready, name, self()})
            receive do: (:go -> :ok)
            reply = Task.async(fn -> text(Cassette.generate_text(@model, "Who are you?")) end) |> Task.await()
            send(parent, {name, reply})
          end
        end)
      end

      # Waited for without a timeout of their own: `assert_receive`'s 100 ms
      # default ran out under load while the processes read their cassettes
      # and started their servers. The processes are linked, so one that
      # fails fails the test, and the test's own timeout bounds the wait.
      left = receive(do: ({:ready, "left", pid} -> pid))
      right = receive(do: ({:ready, "right", pid} -> pid))
      refute Cassette.active?()

      # Both ask at the same time, with the same request.
      send(left, :go)
      send(right, :go)

      assert receive(do: ({"left", reply} -> reply)) == "Left"
      assert receive(do: ({"right", reply} -> reply)) == "Right"
    end

    @tag cassette: "cassette_test/hello"
    test "one cassette per test" do
      assert_raise ArgumentError, ~r/has a cassette or stub in use already/, fn ->
        use_cassette("cassette_test/hello", do: :ok)
      end
    end

    test "without a cassette the cassette client refuses" do
      refute Cassette.active?()
      assert {:error, %ArgumentError{message: message}} = Cassette.generate_text(@model, "Hello")
      assert message =~ "no cassette is in use"
    end

    test "a stub answers from a function" do
      Cassette.stub(fn request -> "You said: " <> hd(request["messages"])["content"] end)
      assert "You said: Hi" = text(Cassette.generate_text(@model, "Hi"))
      assert [%{"messages" => [%{"content" => "Hi"}]}] = Cassette.requests()
    end
  end
end

defmodule Brando.AI.CassetteConfigTest do
  # Changes Brando.AI's application config.
  use ExUnit.Case, async: false
  use Brando.Test

  import Brando.Test.Support, only: [put_test_env: 2]

  setup do
    # A model, but no key, as in a project's test environment.
    put_test_env(Brando.AI, models: [default: "openai:gpt-4o-mini"], client: Brando.AI.Cassette)
    :ok
  end

  test "Brando.AI replays without an API key" do
    refute Brando.AI.configured?()
    assert {:error, :missing_api_key} = Brando.AI.generate_text("Say hello")

    use_cassette "cassette_test/hello" do
      assert Brando.AI.configured?()
      assert {:ok, %{text: "Hello from the cassette", usage: %{input_tokens: 3}}} = Brando.AI.generate_text("Say hello")
    end
  end

  test "the content assistant's client gives way to a cassette" do
    assert Brando.AI.client(MyApp.ScriptedModel) == MyApp.ScriptedModel
    assert Brando.AI.client() == Brando.AI.Cassette
    use_cassette("cassette_test/hello", do: assert(Brando.AI.client(MyApp.ScriptedModel) == Brando.AI.Cassette))
  end
end
