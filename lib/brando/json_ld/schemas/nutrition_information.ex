defmodule Brando.JSONLD.Schema.NutritionInformation do
  @moduledoc """
  A recipe's nutrition per serving. Google reads `calories` (recommended) and
  the other amounts when given, as text with a unit (`"270 calories"`,
  `"12 g"`).

      field :nutrition, JSONLD.Schema.NutritionInformation, &%{calories: "\#{&1.calories} calories"}
  """

  @derive Jason.Encoder
  defstruct "@type": "NutritionInformation",
            calories: nil,
            servingSize: nil,
            carbohydrateContent: nil,
            fatContent: nil,
            fiberContent: nil,
            proteinContent: nil,
            sodiumContent: nil,
            sugarContent: nil

  @spec build(map() | nil) :: %__MODULE__{} | nil
  def build(nil), do: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      calories: Map.get(data, :calories),
      servingSize: Map.get(data, :serving_size),
      carbohydrateContent: Map.get(data, :carbohydrate_content),
      fatContent: Map.get(data, :fat_content),
      fiberContent: Map.get(data, :fiber_content),
      proteinContent: Map.get(data, :protein_content),
      sodiumContent: Map.get(data, :sodium_content),
      sugarContent: Map.get(data, :sugar_content)
    }
  end
end
