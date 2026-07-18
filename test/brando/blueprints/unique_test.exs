defmodule Brando.Blueprint.UniqueTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Migrations.Schema, as: MigrationSchema
  alias Brando.Blueprint.Unique
  alias Brando.Blueprint.UniqueFields

  defmodule ConstraintSchema do
    use Brando.Blueprint,
      application: "Brando",
      domain: "BlueprintUnique",
      schema: "Constraint",
      singular: "constraint",
      plural: "constraints",
      gettext_module: Brando.Gettext

    table "unique_contracts"

    attributes do
      attribute :tenant_id, :integer
      attribute :locale, :string
      attribute :plain, :string, unique: true
      attribute :custom_message, :string, unique: [message: "plain duplicate"]
      attribute :collision_plain, :string, unique: [prevent_collision: true]
      attribute :collision_atom, :string, unique: [prevent_collision: :tenant_id]

      attribute :collision_list, :string, unique: [prevent_collision: [:tenant_id, :locale]]

      attribute :atom_scoped, :string, unique: [with: :tenant_id, message: "tenant duplicate"]

      attribute :list_scoped, :string, unique: [with: [:tenant_id, :locale]]

      attribute :callback_scoped, :string,
        unique: [
          prevent_collision: fn _changeset -> __MODULE__ end,
          with: [:tenant_id, :locale],
          message: "callback duplicate"
        ]
    end

    relations do
      relation :location, :belongs_to,
        module: Brando.BlueprintTest.P1.Location,
        unique: true

      relation :owner, :belongs_to,
        module: Brando.BlueprintTest.P1.Location,
        foreign_key: :owner_ref,
        unique: [with: :tenant_id, message: "owner duplicate"]

      relation :reviewer, :belongs_to,
        module: Brando.BlueprintTest.P1.Location,
        foreign_key: :reviewer_ref,
        unique: [with: [:tenant_id, :locale]]
    end
  end

  test "runtime constraints and migration indexes share fields, names, and messages" do
    changeset = ConstraintSchema.changeset(%ConstraintSchema{}, %{})
    storage_schema = MigrationSchema.build(ConstraintSchema)

    unique_indexes = Enum.filter(storage_schema.indexes, & &1.unique)
    unique_constraints = Enum.filter(changeset.constraints, &(&1.type == :unique))
    constraint_names = MapSet.new(unique_constraints, & &1.constraint)
    index_names = MapSet.new(unique_indexes, & &1.name)

    assert constraint_names == index_names

    assert MapSet.new(unique_indexes, & &1.fields) ==
             MapSet.new([
               [:plain],
               [:custom_message],
               [:collision_plain],
               [:collision_atom, :tenant_id],
               [:collision_list, :tenant_id, :locale],
               [:atom_scoped, :tenant_id],
               [:list_scoped, :tenant_id, :locale],
               [:callback_scoped, :tenant_id, :locale],
               [:location_id],
               [:owner_ref, :tenant_id],
               [:reviewer_ref, :tenant_id, :locale]
             ])

    constraints_by_name = Map.new(unique_constraints, &{&1.constraint, &1})

    assert constraints_by_name["unique_contracts_custom_message_index"].error_message == "plain duplicate"
    assert constraints_by_name["unique_contracts_atom_scoped_tenant_id_index"].error_message == "tenant duplicate"

    assert constraints_by_name["unique_contracts_callback_scoped_tenant_id_locale_index"].error_message ==
             "callback duplicate"

    assert constraints_by_name["unique_contracts_owner_ref_tenant_id_index"].error_message == "owner duplicate"
  end

  test "field normalization distinguishes collision controls from persisted scopes" do
    assert UniqueFields.fields(:slug, true) == [:slug]
    assert UniqueFields.fields(:slug, false) == [:slug]
    assert UniqueFields.fields(:slug, message: "duplicate") == [:slug]
    assert UniqueFields.fields(:slug, prevent_collision: true) == [:slug]
    assert UniqueFields.fields(:slug, prevent_collision: :language) == [:slug, :language]

    assert UniqueFields.fields(:slug, prevent_collision: [:language, :tenant_id]) ==
             [:slug, :language, :tenant_id]

    assert UniqueFields.fields(:slug,
             prevent_collision: fn _changeset -> ConstraintSchema end,
             with: [:language, :tenant_id]
           ) == [:slug, :language, :tenant_id]
  end

  test "a callback is not invoked when a persisted scope is nil" do
    callback = fn _changeset ->
      send(self(), :collision_callback_invoked)
      ConstraintSchema
    end

    attribute = %{
      name: :callback_scoped,
      opts: %{unique: [prevent_collision: callback, with: [:tenant_id, :locale]]}
    }

    changeset =
      %ConstraintSchema{}
      |> Ecto.Changeset.change(%{callback_scoped: "available", tenant_id: nil, locale: "en"})
      |> Unique.run_unique_attribute_constraints(ConstraintSchema, [attribute])

    refute_received :collision_callback_invoked

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.type == :unique and
               constraint.constraint == "unique_contracts_callback_scoped_tenant_id_locale_index"
           end)
  end
end
