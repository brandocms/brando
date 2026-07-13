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
    repo().reload!(queryable, opts)
  end

  def preload(struct, preloads, opts \\ []) do
    repo().preload(struct, preloads, maybe_serialize_preloads(opts))
  end

  def all(queryable, opts \\ []) do
    repo().all(queryable, maybe_serialize_preloads(opts))
  end

  def get(queryable, id, opts \\ []) do
    repo().get(queryable, id, maybe_serialize_preloads(opts))
  end

  def get!(queryable, id, opts \\ []) do
    repo().get!(queryable, id, maybe_serialize_preloads(opts))
  end

  def one(queryable, opts \\ []) do
    repo().one(queryable, maybe_serialize_preloads(opts))
  end

  def one!(queryable, opts \\ []) do
    repo().one!(queryable, maybe_serialize_preloads(opts))
  end

  def delete(struct_or_cs, opts \\ []) do
    repo().delete(struct_or_cs, opts)
  end

  def delete!(struct_or_cs, opts \\ []) do
    repo().delete!(struct_or_cs, opts)
  end

  def delete_all(queryable, opts \\ []) do
    repo().delete_all(queryable, opts)
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
    repo().insert(struct_or_cs, opts)
  end

  def insert!(struct_or_cs, opts \\ []) do
    repo().insert!(struct_or_cs, opts)
  end

  def insert_all(source, q, opts \\ []) do
    repo().insert_all(source, q, opts)
  end

  def update(cs, opts \\ []) do
    repo().update(cs, opts)
  end

  def update!(cs, opts \\ []) do
    repo().update!(cs, opts)
  end

  def update_all(queryable, updates, opts \\ []) do
    repo().update_all(queryable, updates, opts)
  end

  def transaction(fun, opts \\ []) do
    repo().transaction(fun, opts)
  end

  def stream(queryable, opts \\ []) do
    repo().stream(queryable, opts)
  end
end
