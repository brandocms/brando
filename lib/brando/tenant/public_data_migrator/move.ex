defmodule Brando.Tenant.PublicDataMigrator.Move do
  @moduledoc """
  Moves legacy public content into a tenant schema instead of copying it.

  `ALTER TABLE ... SET SCHEMA` is a catalog operation, so no table data is
  rewritten regardless of how large the installation is. Indexes, constraints,
  and column-owned sequences move with their table, which means foreign keys
  keep pointing at `public.users` by object identity and sequences arrive at
  their current values.

  Provisioning has already cloned an empty structure into the target, so the
  move happens in three parts:

    1. an empty template is built from `public` into a temporary schema;
    2. one transaction drops the target's cloned tables, moves the populated
       `public` tables in, and moves the template tables back into `public`;
    3. the temporary schema is dropped.

  Only step 2 mutates `public`, and it is a single transaction, so a failure
  leaves both schemas as they were. The copying migrator remains the default
  because this one leaves no legacy rows in `public` to roll back to.

  ## Requires `public` to be at the current schema version

  Dropping the target's cloned tables also discards any change a tenant
  migration made to them during provisioning, while the target's
  `schema_migrations` still records that migration as applied. The tables that
  arrive from `public` are therefore taken as-is and never re-migrated.

  That is safe as long as every structural change has reached `public`, which the
  design already requires of it as the structural template. A tenant migration
  whose change exists *only* in tenant schemas would be silently lost here — so
  apply structural changes to `public` too, and use tenant migrations to
  propagate them to environments that already exist.
  """

  @behaviour Brando.Tenant.PublicDataMigrator

  alias Brando.Environments.Schema
  alias Brando.Environments.StructureCloner.Postgres, as: StructureCloner
  alias Ecto.Adapters.SQL

  @impl true
  def migrate(source_prefix, target_prefix) do
    with {:ok, tables} <- StructureCloner.tenant_tables(source_prefix),
         :ok <- ensure_any(tables, source_prefix),
         {:ok, template} <- build_template(source_prefix) do
      case swap(source_prefix, target_prefix, template, tables) do
        :ok ->
          drop_template(template)
          :ok

        {:error, reason} ->
          drop_template(template)
          {:error, reason}
      end
    end
  end

  defp ensure_any([], source_prefix), do: {:error, {:no_tenant_tables, source_prefix}}
  defp ensure_any(_tables, _source_prefix), do: :ok

  defp build_template(source_prefix) do
    template = "tenant_template_#{System.unique_integer([:positive, :monotonic])}"

    with :ok <- Schema.create(template),
         :ok <- StructureCloner.clone_structure(source_prefix, template) do
      {:ok, template}
    else
      {:error, reason} ->
        drop_template(template)
        {:error, {:template_build_failed, reason}}
    end
  end

  defp swap(source_prefix, target_prefix, template, tables) do
    Brando.Repo.repo().transaction(fn ->
      Enum.each(tables, fn table ->
        # Drop the empty clone, move the populated table in, then restore an
        # empty table of the same name to keep `public` a usable template.
        execute!(~s|DROP TABLE IF EXISTS "#{target_prefix}"."#{table}" CASCADE|)
        execute!(~s|ALTER TABLE "#{source_prefix}"."#{table}" SET SCHEMA "#{target_prefix}"|)
        execute!(~s|ALTER TABLE "#{template}"."#{table}" SET SCHEMA "#{source_prefix}"|)
      end)
    end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, {:move_failed, reason}}
    end
  rescue
    exception -> {:error, {:move_failed, exception}}
  end

  defp execute!(sql), do: SQL.query!(Brando.Repo.repo(), sql, [])

  defp drop_template(template) do
    SQL.query(Brando.Repo.repo(), ~s|DROP SCHEMA IF EXISTS "#{template}" CASCADE|, [])
    :ok
  end
end
