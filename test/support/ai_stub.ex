defmodule Brando.AIStub do
  @moduledoc """
  Configures `Brando.AI` for a test and answers its model calls from a
  function, through `Brando.AI.Cassette.stub/2`.

  For flows with fixed replies, prefer a recorded cassette (`use_cassette/3`
  or `@tag cassette: "name"`); this is for replies that depend on the prompt.
  The stub is scoped to the test process and the processes it starts —
  LiveViews, their `start_async` tasks and inline Oban jobs — through
  `$callers`.

      setup do
        Brando.AIStub.configure()
        Brando.AIStub.reply("A description")
      end
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Brando.AI.Cassette

  @doc """
  Configures a provider and restores the previous configuration on exit. The
  client is `Brando.AI.Cassette`, so a call no stub or cassette answers fails
  instead of reaching a provider.
  """
  def configure do
    previous = Application.get_env(:brando, Brando.AI)

    Application.put_env(:brando, Brando.AI,
      enabled: true,
      default_model: "openai:gpt-4o-mini",
      providers: [openai: [api_key: "test-key"]],
      client: Cassette
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
    Cassette.stub(fn request ->
      case fun.(prompt(request)) do
        {:error, status} -> %{"error" => %{"status" => status, "message" => "stubbed failure"}}
        text -> %{"text" => text, "usage" => %{"input_tokens" => 1, "output_tokens" => 1}}
      end
    end)
  end

  @doc """
  Answers successive requests with `turns`, in order: `{:text, text}` for a
  final answer, or `{:tools, [{name, args}]}` for function calls. Every
  request is sent to the test process as `{:ai_request, request}`, normalised
  as `Brando.AI.Cassette.Request` describes.
  """
  def script(turns) when is_list(turns) do
    test = self()
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

    Cassette.stub(fn request ->
      send(test, {:ai_request, request})
      n = Elixir.Agent.get_and_update(counter, &{&1, &1 + 1})
      turn(Enum.at(turns, n), n)
    end)
  end

  @doc "The reply a cassette records for one scripted turn."
  def turn({:text, text}, _n), do: %{"text" => text, "usage" => %{"input_tokens" => 1, "output_tokens" => 1}}

  def turn({:tools, calls}, n) do
    %{
      "tool_calls" =>
        calls
        |> Enum.with_index()
        |> Enum.map(fn {{name, args}, i} -> %{"id" => "call_#{n}_#{i}", "name" => name, "arguments" => args} end),
      "usage" => %{"input_tokens" => 100, "output_tokens" => 20}
    }
  end

  def turn({:error, status}, _n), do: %{"error" => %{"status" => status, "message" => "stubbed"}}
  def turn(nil, n), do: turn({:text, "(script exhausted)"}, n)

  @doc "The text of a normalised request: its system prompt and messages."
  def prompt(request) do
    [request["system"] | Enum.map(request["messages"] || [], & &1["content"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", &text/1)
  end

  defp text(text) when is_binary(text), do: text

  defp text(parts) when is_list(parts) do
    Enum.map_join(parts, "\n", fn
      %{"type" => "text", "text" => text} -> text(text)
      %{"type" => _} -> ""
      other -> text(other)
    end)
  end

  defp text(other), do: Jason.encode!(other)
end

defmodule Brando.AIStub.ScriptedClient do
  @moduledoc """
  A fake provider that answers from a script of turns, as `Brando.AIStub.script/1`
  takes them. It speaks ReqLLM's `generate_text/3` and `stream_text/3`, so a
  cassette can record from it — that is how Brando's own cassettes were made
  without a model or a key:

      Brando.AIStub.ScriptedClient.start([{:tools, [{"search_entries", %{"query" => "Ident"}}]}, {:text, "Done"}])
      use_cassette "assistant/example", mode: :record, client: Brando.AIStub.ScriptedClient do
        …
      end

  A streamed text turn arrives a word at a time.
  """
  alias Brando.AI.Cassette.Response

  def start(turns) do
    owner = self()
    {:ok, script} = Elixir.Agent.start(fn -> {turns, 0} end)
    :persistent_term.put({__MODULE__, owner}, script)

    ExUnit.Callbacks.on_exit(fn ->
      :persistent_term.erase({__MODULE__, owner})
      if Process.alive?(script), do: Elixir.Agent.stop(script)
    end)

    :ok
  end

  def generate_text(model, prompt, opts) do
    {turn, n} = next()
    Response.load(Brando.AIStub.turn(turn, n), model, prompt, opts, %{})
  end

  def stream_text(model, prompt, opts) do
    {turn, n} = next()

    reply =
      case Brando.AIStub.turn(turn, n) do
        %{"text" => text} = reply ->
          chunks = text |> String.split(~r/(?<= )/) |> Enum.map(&%{"type" => "content", "text" => &1})
          reply |> Map.delete("text") |> Map.merge(%{"chunks" => chunks, "finish_reason" => "stop"})

        reply ->
          reply
      end

    Response.load_stream(reply, model, prompt, opts, %{})
  end

  defp next do
    script =
      Enum.find_value([self() | Process.get(:"$callers", [])], fn pid ->
        :persistent_term.get({__MODULE__, pid}, nil)
      end) || raise "Brando.AIStub.ScriptedClient.start/1 was not called by this test"

    Elixir.Agent.get_and_update(script, fn {turns, n} -> {{Enum.at(turns, n), n}, {turns, n + 1}} end)
  end
end
