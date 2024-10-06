defmodule Brando.Blueprint.Meta.Dsl do
  alias Brando.Blueprint.Meta

  @meta_field %Spark.Dsl.Entity{
    name: :field,
    args: [:targets, :value_fn],
    target: Meta.MetaField,
    schema: [
      targets: [
        type: {:or, [:string, {:list, :string}]},
        required: true,
        doc: "Target field name(s)"
      ],
      value_fn: [
        type: {:fun, 1},
        required: true,
        doc: "Mutator function"
      ]
    ]
  }

  @meta_schema %Spark.Dsl.Entity{
    name: :meta_schema,
    entities: [fields: [@meta_field]],
    target: Meta.MetaSchema,
    schema: []
  }

  @root %Spark.Dsl.Section{
    name: :meta_schemas,
    entities: [@meta_schema],
    top_level?: true
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: []
end
