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
  Restores struct
  """
  @callback restore(struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t()) ::
              {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Restores struct, raises on error
  """
  @callback restore!(struct_or_changeset :: Ecto.Schema.t() | Ecto.Changeset.t()) ::
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

      def restore(struct_or_changeset) do
        struct_or_changeset
        |> Brando.SoftDelete.Repo.restore_changeset()
        |> update()
        |> maybe_create_identifier()
        |> Brando.Cache.Query.evict()
      end

      def restore!(struct_or_changeset) do
        struct_or_changeset
        |> Brando.SoftDelete.Repo.restore_changeset()
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

  # The changesets are built here rather than in the `__using__` quote, so the
  # Repo only carries the database calls.

  @doc "Restores the obfuscated fields of a soft-deleted entry to their original values."
  def maybe_obfuscate(%Changeset{data: data} = changeset), do: obfuscate(changeset, data, &normalize_field/1)

  def maybe_obfuscate(%{} = struct), do: struct |> Changeset.change() |> obfuscate(struct, &normalize_field/1)

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

  @doc "Clears an entry's deletion and restores its obfuscated fields."
  def restore_changeset(struct_or_changeset),
    do: struct_or_changeset |> Changeset.change(deleted_at: nil) |> maybe_obfuscate()

  @doc "The deletion timestamp, truncated to seconds."
  def utc_now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp obfuscate(changeset, source, transform) do
    fields = obfuscated_fields(source)

    changeset
    |> force_obfuscated(source, fields, transform)
    |> Brando.Utils.Schema.avoid_field_collision(fields)
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
