defmodule Brando.Blueprint.Datasources.Dsl do
  alias Brando.Blueprint.Datasources

  @datasource %Spark.Dsl.Entity{
    name: :datasource,
    args: [:key],
    target: Datasources.Datasource,
    schema: [
      key: [
        type: :atom,
        required: true,
        doc: "Datasource key"
      ],
      type: [
        type: {:in, [:single, :list, :selection]},
        required: true,
        doc: "Datasource type"
      ],
      list: [
        type: {:mfa_or_fun, 3},
        required: false,
        doc:
          "Function to retrieve all entries. Receives `module`, `language`, `vars`. Return as identifiers"
      ],
      get: [
        type: {:fun, 1},
        required: false,
        doc: "Function to retrieve selected entries from identifiers."
      ]
    ]
  }

  @root %Spark.Dsl.Section{
    name: :datasources,
    entities: [
      @datasource
    ],
    imports: [
      Brando.Datasource
    ],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: []
end
