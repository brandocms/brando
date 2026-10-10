defmodule Brando.Repo do
  require Logger

  def repo do
    Application.get_env(:brando, :repo_module)
  end

  # In a sandboxed e2e server (`config :brando, :sql_sandbox_serial_preloads`),
  # Ecto's parallel preload Tasks are separate processes that escape the
  # per-test sandbox transaction in :auto mode and silently read stale data.
  # Forcing `in_parallel: false` keeps preload queries on the caller's
  # connection. No-op in dev/prod (flag unset).
  defp maybe_serialize_preloads(opts) do
    if Application.get_env(:brando, :sql_sandbox_serial_preloads) do
      Keyword.put_new(opts, :in_parallel, false)
    else
      opts
    end
  end

  def reload!(queryable, opts \\ []) do
    repo().reload!(queryable, put_prefix(opts, queryable))
  end

  def preload(struct, preloads, opts \\ []) do
    repo().preload(
      struct,
      preloads,
      opts |> maybe_serialize_preloads() |> put_prefix(struct)
    )
  end

  def all(queryable, opts \\ []) do
    repo().all(queryable, opts |> maybe_serialize_preloads() |> put_prefix(queryable))
  end

  def get(queryable, id, opts \\ []) do
    repo().get(queryable, id, opts |> maybe_serialize_preloads() |> put_prefix(queryable))
  end

  def get!(queryable, id, opts \\ []) do
    repo().get!(queryable, id, opts |> maybe_serialize_preloads() |> put_prefix(queryable))
  end

  def get_by(queryable, clauses, opts \\ []) do
    repo().get_by(
      queryable,
      clauses,
      opts |> maybe_serialize_preloads() |> put_prefix(queryable)
    )
  end

  def get_by!(queryable, clauses, opts \\ []) do
    repo().get_by!(
      queryable,
      clauses,
      opts |> maybe_serialize_preloads() |> put_prefix(queryable)
    )
  end

  def one(queryable, opts \\ []) do
    repo().one(queryable, opts |> maybe_serialize_preloads() |> put_prefix(queryable))
  end

  def aggregate(queryable, aggregate, opts \\ []) do
    repo().aggregate(queryable, aggregate, put_prefix(opts, queryable))
  end

  def one!(queryable, opts \\ []) do
    repo().one!(queryable, opts |> maybe_serialize_preloads() |> put_prefix(queryable))
  end

  def delete(struct_or_cs, opts \\ []) do
    repo().delete(struct_or_cs, put_prefix(opts, struct_or_cs))
  end

  def delete!(struct_or_cs, opts \\ []) do
    repo().delete!(struct_or_cs, put_prefix(opts, struct_or_cs))
  end

  def delete_all(queryable, opts \\ []) do
    repo().delete_all(queryable, put_prefix(opts, queryable))
  end

  def soft_delete(entry) do
    repo().soft_delete(entry)
  end

  def soft_delete!(entry) do
    repo().soft_delete!(entry)
  end

  def soft_delete_all(entry, opts \\ []) do
    repo().soft_delete_all(entry, put_prefix(opts, entry))
  end

  def restore(entry) do
    repo().restore(entry)
  end

  def restore!(entry) do
    repo().restore!(entry)
  end

  def insert(struct_or_cs, opts \\ []) do
    repo().insert(struct_or_cs, put_prefix(opts, struct_or_cs))
  end

  def insert!(struct_or_cs, opts \\ []) do
    repo().insert!(struct_or_cs, put_prefix(opts, struct_or_cs))
  end

  def insert_all(source, q, opts \\ []) do
    repo().insert_all(source, q, put_prefix(opts, source))
  end

  def update(cs, opts \\ []) do
    repo().update(cs, put_prefix(opts, cs))
  end

  def update!(cs, opts \\ []) do
    repo().update!(cs, put_prefix(opts, cs))
  end

  def update_all(queryable, updates, opts \\ []) do
    repo().update_all(queryable, updates, put_prefix(opts, queryable))
  end

  @after_commit :brando_repo_after_commit

  @doc """
  Runs `fun_or_multi` in a transaction, as `c:Ecto.Repo.transaction/2`.

  The outermost one also runs what `after_commit/1` held back during it,
  once it has committed, and drops it when it rolls back. Inside a
  transaction begun on the repo itself, `after_commit/1` cannot wait, and
  runs its work at once.
  """
  def transaction(fun_or_multi, opts \\ []) do
    # Inside another: only the outermost commits. One begun without this
    # function leaves after_commit/1 to run its work at once.
    if Process.get(@after_commit) || repo().in_transaction?() do
      repo().transaction(fun_or_multi, opts)
    else
      Process.put(@after_commit, [])

      {result, held} =
        try do
          result = repo().transaction(fun_or_multi, opts)
          {result, Process.get(@after_commit)}
        after
          Process.delete(@after_commit)
        end

      if elem(result, 0) == :ok, do: held |> Enum.reverse() |> Enum.each(&run_held/1)
      result
    end
  end

  @doc """
  Runs `fun` once the transaction around the caller has committed (one
  started with `transaction/2`), or at once outside one. Rolled back, it
  never runs.

  For what others must only learn of once it is true — a broadcast that
  sends them to read the database again, say.
  """
  @spec after_commit((-> any())) :: :ok
  def after_commit(fun) when is_function(fun, 0), do: hold(make_ref(), fun)

  @doc """
  Like `after_commit/1`, once per `key` in a transaction: work already held
  under `key` is not held again. For work that repeats for every write, such
  as evicting the same cache entries.
  """
  @spec after_commit(term(), (-> any())) :: :ok
  def after_commit(key, fun) when is_function(fun, 0), do: hold({:key, key}, fun)

  # The transaction has committed: work that fails is logged, and the rest
  # still runs, rather than skipped with the error raised to a caller whose
  # write is done.
  defp run_held({key, fun}) do
    fun.()
  rescue
    error -> log_held_failure(key, fun, Exception.format(:error, error, __STACKTRACE__))
  catch
    kind, reason -> log_held_failure(key, fun, Exception.format(kind, reason, __STACKTRACE__))
  end

  defp log_held_failure({:key, key}, _fun, message), do: log_held_failure(key, message)
  defp log_held_failure(_ref, fun, message), do: log_held_failure(fun, message)

  defp log_held_failure(work, message),
    do: Logger.error("[Brando.Repo] After-commit work #{inspect(work)} failed: " <> message)

  defp hold(key, fun) do
    case Process.get(@after_commit) do
      nil -> fun.()
      held -> unless List.keymember?(held, key, 0), do: Process.put(@after_commit, [{key, fun} | held])
    end

    :ok
  end

  def rollback(reason) do
    repo().rollback(reason)
  end

  def stream(queryable, opts \\ []) do
    repo().stream(queryable, put_prefix(opts, queryable))
  end

  defp put_prefix(opts, source) do
    cond do
      Keyword.has_key?(opts, :prefix) ->
        opts

      public_source?(source) ->
        Keyword.put(opts, :prefix, "public")

      prefix = Brando.Tenant.current_prefix() ->
        Keyword.put(opts, :prefix, prefix)

      true ->
        opts
    end
  end

  defp public_source?(%Ecto.Changeset{data: data}), do: public_source?(data)
  defp public_source?(%Ecto.Query{from: %{source: source}}), do: public_source?(source)
  defp public_source?(%Ecto.SubQuery{query: query}), do: public_source?(query)
  defp public_source?(%{__meta__: %{prefix: "public"}}), do: true
  defp public_source?(%{__struct__: schema}), do: public_schema?(schema)
  defp public_source?({_source, schema}) when is_atom(schema), do: public_schema?(schema)
  defp public_source?([first | _rest]), do: public_source?(first)
  defp public_source?(schema) when is_atom(schema), do: public_schema?(schema)
  defp public_source?(_source), do: false

  defp public_schema?(schema) do
    schema == Oban.Job or
      (Code.ensure_loaded?(schema) and function_exported?(schema, :__schema__, 1) and
         schema.__schema__(:prefix) == "public")
  end
end
