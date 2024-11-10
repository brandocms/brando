defmodule Brando.Blueprint.Relations.Dsl do
  alias Brando.Blueprint.Relations

  @valid_relations [
    :belongs_to,
    :has_one,
    :has_many,
    :embeds_one,
    :embeds_many,
    :many_to_many,
    :entries
  ]

  @relation %Spark.Dsl.Entity{
    name: :relation,
    identifier: :name,
    describe: """
    Declares a relation
    """,
    examples: [
      """
      relation :creator, :belongs_to, module: Brando.Users.User, required: true
      """
    ],
    args: [:name, :type, {:optional, :opts}],
    target: Relations.Relation,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Relation name"
      ],
      type: [
        type: {:in, @valid_relations},
        required: true,
        doc: "Relation type"
      ],
      opts: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Relation options"
      ]
    ],
    transform: {__MODULE__, :transform, []}
  }

  @root %Spark.Dsl.Section{
    name: :relations,
    entities: [@relation],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: [Brando.Blueprint.Relations.Transformer]

  def transform(relation) do
    {:ok, %{relation | opts: Enum.into(relation.opts, %{})}}
  end
end
