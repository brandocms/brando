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

  Work its count ended (the last step in, or closed with its steps in) is
  remembered for ten seconds, and a
  `resume/4` for its key in that time is dropped: one read before the last
  step reported can arrive after it, and would start the work again with
  nothing left to count it. A `start/4` forgets the end. A restarted node
  remembers no end, and resumes.
  """
  use GenServer

  alias BrandoAdmin.Work

  @table __MODULE__
  # How long an end by the count holds back a resume of its key
  @remember_end to_timeout(second: 10)

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
    if op == :start, do: :ets.delete(@table, {:ended, table_key})
    # It just ended: the resume was read before
    held_back? = op == :resume and is_nil(current) and ended?(table_key)

    case apply_op(op, current, table_key, attrs, at) do
      nil ->
        :ok

      _work when held_back? ->
        :ok

      # Nothing to show for: only the timeout starts again
      work when op == :touch ->
        store(table_key, work)

      work ->
        store_and_tell(table_key, work)
        remember_end(op, table_key, work)
    end

    {:noreply, state}
  end

  def handle_info({:forget_end, table_key, version}, state) do
    :ets.match_delete(@table, {{:ended, table_key}, version, :_})
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
    %{
      work
      | message: attrs.message || work.message,
        percent: attrs[:percent],
        total: join_total(work.total, attrs[:total]),
        open: Map.get(attrs, :open, work.open),
        done_message: attrs[:done_message] || work.done_message,
        failed_message: attrs[:failed_message] || work.failed_message,
        timeout: attrs[:timeout] || work.timeout,
        toast: attrs[:toast] || work.toast,
        updated_at: at
    }
  end

  def apply_op(:start, _ended_or_nil, key, attrs, at), do: new(key, attrs, at)

  # Running work keeps all but a larger total; other work starts again
  def apply_op(:resume, %Work{status: :running, total: total} = work, _key, attrs, at)
      when is_integer(total) and is_integer(attrs.total) and attrs.total > total,
      do: %{work | total: attrs.total, updated_at: at}

  def apply_op(:resume, %Work{status: :running}, _key, _attrs, _at), do: nil
  def apply_op(:resume, _ended_or_nil, key, attrs, at), do: new(key, attrs, at)

  def apply_op(:update, nil, key, attrs, at), do: new(key, attrs, at)

  def apply_op(:update, %Work{} = work, _key, attrs, at) do
    done = attrs[:done] || work.done

    %{
      work
      | message: attrs.message || work.message,
        percent: Map.get(attrs, :percent, work.percent),
        total: if(attrs[:remaining], do: done + attrs[:remaining], else: attrs[:total] || work.total),
        done: done,
        updated_at: at
    }
  end

  # Keeps running work from timing out; starts nothing
  def apply_op(:touch, %Work{status: :running} = work, _key, _attrs, at), do: %{work | updated_at: at}
  def apply_op(:touch, _work, _key, _attrs, _at), do: nil

  def apply_op(:advance, %Work{status: :running, total: total} = work, _key, %{result: result} = attrs, at)
      when is_integer(total) do
    work = %{work | done: work.done + 1, updated_at: at}

    work
    |> count_failed(result, attrs[:item])
    |> end_when_counted()
  end

  def apply_op(:advance, _work, _key, _attrs, _at), do: nil

  # No more steps: ends once the counted ones are in
  def apply_op(:close, %Work{status: :running} = work, _key, attrs, at) do
    end_when_counted(%{
      work
      | open: false,
        done_message: attrs[:done_message] || work.done_message,
        failed_message: attrs[:failed_message] || work.failed_message,
        updated_at: at
    })
  end

  def apply_op(:close, _work, _key, _attrs, _at), do: nil

  # Nothing running under the key: nothing to end (a job that ended its work
  # itself, then Oban giving it up)
  def apply_op(op, nil, _key, _attrs, _at) when op in [:finish, :fail], do: nil

  def apply_op(op, work, _key, attrs, at) when op in [:finish, :fail] do
    status = if op == :finish, do: :finished, else: :failed
    default = if op == :finish, do: work.done_message, else: work.failed_message
    %{work | status: status, message: attrs.message || default, percent: nil, updated_at: at}
  end

  # Enough of a failed step's items to name them, not a whole library's
  @max_failed_items 100

  defp count_failed(work, :ok, _item), do: work

  defp count_failed(work, :error, item) do
    items =
      if is_nil(item) or length(work.failed_items) >= @max_failed_items,
        do: work.failed_items,
        else: work.failed_items ++ [item]

    %{work | failed: work.failed + 1, failed_items: items}
  end

  defp end_when_counted(%Work{open: true} = work), do: work
  defp end_when_counted(%Work{total: total, done: done} = work) when not is_integer(total) or done < total, do: work

  defp end_when_counted(%Work{failed: failed} = work) when failed > 0,
    do: %{work | status: :failed, message: work.failed_message}

  defp end_when_counted(work), do: %{work | status: :finished, message: work.done_message}

  # A batch that starts while one runs joins its count
  defp join_total(current, more) when is_integer(current) and is_integer(more), do: current + more
  defp join_total(current, nil), do: current
  defp join_total(nil, more), do: more

  defp new({user_id, prefix, key}, attrs, at) do
    %Work{
      id: Work.id(prefix, key),
      key: key,
      prefix: prefix,
      user_id: user_id,
      message: attrs[:message],
      percent: attrs[:percent],
      total: attrs[:total] || attrs[:remaining],
      open: attrs[:open] || false,
      done: attrs[:done] || 0,
      failed: attrs[:failures] || 0,
      failed_items: Enum.take(attrs[:failed_items] || [], @max_failed_items),
      done_message: attrs[:done_message],
      failed_message: attrs[:failed_message],
      timeout: attrs[:timeout] || Work.default_timeout(),
      toast: attrs[:toast] || :auto,
      started_at: at,
      updated_at: at
    }
  end

  defp ended?(table_key), do: :ets.member(@table, {:ended, table_key})

  # Under a key `list/1` and `get/1` do not match
  defp remember_end(op, table_key, %Work{status: status}) when op in [:advance, :close] and status != :running do
    version = System.unique_integer([:monotonic])
    :ets.insert(@table, {{:ended, table_key}, version, nil})
    Process.send_after(self(), {:forget_end, table_key, version}, @remember_end)
  end

  defp remember_end(_op, _table_key, _work), do: :ok

  defp store(table_key, %Work{} = work) do
    if work.status == :running do
      version = System.unique_integer([:monotonic])
      :ets.insert(@table, {table_key, work, version})
      Process.send_after(self(), {:timeout, table_key, version}, work.timeout)
    else
      :ets.delete(@table, table_key)
    end
  end

  defp store_and_tell({user_id, _prefix, key} = table_key, %Work{} = work) do
    store(table_key, work)

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
