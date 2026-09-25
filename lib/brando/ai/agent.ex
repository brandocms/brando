defmodule Brando.AI.Agent do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  The admin's content agent: conversations in which a user describes content
  changes and a model prepares a proposal for them to review.

  The model runs in the Brando backend. It reaches Brando only through
  `Brando.Content.Proposals.Tools`, called in-process with the conversation's
  user — there is no MCP endpoint, route or port. It can read content and
  prepare proposals; approving and applying stay with the user in the admin.

      {:ok, conversation} = Agent.start_conversation(user)
      {:ok, "image1"} = Agent.attach(conversation.id, {:image, 12}, user)
      {:ok, run} = Agent.send_message(conversation.id, "Add the lobby photo to the Sommerro case", user)

  Progress arrives on `subscribe/1` as `{:agent, conversation_id, event}`:
  `{:message, message}`, `{:progress, text}`, `{:proposal, proposal_id}` and
  `{:run, run}`.

  ## Configuration

      config :brando, Brando.AI.Agent,
        model: "anthropic:claude-opus-5-5",   # defaults to Brando.AI's default model
        max_steps: 12,                        # model calls per run
        max_tokens: 4096,                     # output tokens per model call
        run_token_budget: 300_000,            # input + output tokens per run
        monthly_token_budget: 5_000_000,      # per site/environment; nil for none
        prices: [input: 5.0, output: 25.0]    # USD per million tokens; otherwise the
                                              # provider's or catalogue's price

  Keys come from `Brando.AI`'s provider configuration.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.AI.Agent.{Conversation, Loop, Message, Run}
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.{Dependencies, Error}
  alias Brando.Repo
  alias Ecto.Changeset

  @stale_after :timer.minutes(10)

  @doc "The agent's configuration, with defaults."
  @spec config() :: keyword()
  def config do
    Keyword.merge(
      [model: nil, max_steps: 12, max_tokens: 4096, run_token_budget: 300_000, monthly_token_budget: nil],
      Application.get_env(:brando, __MODULE__, [])
    )
  end

  @doc "Whether a model and key are configured for the agent."
  @spec available?() :: boolean()
  def available?, do: match?({:ok, _}, Brando.AI.request(model_opts()))

  @doc "The `Brando.AI` options for the agent's model."
  @spec model_opts() :: keyword()
  def model_opts, do: if(model = config()[:model], do: [model: model], else: [])

  ## Conversations

  @doc "Start a conversation for `actor` in the current site/environment."
  @spec start_conversation(term(), keyword()) :: {:ok, Conversation.t()} | {:error, String.t()}
  def start_conversation(actor, opts \\ []) do
    Error.protect(fn ->
      Transfer.ensure_scope!(actor)

      Repo.insert!(%Conversation{
        scope: Transfer.scope(),
        actor_id: user_id(actor),
        title: opts[:title],
        language: to_string(opts[:language] || Brando.config(:default_language))
      })
    end)
  end

  @doc "A conversation of `actor`, or an error for anyone else's."
  @spec get_conversation(Ecto.UUID.t(), term()) :: {:ok, Conversation.t()} | {:error, String.t()}
  def get_conversation(id, actor), do: Error.protect(fn -> conversation!(id, actor) end)

  @doc "The actor's recent conversations in this site/environment."
  @spec list_conversations(term(), keyword()) :: [Conversation.t()]
  def list_conversations(actor, opts \\ []) do
    Repo.all(
      from(c in Conversation,
        where: c.scope == ^Transfer.scope() and c.actor_id == ^user_id(actor) and is_nil(c.archived_at),
        order_by: [desc: c.updated_at],
        limit: ^Keyword.get(opts, :limit, 20)
      )
    )
  end

  @doc "The conversation's messages, oldest first."
  @spec messages(Ecto.UUID.t(), term()) :: [Message.t()]
  def messages(conversation_id, actor) do
    %{id: id} = conversation!(conversation_id, actor)
    Repo.all(from(m in Message, where: m.conversation_id == ^id, order_by: [asc: m.inserted_at, asc: m.id]))
  end

  @doc "The conversation's latest run, if any."
  @spec latest_run(Ecto.UUID.t(), term()) :: Run.t() | nil
  def latest_run(conversation_id, actor) do
    %{id: id} = conversation!(conversation_id, actor)
    recover_stale_runs(id)
    Repo.one(from(r in Run, where: r.conversation_id == ^id, order_by: [desc: r.inserted_at], limit: 1))
  end

  @doc "Archive a conversation. Its proposals and receipts remain."
  @spec archive(Ecto.UUID.t(), term()) :: :ok | {:error, String.t()}
  def archive(id, actor) do
    with {:ok, _} <-
           Error.protect(fn ->
             id |> conversation!(actor) |> Changeset.change(archived_at: DateTime.utc_now()) |> Repo.update!()
           end),
         do: :ok
  end

  ## Attachments

  @doc """
  Attach a library image or video to the conversation and return its alias.

  Aliases (`image1`, `image2`, `video1` …) follow the order in which media is
  attached, so an upload that finishes early cannot take another's name.
  Attaching the same asset again returns its existing alias.
  """
  @spec attach(Ecto.UUID.t(), {:image | :video, integer()}, term()) :: {:ok, String.t()} | {:error, String.t()}
  def attach(conversation_id, {kind, id}, actor) when kind in [:image, :video] do
    Error.protect(fn ->
      {:ok, alias} = Repo.transaction(fn -> attach!(conversation_id, kind, id, actor) end)
      broadcast(conversation_id, {:attachments, alias})
      alias
    end)
  end

  defp attach!(conversation_id, kind, id, actor) do
    conversation = conversation!(conversation_id, actor, lock: true)
    asset = Dependencies.load!(to_string(kind), id, actor)
    attachments = conversation.attachments

    case Enum.find(attachments, &(&1["kind"] == to_string(kind) and &1["id"] == asset.id)) do
      %{"alias" => alias} ->
        alias

      nil ->
        alias = next_alias(attachments, kind, Enum.count(attachments, &(&1["kind"] == to_string(kind))) + 1)
        entry = %{"alias" => alias, "kind" => to_string(kind), "id" => asset.id, "label" => asset_label(asset)}
        conversation |> Changeset.change(attachments: attachments ++ [entry]) |> Repo.update!()
        alias
    end
  end

  @doc "Remove an attachment. Other aliases keep their names."
  @spec detach(Ecto.UUID.t(), String.t(), term()) :: :ok | {:error, String.t()}
  def detach(conversation_id, alias, actor) do
    with {:ok, _} <-
           Error.protect(fn ->
             conversation = conversation!(conversation_id, actor)
             attachments = Enum.reject(conversation.attachments, &(&1["alias"] == alias))
             conversation |> Changeset.change(attachments: attachments) |> Repo.update!()
           end) do
      broadcast(conversation_id, {:attachments, alias})
      :ok
    end
  end

  defp next_alias(attachments, kind, n) do
    alias = "#{kind}#{n}"
    if Enum.any?(attachments, &(&1["alias"] == alias)), do: next_alias(attachments, kind, n + 1), else: alias
  end

  defp asset_label(asset) do
    Enum.find_value([:title, :filename, :path, :source_url], fn key ->
      case Map.get(asset, key) do
        %{} = text -> text |> Map.values() |> Enum.find(&(&1 not in [nil, ""]))
        value when value not in [nil, ""] -> to_string(value)
        _ -> nil
      end
    end) || "##{asset.id}"
  end

  ## Runs

  @doc """
  Add a user message and start a run that answers it.

  The run executes in a supervised process; follow it with `subscribe/1`.
  `sync: true` runs it in the caller instead, for tests and scripts. Only one
  run per conversation at a time.
  """
  @spec send_message(Ecto.UUID.t(), String.t(), term(), keyword()) :: {:ok, Run.t()} | {:error, String.t()}
  def send_message(conversation_id, text, actor, opts \\ []) do
    text = String.trim(to_string(text))

    with {:ok, {run, message}} <- Error.protect(fn -> start_run!(conversation_id, text, actor) end) do
      broadcast(conversation_id, {:message, message})
      broadcast(conversation_id, {:run, run})
      execute(run, user_id(actor), opts[:sync])
    end
  end

  defp execute(run, user_id, true), do: {:ok, Loop.run(run.id, user_id)}

  defp execute(run, user_id, _sync) do
    work = Brando.Tenant.capture_context(fn -> Loop.run(run.id, user_id) end)
    {:ok, _pid} = Task.Supervisor.start_child(Brando.AI.Agent.Supervisor, work)
    {:ok, run}
  end

  defp start_run!(conversation_id, text, actor) do
    if text == "", do: Error.fail!(dgettext("ai_agent", "Write a message first."))

    unless available?(),
      do: Error.fail!(dgettext("ai_agent", "The assistant has no AI model configured for this site."))

    {:ok, result} =
      Repo.transaction(fn ->
        conversation = conversation!(conversation_id, actor, lock: true)
        recover_stale_runs(conversation.id)

        if Repo.one(
             from(r in Run,
               where: r.conversation_id == ^conversation.id and r.status == "running",
               select: true,
               limit: 1
             )
           ),
           do: Error.fail!(dgettext("ai_agent", "The assistant is still working on the previous message."))

        run = Repo.insert!(%Run{conversation_id: conversation.id, scope: conversation.scope, status: "running"})

        message =
          Repo.insert!(%Message{conversation_id: conversation.id, run_id: run.id, role: "user", content: text})

        conversation
        |> Changeset.change(title: conversation.title || String.slice(text, 0, 80))
        |> Changeset.force_change(:updated_at, DateTime.utc_now())
        |> Repo.update!()

        {run, message}
      end)

    result
  end

  @doc """
  Cancel the conversation's running run. It stops before its next model or
  tool call; charges for a call already in flight still apply.
  """
  @spec cancel(Ecto.UUID.t(), term()) :: :ok | {:error, String.t()}
  def cancel(conversation_id, actor) do
    with {:ok, _} <- Error.protect(fn -> conversation!(conversation_id, actor) end) do
      from(r in Run, where: r.conversation_id == ^conversation_id and r.status == "running")
      |> Repo.update_all(set: [status: "cancelled", finished_at: DateTime.utc_now(), reserved_tokens: 0])

      broadcast(conversation_id, {:progress, nil})
      :ok
    end
  end

  # A run whose process died with the node — a deploy, a crash — would block
  # the conversation forever. After ten quiet minutes it is interrupted.
  defp recover_stale_runs(conversation_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_after, :millisecond)

    from(r in Run, where: r.conversation_id == ^conversation_id and r.status == "running" and r.updated_at < ^cutoff)
    |> Repo.update_all(set: [status: "interrupted", finished_at: DateTime.utc_now(), reserved_tokens: 0])
  end

  ## Events

  @doc "Subscribe the caller to a conversation's events."
  @spec subscribe(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe(conversation_id), do: Phoenix.PubSub.subscribe(Brando.pubsub(), topic(conversation_id))

  @doc "Send `event` to the conversation's subscribers."
  @spec broadcast(Ecto.UUID.t(), term()) :: :ok | {:error, term()}
  def broadcast(conversation_id, event),
    do: Phoenix.PubSub.broadcast(Brando.pubsub(), topic(conversation_id), {:agent, conversation_id, event})

  defp topic(conversation_id), do: Brando.Tenant.Topic.scoped("brando:ai_agent:#{conversation_id}")

  ## Shared

  @doc "The actor's conversation `id`; raises for anyone else's. `lock: true` locks the row."
  @spec conversation!(Ecto.UUID.t(), term(), keyword()) :: Conversation.t()
  def conversation!(id, actor, opts \\ []) do
    query =
      from(c in Conversation,
        where: c.id == ^id and c.scope == ^Transfer.scope() and c.actor_id == ^user_id(actor)
      )

    query = if opts[:lock], do: from(c in query, lock: "FOR UPDATE"), else: query
    Repo.one(query) || Error.fail!(dgettext("ai_agent", "This conversation is not available."))
  rescue
    Ecto.Query.CastError -> Error.fail!(dgettext("ai_agent", "This conversation is not available."))
  end

  defp user_id(%{id: id}) when is_integer(id), do: id
  defp user_id(%Brando.Authorization.Scope{user_id: id}) when is_integer(id), do: id
  defp user_id(_), do: Error.fail!(dgettext("ai_agent", "The assistant requires an authenticated user."))
end
