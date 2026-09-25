defmodule Brando.AIStub do
  @moduledoc """
  Points `Brando.AI` at a `Req.Test` stub instead of a provider.

  `Brando.AI` forwards `default_opts` to ReqLLM untouched, so the stub is
  plain configuration: ReqLLM hands `req_http_options: [plug: …]` to Req, and
  the reply below is what OpenAI's Responses API sends back. `Req.Test` stubs
  follow `$callers`, which covers inline Oban jobs; LiveView tests pass
  `shared: true`, the way `Brando.LiveCase` shares the SQL sandbox, so the
  view's `start_async` tasks see the stub too.

      setup do
        Brando.AIStub.configure()
        Brando.AIStub.reply("A description")
      end
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Configures a provider and restores the previous configuration on exit.
  `shared: true` makes the stub global — only for tests that are not async.
  """
  def configure(opts \\ []) do
    previous = Application.get_env(:brando, Brando.AI)

    if opts[:shared] do
      Req.Test.set_req_test_to_shared(%{async: false})
      on_exit(fn -> Req.Test.set_req_test_to_private() end)
    end

    Application.put_env(:brando, Brando.AI,
      enabled: true,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-key"]],
      default_opts: [req_http_options: [plug: {Req.Test, Brando.AI}, retry: false]]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Brando.AI, previous),
        else: Application.delete_env(:brando, Brando.AI)
    end)
  end

  @doc """
  Answers every request with `text`, or with whatever `fun` returns for the
  prompt it was sent. Returning `{:error, status}` answers with that HTTP status.
  """
  def reply(text) when is_binary(text), do: reply(fn _prompt -> text end)

  def reply(fun) when is_function(fun, 1) do
    Req.Test.stub(Brando.AI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case fun.(prompt(body)) do
        {:error, status} ->
          conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"error" => %{"message" => "stubbed failure"}})

        text ->
          Req.Test.json(conn, response(text))
      end
    end)
  end

  @doc """
  Answers successive requests with `turns`, in order: `{:text, text}` for a
  final answer, or `{:tools, [{name, args}]}` for function calls. Every
  request body is sent to the test process as `{:ai_request, body}`.
  """
  def script(turns) when is_list(turns) do
    test = self()
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

    Req.Test.stub(Brando.AI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:ai_request, Jason.decode!(body)})
      n = Elixir.Agent.get_and_update(counter, &{&1, &1 + 1})

      case Enum.at(turns, n) do
        {:text, text} -> Req.Test.json(conn, response(text))
        {:tools, calls} -> Req.Test.json(conn, tool_response(calls, n))
        {:error, status} -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"error" => %{"message" => "stubbed"}})
        nil -> Req.Test.json(conn, response("(script exhausted)"))
      end
    end)
  end

  defp tool_response(calls, n) do
    output =
      calls
      |> Enum.with_index()
      |> Enum.map(fn {{name, args}, i} ->
        %{
          "type" => "function_call",
          "id" => "fc_#{n}_#{i}",
          "call_id" => "call_#{n}_#{i}",
          "name" => name,
          "arguments" => Jason.encode!(args),
          "status" => "completed"
        }
      end)

    %{
      "id" => "resp_#{n}",
      "object" => "response",
      "status" => "completed",
      "model" => "gpt-4o-mini",
      "output" => output,
      "usage" => %{"input_tokens" => 100, "output_tokens" => 20, "total_tokens" => 120}
    }
  end

  defp prompt(body) do
    body
    |> Jason.decode!()
    |> Map.get("input")
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"content" => content} when is_binary(content) -> [content]
      %{"content" => parts} when is_list(parts) -> Enum.map(parts, &Map.get(&1, "text", ""))
      _ -> []
    end)
    |> Enum.join("\n")
  end

  defp response(text) do
    %{
      "id" => "resp_stub",
      "object" => "response",
      "status" => "completed",
      "model" => "gpt-4o-mini",
      "output" => [
        %{
          "type" => "message",
          "id" => "msg_stub",
          "role" => "assistant",
          "status" => "completed",
          "content" => [%{"type" => "output_text", "text" => text, "annotations" => []}]
        }
      ],
      "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
    }
  end
end
