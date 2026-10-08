defmodule Brando.AI.Cassette do
  @moduledoc """
  Recorded model calls, so tests exercise AI flows without a live model or a key.

  A cassette is a JSON file of request/reply pairs. While a cassette is in use,
  every model call that `Brando.AI` and the content assistant make from the
  test — or from a LiveView, task or inline job the test started — goes to
  the cassette instead of the provider:

      use Brando.Test  # in your DataCase / ConnCase, or import Brando.AI.Cassette

      test "writes alt text" do
        use_cassette "alt_text/lighthouse" do
          assert {:ok, _} = Brando.Images.AltText.generate(image, user)
        end
      end

      @tag cassette: "assistant/add_block"
      test "the assistant prepares a proposal", %{conn: conn} do
        …
      end

  ## Modes

    * `:replay` (the default) answers from the file and fails the test when a
      request matches no recorded one. It needs no key: when none is
      configured, `Brando.AI` uses a placeholder.
    * `:record` calls the real model through the configured client (ReqLLM),
      which needs a key, and writes the file at the end of the test.
    * `:auto` replays when the file exists and records when it does not.

  The mode comes from, in order: the `BRANDO_CASSETTE_MODE` environment
  variable (`replay`, `record` or `auto`), the `mode:` option, and
  `config :brando, Brando.AI.Cassette, mode: …`. To record one test again:

      BRANDO_CASSETTE_MODE=record mix test test/my_app/alt_text_test.exs

  ## Options

    * `:mode` — see above.
    * `:dir` — where cassettes live; `config :brando, Brando.AI.Cassette, dir: …`,
      default `"test/cassettes"`. The file is `<dir>/<name>.json`.
    * `:match_on` — what must match; see `Brando.AI.Cassette.Matcher`.
    * `:bindings` — a map of names to values that differ between runs, such as
      database ids. They are written as `"{{name}}"` when recording, and filled
      in from the map on replay, so a recorded tool call can name an entry the
      test has just created. `bind/1` adds them from inside the test.
    * `:ignore_keys` — keys in tool results and arguments whose values change
      between runs and do not matter to the test, such as a list of suggested
      ids. Ids, uids and timestamps are ignored already.
    * `:client` — the client that answers in `:record` mode. Anything with
      ReqLLM's `generate_text/3` (and `stream_text/3`, to record streams):
      the configured client by default, or a fake to build a cassette by hand.
    * `:allow_unused` — `false` fails the test if recorded interactions were
      not played. Default `true`.

  ## What is recorded

  The request is normalised (`Brando.AI.Cassette.Request`): the model, the
  system prompt, the messages, the tools and the model parameters, with ids,
  UUIDs and timestamps blanked out. The reply keeps its text, tool calls,
  usage and finish reason (`Brando.AI.Cassette.Response`). Streams are
  recorded and replayed chunk by chunk. API keys and credentials are never
  written (`Brando.AI.Cassette.Redact`).

  ## Stubs

  `stub/2` answers with a function instead of a file, for tests where the
  reply depends on the prompt:

      Brando.AI.Cassette.stub(fn request -> %{"text" => "About " <> hd(request["messages"])["content"]} end)
  """

  require Logger

  alias Brando.AI.Cassette.{Matcher, MismatchError, Redact, Request, Response, Server}

  @modes [:replay, :record, :auto]
  @version 1

  ## The test API

  @doc """
  Use cassette `name` for the code in the block, then check it: a request that
  did not match raises `Brando.AI.Cassette.MismatchError`, and in `:record`
  mode the file is written.
  """
  defmacro use_cassette(name, opts \\ [], do: block) do
    quote do
      Brando.AI.Cassette.with_cassette(unquote(name), unquote(opts), fn -> unquote(block) end)
    end
  end

  @doc "The function behind `use_cassette/3`."
  @spec with_cassette(String.t(), keyword(), (-> result)) :: result when result: term()
  def with_cassette(name, opts, fun) do
    {:ok, server} = start(name, opts)

    try do
      fun.()
    after
      check!(self(), server)
    end
  end

  @doc """
  An ExUnit `setup` callback for `@tag cassette: "name"`, with options in
  `@tag cassette_opts: [...]`. `use Brando.Test` adds it.
  """
  @spec setup_tags(map()) :: :ok
  def setup_tags(%{cassette: name} = tags) when is_binary(name) do
    owner = self()
    {:ok, server} = start(name, Map.get(tags, :cassette_opts, []))
    ExUnit.Callbacks.on_exit({__MODULE__, name}, fn -> check!(owner, server) end)
    :ok
  end

  def setup_tags(_tags), do: :ok

  @doc """
  Start cassette `name` for the calling process and the processes it starts.
  Returns `{:ok, server}`; `stop/1` ends it. Most tests use `use_cassette/3`
  or the `:cassette` tag instead.
  """
  @spec start(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start(name, opts \\ []) do
    path = path(name, opts)
    mode = mode(opts, path)

    interactions =
      if mode == :replay,
        do: read!(name, path),
        else: []

    Server.start(self(), %{
      name: name,
      path: path,
      mode: mode,
      stub: nil,
      interactions: interactions,
      used: [],
      recorded: [],
      played: [],
      failures: [],
      match_on: Keyword.get(opts, :match_on, Matcher.default()),
      bindings: Map.new(Keyword.get(opts, :bindings, %{})),
      ignore_keys: Keyword.get(opts, :ignore_keys, []),
      client: Keyword.get(opts, :client),
      allow_unused: Keyword.get(opts, :allow_unused, true)
    })
  end

  @doc """
  Answer every model call from the calling process (and the processes it
  starts) with `fun`, for the rest of the test.

  `fun` gets the normalised request (see `Brando.AI.Cassette.Request`) and
  returns a reply as a cassette records it: `%{"text" => …}`,
  `%{"tool_calls" => [%{"name" => …, "arguments" => %{…}}]}`, `%{"chunks" => […]}`
  for a stream, or `%{"error" => %{"status" => 500, "message" => …}}`.
  A plain string is taken as the text.

  Stops when the test exits; `on_exit: false` leaves it to `stop/1`.
  """
  @spec stub((map() -> map() | String.t()), keyword()) :: {:ok, pid()}
  def stub(fun, opts \\ []) when is_function(fun, 1) do
    owner = self()
    reply = fn request -> wrap(fun.(request)) end

    {:ok, server} =
      case Server.lookup() do
        server when is_pid(server) ->
          :sys.replace_state(server, &%{&1 | stub: reply})
          {:ok, server}

        nil ->
          Server.start(owner, %{
            name: "stub",
            path: nil,
            mode: :replay,
            stub: reply,
            interactions: [],
            used: [],
            recorded: [],
            played: [],
            failures: [],
            match_on: [],
            bindings: %{},
            ignore_keys: [],
            client: nil,
            allow_unused: true
          })
      end

    if Keyword.get(opts, :on_exit, true),
      do: ExUnit.Callbacks.on_exit({__MODULE__, :stub}, fn -> stop(owner) end)

    {:ok, server}
  end

  defp wrap(text) when is_binary(text), do: %{"text" => text}
  defp wrap(reply) when is_map(reply), do: reply

  @doc "Stop the cassette `owner` started, without checking it. Returns its final state."
  @spec stop(pid()) :: map() | nil
  def stop(owner \\ self()) do
    case :ets.whereis(Brando.AI.Cassette.Registry) != :undefined and :ets.lookup(Brando.AI.Cassette.Registry, owner) do
      [{^owner, server}] -> Server.stop(owner, server)
      _ -> nil
    end
  end

  @doc """
  Add bindings to the cassette in use, for values a test only knows once it
  has created its data — with `@tag cassette: …`, say:

      Brando.AI.Cassette.bind(page: page.id, module: "local:\#{module.id}")
  """
  @spec bind(keyword() | map()) :: :ok
  def bind(bindings) do
    case Server.lookup() do
      nil -> raise ArgumentError, "no cassette is in use for this process"
      server -> Server.bind(server, Map.new(bindings))
    end
  end

  @doc "The requests played so far, normalised, in order."
  @spec requests() :: [map()]
  def requests do
    case Server.lookup() do
      nil -> []
      server -> Server.state(server).played
    end
  end

  @doc "Whether a cassette or stub answers model calls from the calling process."
  @spec active?() :: boolean()
  def active?, do: Server.lookup() != nil

  @doc """
  Whether model calls from the calling process are answered without a
  provider, so no API key is needed.
  """
  @spec replaying?() :: boolean()
  def replaying? do
    case Server.lookup() do
      nil -> false
      server -> Server.state(server).mode == :replay
    end
  end

  defp check!(owner, server) do
    state = Server.stop(owner, server)

    if state.mode == :record, do: write!(state)

    case state.failures do
      [error | _] ->
        raise error

      [] ->
        unused = length(state.interactions) - length(state.used)

        if state.mode == :replay and not state.allow_unused and unused > 0,
          do:
            raise(
              ArgumentError,
              "cassette #{inspect(state.name)} has #{unused} recorded interaction(s) the test did not play"
            )

        :ok
    end
  end

  ## The client

  @doc "ReqLLM's `generate_text/3`, answered from the cassette."
  @spec generate_text(term(), term(), keyword()) :: {:ok, ReqLLM.Response.t()} | {:error, term()}
  def generate_text(model, prompt, opts \\ []) do
    call(:generate, model, prompt, opts)
  end

  @doc "ReqLLM's `stream_text/3`, answered from the cassette chunk by chunk."
  @spec stream_text(term(), term(), keyword()) :: {:ok, ReqLLM.StreamResponse.t()} | {:error, term()}
  def stream_text(model, prompt, opts \\ []) do
    call(:stream, model, prompt, opts)
  end

  defp call(kind, model, prompt, opts) do
    case Server.lookup() do
      nil ->
        {:error,
         ArgumentError.exception(
           "no cassette is in use for this process. Wrap the test in use_cassette/2 or tag it with " <>
             "@tag cassette: \"name\" (Brando.AI.Cassette)"
         )}

      server ->
        state = Server.state(server)
        request = Request.normalize(kind, model, prompt, opts, state.bindings, state.ignore_keys)

        if state.mode == :record,
          do: record(kind, server, state, request, model, prompt, opts),
          else: replay(kind, server, state, request, model, prompt, opts)
    end
  end

  defp replay(kind, server, state, request, model, prompt, opts) do
    case Server.play(server, request) do
      {:ok, reply} ->
        load(kind, reply, model, prompt, opts, state.bindings)

      {:error, %MismatchError{} = error} ->
        # Said now as well as at the end of the test: the code that made the
        # request may turn the error into something less telling first.
        Logger.error(Exception.message(error))
        {:error, error}
    end
  rescue
    error in ArgumentError ->
      Server.fail(server, error)
      {:error, error}
  end

  defp load(:generate, reply, model, prompt, opts, bindings), do: Response.load(reply, model, prompt, opts, bindings)
  defp load(:stream, reply, model, prompt, opts, bindings), do: Response.load_stream(reply, model, prompt, opts, bindings)

  defp record(:generate, server, state, request, model, prompt, opts) do
    client = recording_client(state)
    secrets = [opts[:api_key]]

    result = client.generate_text(model, prompt, opts)

    reply =
      case result do
        {:ok, response} -> Response.dump(response)
        {:error, error} -> Response.dump_error(error)
      end

    Server.record(
      server,
      Redact.redact(request, secrets),
      reply |> Request.bind(state.bindings) |> Redact.redact(secrets)
    )

    result
  end

  defp record(:stream, server, state, request, model, prompt, opts) do
    client = recording_client(state)
    secrets = [opts[:api_key]]

    case client.stream_text(model, prompt, opts) do
      {:ok, %ReqLLM.StreamResponse{} = response} ->
        {:ok, %{response | stream: tap(response, server, state, request, secrets)}}

      {:error, error} = result ->
        Server.record(server, Redact.redact(request, secrets), error |> Response.dump_error() |> Redact.redact(secrets))
        result
    end
  end

  # Passes the chunks through as the caller reads them, and records them once
  # the stream is read to the end.
  defp tap(response, server, state, request, secrets) do
    Stream.transform(
      response.stream,
      fn -> [] end,
      fn chunk, acc -> {[chunk], [chunk | acc]} end,
      fn acc ->
        metadata = ReqLLM.StreamResponse.MetadataHandle.await(response.metadata_handle)
        reply = acc |> Enum.reverse() |> Response.dump_stream(metadata) |> Request.bind(state.bindings)
        Server.record(server, Redact.redact(request, secrets), Redact.redact(reply, secrets))
        {[], acc}
      end,
      fn _acc -> :ok end
    )
  end

  defp recording_client(%{client: client}) when not is_nil(client), do: client

  defp recording_client(_state) do
    case Brando.AI.configured_client() do
      __MODULE__ -> ReqLLM
      client -> client
    end
  end

  ## Files

  @doc "The file for cassette `name`."
  @spec path(String.t(), keyword()) :: String.t()
  def path(name, opts \\ []) do
    dir = Keyword.get(opts, :dir) || Keyword.get(config(), :dir, "test/cassettes")
    Path.expand(name <> ".json", dir)
  end

  defp mode(opts, path) do
    mode =
      case System.get_env("BRANDO_CASSETTE_MODE") do
        mode when mode in ["replay", "record", "auto"] -> String.to_existing_atom(mode)
        _ -> Keyword.get(opts, :mode) || Keyword.get(config(), :mode, :replay)
      end

    unless mode in @modes,
      do: raise(ArgumentError, "unknown cassette mode #{inspect(mode)}; use one of #{inspect(@modes)}")

    cond do
      mode != :auto -> mode
      File.exists?(path) -> :replay
      true -> :record
    end
  end

  defp read!(name, path) do
    case File.read(path) do
      {:ok, json} ->
        json |> Jason.decode!() |> Map.get("interactions", [])

      {:error, :enoent} ->
        raise ArgumentError,
              "cassette #{inspect(name)} does not exist at #{Path.relative_to_cwd(path)}. " <>
                "Record it with BRANDO_CASSETTE_MODE=record (calls the real model, so it needs a key)"
    end
  end

  defp write!(state) do
    File.mkdir_p!(Path.dirname(state.path))

    json =
      %{"cassette" => state.name, "version" => @version, "interactions" => state.recorded}
      |> Redact.redact()
      |> Request.ordered()
      |> Jason.encode!(pretty: true)

    File.write!(state.path, json <> "\n")
  end

  defp config, do: Application.get_env(:brando, __MODULE__, [])
end
