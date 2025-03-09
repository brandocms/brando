defmodule Brando.Blueprint.Attributes.Dsl do
  alias Brando.Blueprint.Attributes

  @valid_attributes [
    :array,
    :boolean,
    :date,
    :datetime,
    :enum,
    :naive_datetime,
    :decimal,
    :file,
    :float,
    :i18n_string,
    :id,
    :integer,
    :language,
    :map,
    :slug,
    :status,
    :string,
    :text,
    :time,
    :timestamp,
    :uuid
  ]

  @valid_array_attributes [
    :map,
    :id,
    :integer,
    :string,
    :enum,
    Ecto.Enum
  ]

  @attribute %Spark.Dsl.Entity{
    name: :attribute,
    identifier: :name,
    describe: """
    Declares an attribute
    """,
    examples: [
      """
      attribute :name, :string, required: true
      """
    ],
    args: [:name, :type, {:optional, :opts}],
    target: Attributes.Attribute,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Attribute name"
      ],
      type: [
        type:
          {:or,
           [
             {:in, @valid_attributes},
             {:tuple, [{:in, [:array]}, {:in, @valid_array_attributes}]},
             :module
           ]},
        required: true,
        doc: "Attribute type"
      ],
      opts: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Attribute options"
      ]
    ],
    modules: [:opts],
    transform: {__MODULE__, :transform, []}
  }

  @root %Spark.Dsl.Section{
    name: :attributes,
    entities: [@attribute],
    top_level?: false
  }

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: [@root],
    transformers: [Brando.Blueprint.Attributes.Transformer]

  def transform(%{type: :language} = attr) do
    default_languages =
      case Keyword.get(attr.opts, :languages) do
        nil ->
          Brando.config(:languages) ||
            [
              [value: "en", text: "English"],
              [value: "no", text: "Norsk"]
            ]

        supplied_langs ->
          supplied_langs
      end

    languages =
      Enum.map(default_languages, fn [value: lang_code, text: _] -> String.to_atom(lang_code) end)

    new_opts =
      attr.opts
      |> Keyword.put(:values, languages)
      |> Keyword.put(:required, true)

    {:ok, %{attr | opts: Enum.into(new_opts, %{})}}
  end

  def transform(attr) do
    {:ok, %{attr | opts: Enum.into(attr.opts, %{})}}
  end
end
