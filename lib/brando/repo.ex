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

      # Shared schemas read `public` by design, joins included (a user's avatar)
      public_source?(source) ->
        Keyword.put(opts, :prefix, "public")

      prefix = Brando.Tenant.current_prefix() ->
        Keyword.put(opts, :prefix, prefix)

      true ->
        refuse_unscoped!(source)
        opts
    end
  end

  # With several sites, `public`'s copy of a site table is no site's content
  # (a tenant migration leaves it behind): reading it with no prefix would
  # show it to whoever has no site. A source that carries its own prefix, or
  # a shared table, is not refused, nor is work on `public` on purpose
  # (`Brando.Tenant.with_public/1`) or a migration Ecto is running.
  defp refuse_unscoped!(source) do
    if Brando.Tenant.outside_site?() and is_nil(Process.get(:ecto_migration)) do
      case tenant_tables(source) do
        [] -> :ok
        [table | _] -> raise Brando.Exception.MissingTenantError, table: table
      end
    end
  end

  # Every table the source reads: a query's own, its joins' (an association
  # join through the schema it starts from), its subqueries' wherever they
  # stand, and those of the queries it is combined with.
  defp tenant_tables(%Ecto.Changeset{data: data}), do: tenant_tables(data)
  defp tenant_tables(%Ecto.Query{prefix: prefix}) when is_binary(prefix), do: []

  defp tenant_tables(%Ecto.Query{from: from, joins: joins} = query) do
    {tables, _schemas} =
      Enum.reduce([from | joins], {[], []}, fn expr, {tables, schemas} ->
        source = expr_source(expr, schemas)
        {tables ++ expr_tables(expr, source), schemas ++ [source_schema(source)]}
      end)

    expressions =
      [query.select | Enum.map(joins, & &1.on)] ++
        query.wheres ++ query.havings ++ query.order_bys ++ query.group_bys ++ query.updates

    subqueries = for %{subqueries: subqueries} <- expressions, subquery <- subqueries, do: subquery
    combined = for {_kind, combined} <- query.combinations, do: combined

    tables ++ Enum.flat_map(subqueries ++ combined, &tenant_tables/1)
  end

  defp tenant_tables(%Ecto.SubQuery{query: query}), do: tenant_tables(query)
  defp tenant_tables(%{__meta__: %{prefix: prefix}}) when is_binary(prefix), do: []
  defp tenant_tables(%{__meta__: %{source: table}, __struct__: schema}), do: tenant_tables({table, schema})
  defp tenant_tables({table, nil}) when is_binary(table), do: tenant_tables(table)

  defp tenant_tables({table, schema}) when is_binary(table) and is_atom(schema),
    do: if(schema_prefix?(schema), do: [], else: tenant_tables(table))

  defp tenant_tables([first | _rest]), do: tenant_tables(first)

  defp tenant_tables(table) when is_binary(table),
    do: if(Brando.Tenant.SharedTables.member?(table), do: [], else: [table])

  defp tenant_tables(schema) when is_atom(schema) do
    if schema?(schema), do: tenant_tables({schema.__schema__(:source), schema}), else: []
  end

  defp tenant_tables(_source), do: []

  defp expr_source(%{source: nil, assoc: {parent, field}}, schemas) do
    with schema when not is_nil(schema) <- Enum.at(schemas, parent),
         %{related: related} <- schema.__schema__(:association, field) do
      {related.__schema__(:source), related}
    end
  end

  defp expr_source(%{source: source}, _schemas), do: source

  defp expr_tables(%{prefix: prefix}, _source) when is_binary(prefix), do: []
  defp expr_tables(_expr, source), do: tenant_tables(source)

  defp source_schema({_table, schema}) when is_atom(schema) and not is_nil(schema), do: schema
  defp source_schema(_source), do: nil

  defp schema?(schema), do: Code.ensure_loaded?(schema) and function_exported?(schema, :__schema__, 1)
  defp schema_prefix?(schema), do: schema?(schema) and is_binary(schema.__schema__(:prefix))

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
