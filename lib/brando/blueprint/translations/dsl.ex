defmodule Brando.Blueprint.Translations.Dsl do
  alias Brando.Blueprint.Translations

  @translate %Spark.Dsl.Entity{
    name: :translate,
    args: [:key, :value],
    target: Translations.Translation,
    schema: [
      key: [
        type: :atom,
        required: true,
        doc: "Translation key"
      ],
      value: [
        type: :string,
        required: true,
        doc: "Translation value"
      ]
    ]
  }

  @context %Spark.Dsl.Entity{
    name: :context,
    args: [:key],
    target: Translations.Context,
    entities: [translations: [@translate]],
    schema: [
      key: [
        type: :atom,
        required: true,
        doc: "Context key"
      ]
    ]
  }

  @root %Spark.Dsl.Section{
    name: :translations,
    entities: [@context],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: [Translations.Transformer]
end
