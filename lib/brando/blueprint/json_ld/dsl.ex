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
        type: :atom,
        required: true,
        doc: "Field type"
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
