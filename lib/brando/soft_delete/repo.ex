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
    quote do
      def maybe_slug(%Ecto.Changeset{data: %{slug: slug}} = changeset) do
        changeset
        |> Ecto.Changeset.force_change(:slug, normalize_slug(slug))
        |> Brando.Utils.Schema.avoid_slug_collision()
      end

      def maybe_slug(%{slug: slug} = struct) do
        struct
        |> Ecto.Changeset.force_change(:slug, normalize_slug(slug))
        |> Brando.Utils.Schema.avoid_slug_collision()
      end

      def maybe_slug(changeset), do: changeset

      def randomize_slug(slug), do: "#{slug}$$$#{Brando.Utils.random_string(slug)}"

      def normalize_slug(slug) do
        case String.split(slug, "$$$") do
          [slug, _] -> slug
          [slug] -> slug
        end
      end

      def soft_delete_all(queryable) do
        update_all(queryable, set: [deleted_at: utc_now()])
      end

      def soft_delete(%Ecto.Changeset{data: %{slug: slug}} = changeset) do
        changeset
        |> Ecto.Changeset.change(slug: randomize_slug(slug))
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update()
      end

      def soft_delete(%{slug: slug} = struct) do
        struct
        |> Ecto.Changeset.change(slug: randomize_slug(slug))
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update()
      end

      def soft_delete(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update()
      end

      def soft_delete!(%Ecto.Changeset{data: %{slug: slug}} = changeset) do
        changeset
        |> Ecto.Changeset.change(slug: randomize_slug(slug))
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update!()
      end

      def soft_delete!(%{slug: slug} = struct) do
        struct
        |> Ecto.Changeset.change(slug: randomize_slug(slug))
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update!()
      end

      def soft_delete!(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: utc_now())
        |> update!()
      end

      def restore(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: nil)
        |> maybe_slug()
        |> update()
      end

      def restore!(struct_or_changeset) do
        struct_or_changeset
        |> Ecto.Changeset.change(deleted_at: nil)
        |> maybe_slug()
        |> update!()
      end

      defp utc_now do
        DateTime.truncate(DateTime.utc_now(), :second)
      end
    end
  end
end
