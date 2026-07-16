defmodule Brando.Blueprint.RuntimeRegressionTest do
  use ExUnit.Case, async: false

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

  test "changeset module and data schema must match" do
    assert_raise BlueprintError, ~r/module\/schema mismatch/, fn ->
      UniqueMessage.changeset(%CustomRelationCast{}, %{})
    end
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
