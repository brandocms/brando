defmodule Brando.Blueprint.OptionCompatibilityTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.AssetOptions
  alias Brando.Blueprint.AttributeOptions
  alias Brando.Blueprint.Attributes
  alias Brando.Blueprint.Migrations.Schema, as: MigrationSchema
  alias Brando.Blueprint.RelationOptions
  alias Brando.Blueprint.Utils
  alias Brando.OptionCompatibility.AttributeMatrix

  @relation_types [:belongs_to, :embeds_many, :embeds_one, :entries, :has_many, :has_one, :many_to_many]
  @association_types [:belongs_to, :has_many, :has_one, :many_to_many]
  @has_types [:has_many, :has_one]
  @embed_types [:embeds_many, :embeds_one]

  @relation_option_scopes %{
    cast: @association_types,
    constraint_name: [:belongs_to],
    constraints: @relation_types,
    defaults: @association_types,
    defaults_to_struct: [:embeds_one],
    define_field: [:belongs_to],
    drop_param: [:embeds_many, :has_many],
    force_update_on_change: @relation_types -- [:many_to_many],
    foreign_key: [:belongs_to | @has_types],
    invalid_message: @relation_types,
    join_defaults: [:many_to_many],
    join_keys: [:many_to_many],
    join_through: [:many_to_many],
    join_where: [:many_to_many],
    load_in_query: @embed_types,
    module: @relation_types,
    null: [:belongs_to],
    on_delete: [:belongs_to, :has_many, :has_one, :many_to_many],
    on_replace: @association_types ++ @embed_types,
    preload_order: @has_types ++ [:many_to_many],
    primary_key: [:belongs_to],
    references: [:belongs_to | @has_types],
    required: @relation_types,
    required_message: @relation_types,
    sort_param: [:embeds_many, :has_many],
    source: [:belongs_to | @embed_types],
    through: @has_types,
    type: [:belongs_to],
    unique: [:belongs_to, :many_to_many],
    where: @association_types,
    with: [:belongs_to | @embed_types]
  }

  @attribute_destinations %{
    ecto_schema: [
      :autogenerate,
      :default,
      :embed_as,
      :load_in_query,
      :read_after_writes,
      :redact,
      :skip_default_validation,
      :source,
      :values,
      :virtual,
      :writable
    ],
    migration: [:default, :null, :precision, :rename_from, :scale, :source, :unique, :virtual],
    changeset: [:constraints, :required, :unique],
    transform: [:languages]
  }

  @relation_destinations %{
    ecto_schema: [
      :defaults,
      :defaults_to_struct,
      :define_field,
      :foreign_key,
      :join_defaults,
      :join_keys,
      :join_through,
      :join_where,
      :load_in_query,
      :on_delete,
      :on_replace,
      :preload_order,
      :primary_key,
      :references,
      :source,
      :through,
      :type,
      :unique,
      :where
    ],
    migration: [
      :constraint_name,
      :define_field,
      :foreign_key,
      :module,
      :null,
      :on_delete,
      :primary_key,
      :references,
      :source,
      :type,
      :unique
    ],
    changeset: [
      :drop_param,
      :force_update_on_change,
      :invalid_message,
      :required,
      :required_message,
      :sort_param,
      :with
    ],
    runtime: [:cast, :constraints, :module, :required, :unique]
  }

  @asset_option_scopes %{
    cfg: [:file, :gallery, :image, :video],
    force_update_on_change: [:gallery],
    invalid_message: [:gallery],
    module: [:file, :gallery, :image, :video],
    required: [:file, :gallery, :image, :video],
    required_message: [:gallery]
  }

  test "attribute option contract is exhaustive and every option has a destination" do
    assert AttributeOptions.known_options(:string) ==
             ~w(autogenerate constraints default load_in_query null precision read_after_writes redact rename_from required scale skip_default_validation source unique virtual writable)a

    assert AttributeOptions.known_options(:enum) ==
             ~w(autogenerate constraints default embed_as load_in_query null precision read_after_writes redact rename_from required scale skip_default_validation source unique values virtual writable)a

    assert AttributeOptions.known_options(:language) ==
             ~w(autogenerate constraints default embed_as languages load_in_query null precision read_after_writes redact rename_from required scale skip_default_validation source unique values virtual writable)a

    routed_options = @attribute_destinations |> Map.values() |> List.flatten() |> MapSet.new()

    assert routed_options == MapSet.new(AttributeOptions.known_options(:language))
  end

  test "attribute options reach Ecto, changeset, and migration boundaries without leaking" do
    schema = MigrationSchema.build(AttributeMatrix)
    columns = Map.new(schema.columns, &{&1.name, &1})
    attribute_opts = Attributes.__attribute_opts__(AttributeMatrix, :database_field)

    assert Map.take(attribute_opts, [:load_in_query, :read_after_writes, :redact, :source, :writable]) == %{
             load_in_query: false,
             read_after_writes: true,
             redact: true,
             source: :stored_field,
             writable: :never
           }

    assert AttributeMatrix.__schema__(:field_source, :database_field) == :stored_field
    refute :database_field in AttributeMatrix.__schema__(:query_fields)
    assert :database_field in AttributeMatrix.__schema__(:read_after_writes)
    assert :database_field in AttributeMatrix.__schema__(:redact_fields)
    assert :generated_id in AttributeMatrix.__schema__(:autogenerate_fields)
    assert :scratch in AttributeMatrix.__schema__(:virtual_fields)
    assert %AttributeMatrix{database_field: "protected", scratch: "scratch"} = struct(AttributeMatrix)

    {_updatable, not_updatable} = AttributeMatrix.__schema__(:updatable_fields)
    {_insertable, not_insertable} = AttributeMatrix.__schema__(:insertable_fields)
    assert :database_field in not_updatable
    assert :database_field in not_insertable

    assert columns.stored_field.opts == %{default: "protected"}
    assert columns.amount.opts == %{null: false, precision: 12, scale: 4}
    assert columns.renamed.rename_from == :legacy_name
    refute Map.has_key?(columns, :scratch)
    assert Enum.any?(schema.indexes, &(&1.fields == [:required_code] and &1.unique))

    refute schema
           |> MigrationSchema.persistable()
           |> Map.fetch!(:columns)
           |> Enum.any?(&Map.has_key?(&1, :rename_from))

    changeset = AttributeMatrix.changeset(%AttributeMatrix{}, %{"required_code" => "x"})
    refute changeset.valid?
    assert {_, [count: 2, validation: :length, kind: :min, type: :string]} = changeset.errors[:required_code]
    assert Enum.any?(changeset.constraints, &(&1.type == :unique and &1.field == :required_code))
  end

  test "relation option scopes are exhaustive and every accepted option has a destination" do
    assert RelationOptions.option_scopes() == @relation_option_scopes

    routed_options = @relation_destinations |> Map.values() |> List.flatten() |> MapSet.new()
    assert routed_options == MapSet.new(Map.keys(@relation_option_scopes))
  end

  test "relation options route only to Ecto schema and changeset consumers that accept them" do
    belongs_to_opts = %{
      cast: true,
      constraint_name: "owner_fkey",
      constraints: [required: true],
      defaults: [active: true],
      define_field: true,
      force_update_on_change: true,
      foreign_key: :owner_ref,
      invalid_message: "invalid owner",
      module: AttributeMatrix,
      null: false,
      on_delete: :restrict,
      on_replace: :update,
      primary_key: true,
      references: :id,
      required: true,
      required_message: "select an owner",
      source: :owner_column,
      type: :id,
      unique: true,
      where: [active: true],
      with: &Ecto.Changeset.change/2
    }

    assert Utils.to_ecto_opts(:belongs_to, belongs_to_opts) |> Map.new() == %{
             defaults: [active: true],
             define_field: true,
             foreign_key: :owner_ref,
             on_replace: :update,
             primary_key: true,
             references: :id,
             source: :owner_column,
             type: :id,
             where: [active: true]
           }

    assert Utils.to_changeset_opts(:belongs_to, belongs_to_opts) |> Map.new() == %{
             force_update_on_change: true,
             invalid_message: "invalid owner",
             required: true,
             required_message: "select an owner",
             with: &Ecto.Changeset.change/2
           }

    assert Utils.to_ecto_opts(:embeds_one, %{
             constraints: [required: true],
             defaults_to_struct: true,
             force_update_on_change: true,
             invalid_message: "invalid embed",
             load_in_query: false,
             module: AttributeMatrix,
             on_replace: :delete,
             required: true,
             required_message: "add an embed",
             source: :embed_payload,
             with: &Ecto.Changeset.change/2
           })
           |> Map.new() == %{
             defaults_to_struct: true,
             load_in_query: false,
             on_replace: :delete,
             source: :embed_payload
           }

    assert Utils.to_ecto_opts(:many_to_many, %{
             cast: true,
             defaults: [active: true],
             join_defaults: [featured: true],
             join_keys: [owner_id: :id, related_id: :id],
             join_through: AttributeMatrix,
             join_where: [featured: true],
             module: AttributeMatrix,
             on_delete: :delete_all,
             on_replace: :delete,
             preload_order: [asc: :id],
             required: true,
             unique: true,
             where: [active: true]
           })
           |> Map.new() == %{
             defaults: [active: true],
             join_defaults: [featured: true],
             join_keys: [owner_id: :id, related_id: :id],
             join_through: AttributeMatrix,
             join_where: [featured: true],
             on_delete: :delete_all,
             on_replace: :delete,
             preload_order: [asc: :id],
             unique: true,
             where: [active: true]
           }
  end

  test "asset option scopes are exhaustive and validated by asset type" do
    assert AssetOptions.option_scopes() == @asset_option_scopes

    assert :ok =
             AssetOptions.validate(%{
               type: :gallery,
               opts: %{
                 cfg: :default,
                 force_update_on_change: true,
                 invalid_message: "invalid gallery",
                 module: Brando.Galleries.Gallery,
                 required: true,
                 required_message: "select a gallery"
               }
             })

    assert {:error, message} =
             AssetOptions.validate(%{
               type: :image,
               opts: %{cfg: :default, module: Brando.Images.Image, required_message: "select an image"}
             })

    assert message =~ "unsupported options [:required_message]"
  end
end
