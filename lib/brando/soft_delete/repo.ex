defmodule Brando.SoftDelete.Repo do
  @moduledoc """
  Adds the soft deletion functionality to your repo
      defmodule Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Postgres
        use Brando.SoftDelete.Repo
      end
  """

  alias Ecto.Changeset

  @deleted_at_key {__MODULE__, :deleted_at}

  @doc """
  Soft deletes all entries matching the given query.
  """
  @callback soft_delete_all(queryable :: Ecto.Queryable.t(), opts :: keyword()) ::
              {integer, nil | [term]}

  @doc """
  Soft deletes a struct.
  """
  @callback soft_delete(struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Soft delete, raises on error
  """
  @callback soft_delete!(struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t()) ::
              Ecto.Schema.t()

  @doc """
  Restores struct. Its freed fields come back free of collisions, a draft's
  too unless `draft_address: :keep` (`restore_changeset/2`). A row restored
  or gone since it was read is an error on `deleted_at`.
  """
  @callback restore(struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(), opts :: keyword()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Restores struct, raises on error
  """
  @callback restore!(struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t(), opts :: keyword()) ::
              Ecto.Schema.t()

  defmacro __using__(_opts) do
    quote location: :keep do
      defdelegate maybe_obfuscate(struct_or_changeset), to: Brando.SoftDelete.Repo
      defdelegate randomize_field(field), to: Brando.SoftDelete.Repo
      defdelegate normalize_field(field), to: Brando.SoftDelete.Repo

      def soft_delete_all(queryable, opts \\ []) do
        update_all(queryable, [set: [deleted_at: Brando.SoftDelete.Repo.utc_now()]], opts)
      end

      def soft_delete(struct_or_changeset) do
        struct_or_changeset
        |> Brando.SoftDelete.Repo.soft_delete_changeset()
        |> update()
        |> maybe_delete_identifier()
        |> Brando.Cache.Query.evict()
      end

      def soft_delete!(struct_or_changeset) do
        struct_or_changeset
        |> Brando.SoftDelete.Repo.soft_delete_slug_changeset()
        |> update!()
        |> maybe_delete_identifier()
        |> Brando.Cache.Query.evict()
      end

      def restore(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> Brando.SoftDelete.Repo.restore_changeset(opts)
        |> update(stale_error_field: :deleted_at)
        |> maybe_create_identifier()
        |> Brando.Cache.Query.evict()
      end

      def restore!(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> Brando.SoftDelete.Repo.restore_changeset(opts)
        |> update!()
        |> maybe_create_identifier()
        |> Brando.Cache.Query.evict()
      end

      def maybe_create_identifier({:ok, entry}) do
        module = entry.__struct__
        Brando.Content.create_identifier(module, entry)
        {:ok, entry}
      end

      def maybe_create_identifier(other), do: other

      defp maybe_delete_identifier({:ok, entry}) when is_map(entry) do
        Brando.Content.delete_identifier(entry.__struct__, entry)
        {:ok, entry}
      end

      defp maybe_delete_identifier({:error, entry}), do: {:error, entry}

      defp maybe_delete_identifier(entry) when is_map(entry) do
        Brando.Content.delete_identifier(entry.__struct__, entry)
        entry
      end

      defp maybe_delete_identifier(other), do: other
    end
  end

  @functions [soft_delete: 1, soft_delete!: 1, soft_delete_all: 2, restore: 1, restore!: 1]

  @doc """
  Whether `repo` has the functions `use Brando.SoftDelete.Repo` adds, which
  every soft delete and restore calls (`Brando.Repo.soft_delete/1` and the
  rest).
  """
  @spec used_by?(module()) :: boolean()
  def used_by?(repo) do
    is_atom(repo) and Code.ensure_loaded?(repo) and
      Enum.all?(@functions, fn {function, arity} -> function_exported?(repo, function, arity) end)
  end

  @doc """
  What is wrong with a `repo` without Brando's soft-delete functions, and
  the line that adds them.
  """
  @spec missing_message(module()) :: String.t()
  def missing_message(repo) do
    """
    #{inspect(repo)} lacks Brando's soft-delete functions (soft_delete/1, restore/1 and the rest), \
    so nothing can be deleted or restored.

    Add this line to #{inspect(repo)}, after `use Ecto.Repo`:

        use Brando.SoftDelete.Repo
    """
  end

  @doc """
  Returns `repo` when it has Brando's soft-delete functions, and raises
  `Brando.Exception.ConfigError` with `missing_message/1` when it does not.
  """
  @spec ensure_used!(module()) :: module()
  def ensure_used!(repo) do
    if used_by?(repo), do: repo, else: raise(Brando.Exception.ConfigError, message: missing_message(repo))
  end

  # The changesets are built here rather than in the `__using__` quote, so the
  # Repo only carries the database calls.

  @doc "Restores the obfuscated fields of a soft-deleted entry to their original values."
  def maybe_obfuscate(%Changeset{data: data} = changeset), do: restore_obfuscated(changeset, data, [])

  def maybe_obfuscate(%{} = struct), do: struct |> Changeset.change() |> restore_obfuscated(struct, [])

  def maybe_obfuscate(changeset), do: changeset

  @doc "Appends a random suffix, freeing a unique value while its entry is deleted."
  def randomize_field(field), do: "#{field}$$$#{Brando.Utils.random_string(field)}"

  @doc "Removes the suffix `randomize_field/1` added."
  def normalize_field(field) do
    case String.split(field, "$$$") do
      [field, _] -> field
      [field] -> field
    end
  end

  @doc """
  Marks an entry deleted and randomizes its obfuscated fields. A struct's fields
  also avoid colliding with another entry's; a changeset's are taken as they are.
  """
  def soft_delete_changeset(%Changeset{data: data} = changeset) do
    changeset
    |> randomize_obfuscated(data)
    |> Changeset.change(deleted_at: utc_now())
  end

  def soft_delete_changeset(%{} = struct) do
    struct
    |> Changeset.change()
    |> obfuscate(struct, &randomize_field/1)
    |> Changeset.change(deleted_at: utc_now())
  end

  def soft_delete_changeset(struct_or_changeset), do: Changeset.change(struct_or_changeset, deleted_at: utc_now())

  @doc "Marks an entry deleted and randomizes its slug."
  def soft_delete_slug_changeset(%Changeset{data: %{slug: slug}} = changeset),
    do: changeset |> Changeset.change(slug: randomize_field(slug)) |> Changeset.change(deleted_at: utc_now())

  def soft_delete_slug_changeset(%{slug: slug} = struct),
    do: struct |> Changeset.change(slug: randomize_field(slug)) |> Changeset.change(deleted_at: utc_now())

  def soft_delete_slug_changeset(struct_or_changeset), do: Changeset.change(struct_or_changeset, deleted_at: utc_now())

  @doc """
  Clears an entry's deletion and restores its obfuscated fields, each to its
  value before the trash or, when another entry holds that now, to the first
  free of `value-1` … in the scope a save of the type checks
  (`Brando.Blueprint.Unique.avoid_collisions/4`). A draft is given a free
  value too, unless `draft_address: :keep`.

  The update applies only while the row holds the `deleted_at` it was read
  with: a row restored, trashed again or gone since is stale.
  """
  def restore_changeset(struct_or_changeset, opts \\ []) do
    %Changeset{data: data} = changeset = Changeset.change(struct_or_changeset)

    changeset
    |> clear_deleted_at()
    |> restore_obfuscated(data, opts)
  end

  # The lock only filters the update: its change applies in `prepare_changes`, which an update without changes skips
  defp clear_deleted_at(%Changeset{data: %{deleted_at: deleted_at}} = changeset) when not is_nil(deleted_at) do
    changeset
    |> Changeset.optimistic_lock(:deleted_at, fn _deleted_at -> nil end)
    |> Changeset.change(deleted_at: nil)
  end

  defp clear_deleted_at(changeset), do: Changeset.change(changeset, deleted_at: nil)

  @doc """
  The deletion timestamp, truncated to seconds: now, or the one `at/2` holds
  for this process.
  """
  def utc_now, do: Process.get(@deleted_at_key) || DateTime.truncate(DateTime.utc_now(), :second)

  @doc """
  Runs `fun` with every soft delete in this process stamped `deleted_at`, so
  entries trashed together share it, as a restore finds them
  (`Brando.Translations.delete_with_translations/4`).
  """
  def at(%DateTime{} = deleted_at, fun) do
    previous = Process.put(@deleted_at_key, deleted_at)

    try do
      fun.()
    after
      if previous, do: Process.put(@deleted_at_key, previous), else: Process.delete(@deleted_at_key)
    end
  end

  defp obfuscate(changeset, source, transform) do
    fields = obfuscated_fields(source)

    changeset
    |> force_obfuscated(source, fields, transform)
    |> Brando.Utils.Schema.avoid_field_collision(fields)
  end

  defp restore_obfuscated(changeset, %{__struct__: module} = source, opts) do
    fields = obfuscated_fields(source)
    drafts? = Keyword.get(opts, :draft_address, :free) == :free

    changeset
    |> force_obfuscated(source, fields, &normalize_field/1)
    |> Brando.Blueprint.Unique.avoid_collisions(module, fields, drafts: drafts?)
  end

  defp randomize_obfuscated(changeset, source),
    do: force_obfuscated(changeset, source, obfuscated_fields(source), &randomize_field/1)

  defp force_obfuscated(changeset, source, fields, transform) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      Changeset.force_change(changeset, field, transform.(Map.get(source, field)))
    end)
  end

  defp obfuscated_fields(%{__struct__: module}),
    do: Keyword.get(module.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, [])
end
