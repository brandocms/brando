defmodule Brando.JSONLD.Schema.Review do
  @moduledoc """
  A review of a thing, for Google's review snippets.

  Google requires `author`, `itemReviewed` and `reviewRating` with its
  `ratingValue`; `datePublished` is recommended. Inside a `Product` or a
  `Recipe` the item reviewed is the product or recipe, so it may be left out.

      json_ld_schema JSONLD.Schema.Review do
        field :name, :string, & &1.title
        field :author, :person, & &1.creator
        field :datePublished, :datetime, & &1.publish_at
        field :reviewBody, :string, & &1.summary
        field :reviewRating, JSONLD.Schema.Rating, &%{rating_value: &1.rating, best_rating: 6}
        field :itemReviewed, JSONLD.Schema.Thing, &%{type: "Book", name: &1.book_title}
        field :publisher, :identity
      end

  `build/1` makes a nested review, such as one of a product's, from a map
  with `:author` (a user, a People entry or a name), `:rating`,
  `:date_published`, `:body` and `:name`.

  https://developers.google.com/search/docs/appearance/structured-data/review-snippet
  """

  alias Brando.JSONLD.Schema.Rating

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Review",
            "@id": nil,
            name: nil,
            author: nil,
            datePublished: nil,
            reviewBody: nil,
            reviewRating: nil,
            itemReviewed: nil,
            publisher: nil,
            url: nil

  @spec build(map() | nil) :: %__MODULE__{} | nil
  def build(nil), do: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      name: Map.get(data, :name),
      author: data |> Map.get(:author) |> Brando.JSONLD.Author.build(),
      datePublished: data |> Map.get(:date_published) |> date(),
      reviewBody: Map.get(data, :body),
      reviewRating: data |> Map.get(:rating) |> Rating.build()
    }
  end

  defp date(%Date{} = date), do: Brando.JSONLD.to_date(date)
  defp date(%DateTime{} = datetime), do: Brando.JSONLD.to_datetime(datetime)
  defp date(%NaiveDateTime{} = datetime), do: Brando.JSONLD.to_datetime(datetime)
  defp date(value), do: value
end
