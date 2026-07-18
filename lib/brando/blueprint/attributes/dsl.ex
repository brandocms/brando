defmodule Brando.Blueprint.Attributes.Dsl do
  alias Brando.Blueprint.Attributes
  alias Brando.RuntimeConfig

  @valid_attributes [
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
    transformers: [Brando.Blueprint.Attributes.Transformer, Brando.Blueprint.SemanticValidator]

  def transform(%{type: :language} = attr) do
    default_languages =
      case Keyword.get(attr.opts, :languages) do
        nil ->
          RuntimeConfig.get(:languages) ||
            [
              [value: "en", text: "English"],
              [value: "no", text: "Norsk"]
            ]

        supplied_langs ->
          supplied_langs
      end

    case normalize_languages(default_languages) do
      {:ok, languages} ->
        new_opts =
          attr.opts
          |> Keyword.put(:values, languages)
          |> Keyword.put(:required, true)

        {:ok, %{attr | opts: Enum.into(new_opts, %{})}}

      :error ->
        {:error, "language attribute `:languages` must be a list of `[value: \"code\", text: \"Label\"]` options"}
    end
  end

  def transform(attr) do
    {:ok, %{attr | opts: Enum.into(attr.opts, %{})}}
  end

  defp normalize_languages(languages) when is_list(languages) do
    Enum.reduce_while(languages, {:ok, []}, fn language, {:ok, normalized} ->
      with true <- Keyword.keyword?(language),
           {:ok, code} when is_binary(code) and code != "" <- Keyword.fetch(language, :value),
           {:ok, label} when is_binary(label) and label != "" <- Keyword.fetch(language, :text) do
        {:cont, {:ok, [String.to_atom(code) | normalized]}}
      else
        _invalid -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end

  defp normalize_languages(_languages), do: :error
end
