defmodule Brando.JSONLD.Schema.Rating do
  @moduledoc """
  A review's rating. Google requires `ratingValue`; `bestRating` and
  `worstRating` are recommended when the scale isn't 1 to 5.

      Rating.build(4)
      Rating.build(%{rating_value: 8, best_rating: 10, worst_rating: 1})
  """

  @derive Jason.Encoder
  defstruct "@type": "Rating",
            ratingValue: nil,
            bestRating: nil,
            worstRating: nil

  @spec build(term()) :: %__MODULE__{} | nil
  def build(nil), do: nil
  def build(value) when is_number(value) or is_binary(value), do: %__MODULE__{ratingValue: value}
  def build(%Decimal{} = value), do: %__MODULE__{ratingValue: Decimal.to_float(value)}

  def build(data) when is_map(data) do
    %__MODULE__{
      ratingValue: get(data, [:rating_value, :value, :ratingValue]),
      bestRating: get(data, [:best_rating, :best, :bestRating]),
      worstRating: get(data, [:worst_rating, :worst, :worstRating])
    }
  end

  defp get(data, keys), do: Enum.find_value(keys, &Map.get(data, &1))
end
