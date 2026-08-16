defmodule Brando.Repo do
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

  def transaction(fun, opts \\ []) do
    repo().transaction(fun, opts)
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
