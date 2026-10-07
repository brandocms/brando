defmodule Brando.JSONLD.Schema.AggregateRating do
  @moduledoc """
  The average of many ratings, on a product or a recipe. Google requires
  `ratingValue` and one of `ratingCount` or `reviewCount`.

      AggregateRating.build(%{rating_value: 4.4, review_count: 89})
  """

  @derive Jason.Encoder
  defstruct "@type": "AggregateRating",
            ratingValue: nil,
            ratingCount: nil,
            reviewCount: nil,
            bestRating: nil,
            worstRating: nil

  @spec build(map() | nil) :: %__MODULE__{} | nil
  def build(nil), do: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      ratingValue: get(data, [:rating_value, :value, :ratingValue]),
      ratingCount: get(data, [:rating_count, :ratingCount]),
      reviewCount: get(data, [:review_count, :reviewCount]),
      bestRating: get(data, [:best_rating, :best, :bestRating]),
      worstRating: get(data, [:worst_rating, :worst, :worstRating])
    }
  end

  defp get(data, keys), do: Enum.find_value(keys, &Map.get(data, &1))
end
