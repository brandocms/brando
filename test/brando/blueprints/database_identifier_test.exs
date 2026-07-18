defmodule Brando.Blueprint.DatabaseIdentifierTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.Blueprint.Migrations.Schema, as: MigrationSchema
  alias Brando.Factory
  alias Brando.MigrationTest.LongIdentifiers

  @table "blueprint_runtime_constraint_records"
  @unique_fields [:uniqueness_value, :tenant_reference_identifier]
  @foreign_key :owner_reference_identifier_id
  @full_unique_name "#{@table}_#{Enum.join(@unique_fields, "_")}_index"
  @full_foreign_key_name "#{@table}_#{@foreign_key}_fkey"

  setup do
    query!(~s(DROP TABLE IF EXISTS "#{@table}"))

    query!("""
    CREATE TABLE "#{@table}" (
      id bigserial PRIMARY KEY,
      uniqueness_value varchar(255),
      tenant_reference_identifier bigint,
      owner_reference_identifier_id bigint,
      inserted_at timestamp(0) without time zone,
      updated_at timestamp(0) without time zone,
      CONSTRAINT "#{@full_foreign_key_name}"
        FOREIGN KEY (owner_reference_identifier_id) REFERENCES users(id)
    )
    """)

    query!("""
    CREATE UNIQUE INDEX "#{@full_unique_name}"
      ON "#{@table}" (uniqueness_value, tenant_reference_identifier)
    """)

    on_exit(fn -> query!(~s(DROP TABLE IF EXISTS "#{@table}")) end)

    :ok
  end

  test "normalizes ASCII and UTF-8 identifiers to PostgreSQL's byte limit" do
    assert DatabaseIdentifier.normalize("short_name") == "short_name"
    assert DatabaseIdentifier.normalize(:atom_name) == "atom_name"

    ascii_identifier = String.duplicate("a", 70)
    assert DatabaseIdentifier.normalize(ascii_identifier) == String.duplicate("a", 63)

    utf8_identifier = String.duplicate("a", 62) <> "ørest"
    normalized_utf8 = DatabaseIdentifier.normalize(utf8_identifier)

    assert normalized_utf8 == String.duplicate("a", 62)
    assert byte_size(normalized_utf8) <= 63
    assert String.valid?(normalized_utf8)
  end

  test "migration and runtime names share PostgreSQL's stored identifiers" do
    storage_schema = MigrationSchema.build(LongIdentifiers)
    unique_index = Enum.find(storage_schema.indexes, & &1.unique)
    owner_column = Enum.find(storage_schema.columns, &(&1.name == @foreign_key))

    changeset = LongIdentifiers.changeset(%LongIdentifiers{}, %{})

    assert unique_index.name == DatabaseIdentifier.normalize(@full_unique_name)
    assert owner_column.reference.name == DatabaseIdentifier.normalize(@full_foreign_key_name)
    assert byte_size(unique_index.name) == 63
    assert byte_size(owner_column.reference.name) == 63

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.type == :unique and constraint.constraint == unique_index.name
           end)

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.type == :foreign_key and constraint.constraint == owner_column.reference.name
           end)
  end

  test "overlong unique violations return a changeset error" do
    user = Factory.insert(:random_user)
    stored_constraint_name = DatabaseIdentifier.normalize(@full_unique_name)

    params = %{
      uniqueness_value: "shared-value",
      tenant_reference_identifier: 42,
      owner_reference_identifier_id: user.id
    }

    assert {:ok, _record} = %LongIdentifiers{} |> LongIdentifiers.changeset(params) |> Repo.insert()

    assert {:error, changeset} =
             %LongIdentifiers{}
             |> LongIdentifiers.changeset(params)
             |> Repo.insert()

    assert {"has already been used for this tenant", [constraint: :unique, constraint_name: ^stored_constraint_name]} =
             Keyword.fetch!(changeset.errors, :uniqueness_value)
  end

  test "overlong foreign-key violations return a changeset error" do
    stored_constraint_name = DatabaseIdentifier.normalize(@full_foreign_key_name)

    params = %{
      uniqueness_value: "invalid-owner",
      tenant_reference_identifier: 99,
      owner_reference_identifier_id: -1
    }

    assert {:error, changeset} =
             %LongIdentifiers{}
             |> LongIdentifiers.changeset(params)
             |> Repo.insert()

    assert {"does not exist", [constraint: :foreign, constraint_name: ^stored_constraint_name]} =
             Keyword.fetch!(changeset.errors, @foreign_key)
  end

  defp query!(statement), do: Ecto.Adapters.SQL.query!(Repo, statement, [])
end
