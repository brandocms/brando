defmodule BrandoAdmin.Work.Registry do
  @moduledoc """
  Remembers the admin users' running `BrandoAdmin.Work`, so a screen opened
  halfway, or a new tab, shows it still running.

  Every report is broadcast on PubSub. Each node's registry applies it to
  its own ETS table and then tells the LiveViews (`{:work, key, status,
  work}` on the user's topic) and the user channel (`"work"`) on that node.
  So each node knows all the work in a cluster, nothing is pushed twice, and
  each node times work out by itself, alike.

  Work leaves the table when it finishes, fails or times out. The table is
  lost with the node: running work started before a restart reappears with
  its next report, as `update/4` starts work it does not know.
  """
  use GenServer

  alias BrandoAdmin.Work

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The work under `{user_id, prefix, key}`, or nil."
  def get(table_key) do
    case :ets.lookup(@table, table_key) do
      [{_key, work, _version}] -> work
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "The user's running work, oldest first."
  def list(user_id) do
    @table
    |> :ets.match_object({{user_id, :_, :_}, :_, :_})
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.started_at, DateTime)
  rescue
    ArgumentError -> []
  end

  @doc "Returns once every report broadcast before the call is applied. For tests."
  def sync, do: GenServer.call(__MODULE__, :sync)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    :ok = Phoenix.PubSub.subscribe(Brando.pubsub(), Work.topic())
    {:ok, nil}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:brando_work, {op, table_key, attrs, at}}, state) do
    current = get(table_key)

    case apply_op(op, current, table_key, attrs, at) do
      nil -> :ok
      work -> store_and_tell(table_key, work)
    end

    {:noreply, state}
  end

  def handle_info({:timeout, table_key, version}, state) do
    case :ets.lookup(@table, table_key) do
      [{_key, %Work{status: :running} = work, ^version}] ->
        store_and_tell(table_key, %{work | status: :failed, timed_out: true, message: nil, updated_at: DateTime.utc_now()})

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc false
  # The new state of the work, or nil when the report changes nothing.
  def apply_op(:start, %Work{status: :running} = work, _key, attrs, at) do
    # A batch that starts while one runs joins its count
    total =
      case {work.total, attrs[:total]} do
        {current, more} when is_integer(current) and is_integer(more) -> current + more
        {current, nil} -> current
        {nil, more} -> more
      end

    %{
      work
      | message: attrs.message || work.message,
        percent: attrs[:percent],
        total: total,
        done_message: attrs[:done_message] || work.done_message,
        failed_message: attrs[:failed_message] || work.failed_message,
        timeout: attrs[:timeout] || work.timeout,
        toast: attrs[:toast] || work.toast,
        updated_at: at
    }
  end

  def apply_op(:start, _ended_or_nil, key, attrs, at), do: new(key, attrs, at)

  def apply_op(:update, nil, key, attrs, at), do: new(key, attrs, at)

  def apply_op(:update, %Work{} = work, _key, attrs, at) do
    %{
      work
      | message: attrs.message || work.message,
        percent: Map.get(attrs, :percent, work.percent),
        total: attrs[:total] || work.total,
        done: attrs[:done] || work.done,
        updated_at: at
    }
  end

  def apply_op(:advance, %Work{status: :running, total: total} = work, _key, %{result: result}, at)
      when is_integer(total) do
    work = %{work | done: work.done + 1, failed: work.failed + if(result == :error, do: 1, else: 0), updated_at: at}

    cond do
      work.done < total -> work
      work.failed > 0 -> %{work | status: :failed, message: work.failed_message}
      true -> %{work | status: :finished, message: work.done_message}
    end
  end

  def apply_op(:advance, _work, _key, _attrs, _at), do: nil

  def apply_op(op, work, key, attrs, at) when op in [:finish, :fail] do
    work = work || new(key, %{}, at)
    status = if op == :finish, do: :finished, else: :failed
    default = if op == :finish, do: work.done_message, else: work.failed_message
    %{work | status: status, message: attrs.message || default, percent: nil, updated_at: at}
  end

  defp new({user_id, prefix, key}, attrs, at) do
    %Work{
      id: Work.id(prefix, key),
      key: key,
      prefix: prefix,
      user_id: user_id,
      message: attrs[:message],
      percent: attrs[:percent],
      total: attrs[:total],
      done: attrs[:done] || 0,
      done_message: attrs[:done_message],
      failed_message: attrs[:failed_message],
      timeout: attrs[:timeout] || Work.default_timeout(),
      toast: attrs[:toast] || :auto,
      started_at: at,
      updated_at: at
    }
  end

  defp store_and_tell({user_id, _prefix, key} = table_key, %Work{} = work) do
    if work.status == :running do
      version = System.unique_integer([:monotonic])
      :ets.insert(@table, {table_key, work, version})
      Process.send_after(self(), {:timeout, table_key, version}, work.timeout)
    else
      :ets.delete(@table, table_key)
    end

    Phoenix.PubSub.local_broadcast(Brando.pubsub(), Work.user_topic(user_id), {:work, key, work.status, work})
    push(user_id, work)
  end

  defp push(user_id, work) do
    Brando.endpoint().local_broadcast("user:#{user_id}", "work", Work.to_payload(work))
  rescue
    # No endpoint running (a task, a test without one)
    _ -> :ok
  catch
    _kind, _reason -> :ok
  end
end
