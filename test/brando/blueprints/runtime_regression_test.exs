defmodule Brando.Blueprint.RuntimeRegressionTest do
  use ExUnit.Case, async: false

  alias Brando.Blueprint
  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Attributes
  alias Brando.Blueprint.ChangesetParams
  alias Brando.Blueprint.Relations
  alias Brando.Exception.BlueprintError

  defmodule CustomRelationCast do
    use Brando.Blueprint,
      application: "Brando",
      domain: "BlueprintRuntimeRegression",
      schema: "CustomRelationCast",
      singular: "custom_relation_cast",
      plural: "custom_relation_casts",
      gettext_module: Brando.Gettext

    relations do
      relation :location, :belongs_to,
        module: Brando.BlueprintTest.P1.Location,
        cast: [with: {Brando.BlueprintTest.P1.Location, :changeset}]
    end
  end

  defmodule UniqueMessage do
    use Brando.Blueprint,
      application: "Brando",
      domain: "BlueprintRuntimeRegression",
      schema: "UniqueMessage",
      singular: "unique_message",
      plural: "unique_messages",
      gettext_module: Brando.Gettext

    attributes do
      attribute :title, :string, unique: [message: "must be unique"]
    end
  end

  defmodule CustomForeignKey do
    use Brando.Blueprint,
      application: "Brando",
      domain: "BlueprintRuntimeRegression",
      schema: "CustomForeignKey",
      singular: "custom_foreign_key",
      plural: "custom_foreign_keys",
      gettext_module: Brando.Gettext

    attributes do
      attribute :tenant_id, :integer
    end

    relations do
      relation :location, :belongs_to,
        module: Brando.BlueprintTest.P1.Location,
        foreign_key: :location_ref,
        constraint_name: "custom_location_ref_fkey",
        required: true,
        unique: [with: :tenant_id]
    end
  end

  defmodule InvalidTrait do
    use Brando.Trait

    @impl true
    def validate(_module, _opts), do: false
  end

  test "custom belongs_to cast callbacks receive the related struct and params" do
    changeset =
      CustomRelationCast.changeset(
        %CustomRelationCast{},
        %{"location" => %{"name" => "Oslo"}}
      )

    assert %Ecto.Changeset{changes: %{name: "Oslo"}} = changeset.changes.location
  end

  test "message-only unique options preserve the changeset" do
    changeset = UniqueMessage.changeset(%UniqueMessage{}, %{title: "Same"})

    assert %Ecto.Changeset{} = changeset

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.field == :title and constraint.error_message == "must be unique"
           end)
  end

  test "custom belongs_to foreign keys stay aligned across casting and constraints" do
    [relation] = Relations.__relations__(CustomForeignKey)

    assert Blueprint.get_relation_key(relation) == :location_ref
    assert Blueprint.get_castable_relation_fields([relation]) == [:location_ref]
    assert CustomForeignKey.__castable_relations__() == [:location_ref]
    assert CustomForeignKey.__required_relations__() == [:location_ref]

    changeset =
      CustomForeignKey.changeset(%CustomForeignKey{}, %{
        location_ref: 42,
        tenant_id: 7
      })

    assert changeset.changes.location_ref == 42
    assert changeset.changes.tenant_id == 7

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.type == :unique and constraint.field == :location_ref
           end)

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.type == :foreign_key and
               constraint.field == :location_ref and
               constraint.constraint == "custom_location_ref_fkey"
           end)

    required_changeset = CustomForeignKey.changeset(%CustomForeignKey{}, %{tenant_id: 7})
    assert {:location_ref, {"can't be blank", [validation: :required]}} in required_changeset.errors

    storage_schema = Brando.Blueprint.Migrations.Schema.build(CustomForeignKey)
    location_column = Enum.find(storage_schema.columns, &(&1.name == :location_ref))

    assert location_column.reference.name == "custom_location_ref_fkey"
    assert Enum.any?(storage_schema.indexes, &(&1.unique and &1.fields == [:location_ref, :tenant_id]))
  end

  test "changeset module and data schema must match" do
    assert_raise BlueprintError, ~r/module\/schema mismatch/, fn ->
      UniqueMessage.changeset(%CustomRelationCast{}, %{})
    end
  end

  test "the Blueprint changeset compatibility API delegates to the runtime runner" do
    attributes = Attributes.__attributes__(UniqueMessage)
    relations = Relations.__relations__(UniqueMessage)
    assets = Assets.__assets__(UniqueMessage)

    changeset_params = %ChangesetParams{
      module: UniqueMessage,
      schema: %UniqueMessage{},
      params: %{title: "Runtime boundary"},
      user: :system,
      sequence: nil,
      traits_before_validate_required: UniqueMessage.__traits_before_validate_required__(),
      traits_after_validate_required: UniqueMessage.__traits_after_validate_required__(),
      attributes: attributes,
      relations: relations,
      assets: assets,
      castable_fields:
        UniqueMessage.__required_attrs__() ++
          UniqueMessage.__optional_attrs__() ++
          UniqueMessage.__castable_relations__() ++ UniqueMessage.__castable_assets__(),
      required_castable_fields:
        UniqueMessage.__required_attrs__() ++
          UniqueMessage.__required_relations__() ++ UniqueMessage.__required_assets__(),
      opts: []
    }

    assert %{title: "Runtime boundary"} =
             changeset_params
             |> Blueprint.run_changeset()
             |> Ecto.Changeset.apply_changes()
  end

  test "generated block join constraints use the relation-specific table name" do
    join_schema = Brando.TraitTest.Project.BioBlocks
    expected_constraint = "#{join_schema.__schema__(:source)}_entry_id_block_id_index"

    changeset =
      join_schema.changeset(
        struct(join_schema),
        %{},
        :system
      )

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.constraint == expected_constraint
           end)
  end

  test "trait validation runs after Blueprint compilation" do
    module = Module.concat(__MODULE__, "InvalidTraitSchema#{System.unique_integer([:positive])}")

    quoted =
      quote do
        defmodule unquote(module) do
          use Brando.Blueprint,
            application: "Brando",
            domain: "BlueprintRuntimeRegression",
            schema: "InvalidTraitSchema",
            singular: "invalid_trait_schema",
            plural: "invalid_trait_schemas",
            gettext_module: Brando.Gettext

          trait unquote(InvalidTrait)
        end
      end

    assert_raise BlueprintError, ~r/returned invalid validation result false/, fn ->
      Code.compile_quoted(quoted)
    end
  end
end
