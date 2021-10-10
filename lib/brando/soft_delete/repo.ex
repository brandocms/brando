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

  @doc """
  Soft deletes all entries matching the given query.
  """
  @callback soft_delete_all(queryable :: Ecto.Queryable.t()) :: {integer, nil | [term]}

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
      def maybe_obfuscate(%Ecto.Changeset{data: data} = changeset) do
        module = changeset.data.__struct__

        obfuscated_fields =
          Keyword.get(module.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, [])

        obfuscated_fields
        |> Enum.reduce(changeset, fn obfuscated_field, new_changeset ->
          Ecto.Changeset.force_change(
            new_changeset,
            obfuscated_field,
            normalize_field(Map.get(data, obfuscated_field))
          )
        end)
        |> Brando.Utils.Schema.avoid_field_collision(obfuscated_fields)
      end

      def maybe_obfuscate(%{} = struct) do
        module = struct.__struct__

        obfuscated_fields =
          Keyword.get(module.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, [])

        changeset = Ecto.Changeset.change(struct)

        obfuscated_fields
        |> Enum.reduce(changeset, fn obfuscated_field, new_changeset ->
          Ecto.Changeset.force_change(
            new_changeset,
            obfuscated_field,
            normalize_field(Map.get(struct, obfuscated_field))
          )
        end)
        |> Brando.Utils.Schema.avoid_field_collision(obfuscated_fields)
      end

      def maybe_obfuscate(changeset), do: changeset

      def randomize_field(field), do: "#{field}$$$#{Brando.Utils.random_string(field)}"

      def normalize_field(field) do
        case String.split(field, "$$$") do
          [field, _] -> field
          [field] -> field
        end
      end

      def soft_delete_all(queryable) do
        update_all(queryable, set: [deleted_at: utc_now()])
      end

      def soft_delete(%Ecto.Changeset{data: data} = changeset) do
        module = changeset.data.__struct__

        obfuscated_fields =
          Keyword.get(module.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, [])

        obfuscated_fields
        |> Enum.reduce(changeset, fn obfuscated_field, new_changeset ->
          Ecto.Changeset.force_change(
            new_changeset,
            obfuscated_field,
            randomize_field(Map.get(data, obfuscated_field))
          )
        end)
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update()
        |> Brando.Cache.Query.evict()
      end

      def soft_delete(%{} = struct) do
        module = struct.__struct__

        obfuscated_fields =
          Keyword.get(module.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, [])

        changeset = Ecto.Changeset.change(struct)

        obfuscated_fields
        |> Enum.reduce(changeset, fn obfuscated_field, new_changeset ->
          Ecto.Changeset.force_change(
            new_changeset,
            obfuscated_field,
            randomize_field(Map.get(struct, obfuscated_field))
          )
        end)
        |> Brando.Utils.Schema.avoid_field_collision(obfuscated_fields)
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update()
        |> Brando.Cache.Query.evict()
      end

      def soft_delete(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update()
        |> Brando.Cache.Query.evict()
      end

      def soft_delete!(%Ecto.Changeset{data: %{slug: slug}} = changeset) do
        changeset
        |> Ecto.Changeset.change(slug: randomize_field(slug))
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update!()
        |> Brando.Cache.Query.evict()
      end

      def soft_delete!(%{slug: slug} = struct) do
        struct
        |> Ecto.Changeset.change(slug: randomize_field(slug))
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update!()
        |> Brando.Cache.Query.evict()
      end

      def soft_delete!(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update!()
        |> Brando.Cache.Query.evict()
      end

      def restore(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: nil)
        |> maybe_obfuscate()
        |> update()
        |> Brando.Cache.Query.evict()
      end

      def restore!(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: nil)
        |> maybe_obfuscate()
        |> update!()
        |> Brando.Cache.Query.evict()
      end

      defp utc_now, do: DateTime.truncate(DateTime.utc_now(), :second)
    end
  end
end
