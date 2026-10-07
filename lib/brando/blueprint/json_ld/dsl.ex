defmodule Brando.Blueprint.JSONLD.Dsl do
  alias Brando.Blueprint.JSONLD

  @json_ld_field %Spark.Dsl.Entity{
    name: :field,
    args: [:name, :type, {:optional, :value_fn, nil}],
    target: JSONLD.JSONLDField,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Field name"
      ],
      type: [
        type: {:or, [:atom, {:tuple, [:atom, :atom]}]},
        required: true,
        doc:
          "Field type. Atom for simple types (`:person` maps users and People entries to `Person` nodes) " <>
            "or {:list, SchemaModule} for lists."
      ],
      value_fn: [
        type: {:or, [nil, {:fun, 1}]},
        required: false,
        doc: "Mutator function"
      ]
    ]
  }

  @json_ld_schema %Spark.Dsl.Entity{
    name: :json_ld_schema,
    identifier: :schema,
    args: [:schema],
    entities: [fields: [@json_ld_field]],
    target: JSONLD.JSONLDSchema,
    schema: [
      schema: [
        type: :atom,
        required: true,
        doc: "Schema to JSONLD"
      ],
      videos: [
        type: :boolean,
        default: true,
        doc:
          "Describe the videos the entry shows (its video fields and preloaded video blocks) " <>
            "as `VideoObject`s linked from `video`, on schemas with a `video` property."
      ]
    ]
  }

  @root %Spark.Dsl.Section{
    name: :json_ld_schemas,
    entities: [@json_ld_schema],
    top_level?: true
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: []
end
