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
    repo().reload!(queryable, put_prefix(opts))
  end

  def preload(struct, preloads, opts \\ []) do
    repo().preload(struct, preloads, opts |> maybe_serialize_preloads() |> put_prefix())
  end

  def all(queryable, opts \\ []) do
    repo().all(queryable, opts |> maybe_serialize_preloads() |> put_prefix())
  end

  def get(queryable, id, opts \\ []) do
    repo().get(queryable, id, opts |> maybe_serialize_preloads() |> put_prefix())
  end

  def get!(queryable, id, opts \\ []) do
    repo().get!(queryable, id, opts |> maybe_serialize_preloads() |> put_prefix())
  end

  def one(queryable, opts \\ []) do
    repo().one(queryable, opts |> maybe_serialize_preloads() |> put_prefix())
  end

  def aggregate(queryable, aggregate, opts \\ []) do
    repo().aggregate(queryable, aggregate, put_prefix(opts))
  end

  def one!(queryable, opts \\ []) do
    repo().one!(queryable, opts |> maybe_serialize_preloads() |> put_prefix())
  end

  def delete(struct_or_cs, opts \\ []) do
    repo().delete(struct_or_cs, put_prefix(opts))
  end

  def delete!(struct_or_cs, opts \\ []) do
    repo().delete!(struct_or_cs, put_prefix(opts))
  end

  def delete_all(queryable, opts \\ []) do
    repo().delete_all(queryable, put_prefix(opts))
  end

  def soft_delete(entry) do
    repo().soft_delete(entry)
  end

  def soft_delete!(entry) do
    repo().soft_delete!(entry)
  end

  def soft_delete_all(entry) do
    repo().soft_delete_all(entry)
  end

  def restore(entry) do
    repo().restore(entry)
  end

  def restore!(entry) do
    repo().restore!(entry)
  end

  def insert(struct_or_cs, opts \\ []) do
    repo().insert(struct_or_cs, put_prefix(opts))
  end

  def insert!(struct_or_cs, opts \\ []) do
    repo().insert!(struct_or_cs, put_prefix(opts))
  end

  def insert_all(source, q, opts \\ []) do
    repo().insert_all(source, q, put_prefix(opts))
  end

  def update(cs, opts \\ []) do
    repo().update(cs, put_prefix(opts))
  end

  def update!(cs, opts \\ []) do
    repo().update!(cs, put_prefix(opts))
  end

  def update_all(queryable, updates, opts \\ []) do
    repo().update_all(queryable, updates, put_prefix(opts))
  end

  def transaction(fun, opts \\ []) do
    repo().transaction(fun, opts)
  end

  def rollback(reason) do
    repo().rollback(reason)
  end

  def stream(queryable, opts \\ []) do
    repo().stream(queryable, put_prefix(opts))
  end

  defp put_prefix(opts) do
    case Brando.Tenant.current_prefix() do
      nil -> opts
      prefix -> Keyword.put_new(opts, :prefix, prefix)
    end
  end
end
