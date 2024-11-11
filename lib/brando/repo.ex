defmodule Brando.Repo do
  def repo do
    Application.get_env(:brando, :repo_module)
  end

  def preload(struct, preloads, opts \\ []) do
    repo().preload(struct, preloads, opts)
  end

  def all(queryable, opts \\ []) do
    repo().all(queryable, opts)
  end

  def get(queryable, id, opts \\ []) do
    repo().get(queryable, id, opts)
  end

  def get!(queryable, id, opts \\ []) do
    repo().get!(queryable, id, opts)
  end

  def one(queryable, opts \\ []) do
    repo().one(queryable, opts)
  end

  def one!(queryable, opts \\ []) do
    repo().one!(queryable, opts)
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
