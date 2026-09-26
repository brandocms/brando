defmodule Brando.AI.Agent.Loop do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  One agent run: call the model, execute the tools it asks for, and repeat
  until it answers in text, the step limit is reached, the budget runs out or
  the user cancels.

  Tools execute in this process through `Brando.Content.Proposals.Tools`, with
  the conversation's user. Every message is stored as it happens, so a
  reconnecting admin shows the run's progress and a later run continues the
  same conversation.
  """
  import Ecto.Query, only: [from: 2]
  require Logger

  alias Brando.AI.Agent
  alias Brando.AI.Agent.{Budget, Conversation, Message, Prompt, Run}
  alias Brando.Content.Proposals.Tools
  alias Brando.Repo
  alias ReqLLM.{Context, Response, ToolCall}

  @result_limit 24_000

  @doc "Run `run_id` for user `user_id` to completion and return the finished run."
  @spec run(Ecto.UUID.t(), integer()) :: Run.t()
  def run(run_id, user_id) do
    run = Repo.get!(Run, run_id)
    user = Repo.get!(Brando.Users.User, user_id)
    # Progress and the assistant's own notices are shown in the editor's
    # language; this process does not inherit the LiveView's locale.
    Gettext.put_locale(Brando.Gettext, to_string(user.language || Brando.config(:default_admin_language) || "en"))

    case Brando.AI.request(Agent.model_opts()) do
      {:ok, request} -> step(run, user, request, 1)
      {:error, reason} -> finish(run, "failed", inspect(reason))
    end
  rescue
    error ->
      Logger.error("Content agent run #{run_id} failed: " <> Exception.format(:error, error, __STACKTRACE__))
      run_id |> then(&Repo.get(Run, &1)) |> finish("failed", Exception.message(error))
  end

  defp step(run, user, request, n) do
    config = Agent.config()
    run = Repo.get!(Run, run.id)
    conversation = Repo.get!(Conversation, run.conversation_id)

    cond do
      run.status != "running" ->
        run

      n > config[:max_steps] ->
        say(
          run,
          dgettext("ai_agent", "I stopped after %{steps} steps. Tell me how to continue.", steps: config[:max_steps])
        )

        finish(run, "completed", "step limit")

      true ->
        context = context(conversation)

        case Budget.reserve(run, Budget.estimate(context) + config[:max_tokens]) do
          {:ok, run} -> call(run, user, request, conversation, context, n)
          {:error, :exhausted} -> exhausted(run)
        end
    end
  end

  defp call(run, user, request, conversation, context, n) do
    Agent.broadcast(conversation.id, {:progress, dgettext("ai_agent", "Thinking")})

    opts =
      Keyword.merge(request.req_opts, tools: tools(), max_tokens: Agent.config()[:max_tokens])

    case Agent.config()[:client].generate_text(request.model, context, opts) do
      {:ok, response} ->
        run = Budget.reconcile(run, Response.usage(response), request.model)
        respond(run, user, request, conversation, response, n)

      {:error, error} ->
        run |> Budget.reconcile(%{}, request.model) |> finish("failed", error_message(error))
    end
  end

  defp respond(run, user, request, conversation, response, n) do
    text = response |> Response.text() |> to_string() |> String.trim()

    case Response.tool_calls(response) do
      [] ->
        say(run, if(text == "", do: dgettext("ai_agent", "Done."), else: text))
        finish(run, "completed")

      calls ->
        calls = Enum.map(calls, &ToolCall.to_map/1)

        insert(run, %{
          role: "assistant",
          content: text,
          tool_calls: Enum.map(calls, &%{"id" => &1.id, "name" => &1.name, "arguments" => Jason.encode!(&1.arguments)})
        })

        Enum.each(calls, &execute(&1, run, user, conversation))
        step(run, user, request, n + 1)
    end
  end

  defp execute(%{id: id, name: name, arguments: args}, run, user, conversation) do
    # Re-read: a proposal prepared by an earlier call in this step is the one
    # a later call refines.
    conversation = Repo.get!(Conversation, conversation.id)

    if Repo.get!(Run, run.id).status == "running" do
      Agent.broadcast(conversation.id, {:progress, progress(name, args)})

      result =
        case Tools.call(name, args, tool_context(conversation, user)) do
          {:ok, result} -> result
          {:error, message} -> %{error: message}
        end

      track_proposal(conversation, result)
      insert(run, %{role: "tool", tool_call_id: id, tool_name: name, content: encode(result)})
    else
      # The model still needs a result for every call it made.
      insert(run, %{role: "tool", tool_call_id: id, tool_name: name, content: ~s({"error":"cancelled"})})
    end
  end

  defp track_proposal(conversation, %{proposal_id: id}) do
    conversation |> Ecto.Changeset.change(proposal_id: id) |> Repo.update!()
    Agent.broadcast(conversation.id, {:proposal, id})
  end

  defp track_proposal(_conversation, _result), do: :ok

  defp tool_context(conversation, user) do
    %Tools.Context{
      actor: user,
      conversation_id: conversation.id,
      proposal_id: conversation.proposal_id,
      # Uploads still in progress have an alias but no asset yet.
      attachments:
        for a <- conversation.attachments, a["id"], into: %{} do
          {a["alias"], %{kind: String.to_existing_atom(a["kind"]), id: a["id"], label: a["label"]}}
        end
    }
  end

  @doc "The tool definitions, as ReqLLM tools. Brando executes them itself, with the conversation's user."
  @spec tools() :: [ReqLLM.Tool.t()]
  def tools do
    Enum.map(Tools.definitions(), fn definition ->
      ReqLLM.Tool.new!(
        name: definition.name,
        description: definition.description,
        parameter_schema: definition.parameters |> Jason.encode!() |> Jason.decode!(),
        # Brando executes tools itself, with the conversation's user.
        callback: fn _args -> {:error, :executed_by_brando} end
      )
    end)
  end

  # Tools that read content. Their results go stale when the editor writes
  # again: the editor may have saved the entry, or be asking about it anew.
  @reads ~w(list_content_types describe_content_type search_entries entry_outline list_modules describe_module
            list_attachments search_assets find_media_folders list_selection_options)
  @stale Jason.encode!(%{
           stale:
             "Read before the editor's latest message; the content may have changed since. " <>
               "Call the tool again for current data before you rely on it."
         })

  @doc """
  Rebuild the model context from the stored messages. Runs are stateless, so
  a restart or a later message continues the same conversation.

  Results of reading tools from before the editor's latest message are
  replaced by a note to read again, so the model does not answer from an
  outline the editor has since changed — and does not pay for it twice.
  """
  @spec context(Conversation.t()) :: Context.t()
  def context(conversation) do
    messages =
      Repo.all(
        from(m in Message,
          where: m.conversation_id == ^conversation.id,
          order_by: [asc: m.inserted_at, asc: m.id]
        )
      )

    latest = messages |> Enum.map(& &1.role) |> Enum.with_index() |> Enum.filter(&(elem(&1, 0) == "user")) |> List.last()
    latest = if latest, do: elem(latest, 1), else: -1

    messages =
      messages
      |> Enum.with_index()
      |> Enum.map(fn
        {%Message{role: "tool", tool_name: name} = message, index} when index < latest and name in @reads ->
          %{message | content: @stale}

        {message, _index} ->
          message
      end)

    Context.new([Context.system(Prompt.system(conversation)) | Enum.flat_map(messages, &message/1)])
  end

  defp message(%Message{role: "user", content: content}), do: [Context.user(content)]

  defp message(%Message{role: "assistant", tool_calls: [_ | _] = calls, content: content}) do
    calls = Enum.map(calls, &ToolCall.new(&1["id"], &1["name"], &1["arguments"]))
    [Context.assistant(content || "", tool_calls: calls)]
  end

  defp message(%Message{role: "assistant", content: content}), do: [Context.assistant(content || "")]

  defp message(%Message{role: "tool"} = m), do: [Context.tool_result(m.tool_call_id, m.tool_name, m.content || "")]

  defp message(_), do: []

  defp progress("search_entries", args), do: dgettext("ai_agent", "Searching for “%{query}”", query: args["query"])
  defp progress("entry_outline", _), do: dgettext("ai_agent", "Reading an entry")
  defp progress("describe_module", _), do: dgettext("ai_agent", "Checking a module's slots")
  defp progress("list_modules", _), do: dgettext("ai_agent", "Looking at the available modules")
  defp progress("search_assets", _), do: dgettext("ai_agent", "Searching the media library")
  defp progress("find_media_folders", _), do: dgettext("ai_agent", "Looking for the folder")
  defp progress("attach_folder", _), do: dgettext("ai_agent", "Attaching the folder's media")
  defp progress("prepare_proposal", _), do: dgettext("ai_agent", "Checking the proposal")
  defp progress("list_attachments", _), do: dgettext("ai_agent", "Looking at the attachments")
  defp progress("list_selection_options", _), do: dgettext("ai_agent", "Looking at the entries a block can show")
  defp progress("request_media", _), do: dgettext("ai_agent", "Asking you for media")
  defp progress(_, _), do: dgettext("ai_agent", "Looking at the site's content")

  defp encode(result) do
    json = Jason.encode!(result)

    if byte_size(json) > @result_limit,
      do: Jason.encode!(%{error: "The result was too large. Narrow the request.", size: byte_size(json)}),
      else: json
  end

  defp exhausted(run) do
    say(run, dgettext("ai_agent", "The assistant's token budget is used up. Nothing more was sent to the model."))
    finish(run, "budget_exhausted")
  end

  defp say(run, text), do: insert(run, %{role: "assistant", content: text})

  defp insert(run, attrs) do
    message = Repo.insert!(struct(Message, Map.merge(attrs, %{conversation_id: run.conversation_id, run_id: run.id})))
    Agent.broadcast(run.conversation_id, {:message, message})
    message
  end

  defp finish(run, status, error \\ nil)
  defp finish(nil, _status, _error), do: nil

  defp finish(run, status, error) do
    run = Repo.get!(Run, run.id)

    # A cancelled run keeps its status; the steps already taken are recorded.
    run =
      if run.status == "running" do
        run
        |> Ecto.Changeset.change(status: status, error: error, reserved_tokens: 0, finished_at: DateTime.utc_now())
        |> Repo.update!()
      else
        run
      end

    if status == "failed" and run.status == "failed",
      do: say(run, dgettext("ai_agent", "Something went wrong: %{error}", error: error))

    Agent.broadcast(run.conversation_id, {:progress, nil})
    Agent.broadcast(run.conversation_id, {:run, run})
    run
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)
end
