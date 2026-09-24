defmodule Brando.AIStub do
  @moduledoc """
  Points `Brando.AI` at a `Req.Test` stub instead of a provider.

  `Brando.AI` forwards `default_opts` to ReqLLM untouched, so the stub is
  plain configuration: ReqLLM hands `req_http_options: [plug: …]` to Req, and
  the reply below is what OpenAI's Responses API sends back. `Req.Test` stubs
  follow `$callers`, so `start_async` tasks and inline Oban jobs see them.

      setup do
        Brando.AIStub.configure()
        Brando.AIStub.reply("A description")
      end
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc "Configures a provider and restores the previous configuration on exit."
  def configure do
    previous = Application.get_env(:brando, Brando.AI)

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
