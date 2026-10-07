defmodule Brando.JSONLD.Schema.Product do
  @moduledoc """
  A product, for Google's product snippets and merchant listings.

  Google requires `name` and at least one of `offers`, `review` or
  `aggregateRating`; `image`, `description` and `sku` are recommended. An
  offer needs `price` and `priceCurrency` (see `Brando.JSONLD.Schema.Offer`).

      json_ld_schema JSONLD.Schema.Product do
        field :name, :string, & &1.title
        field :description, :string, & &1.meta_description
        field :image, :image, & &1.cover
        field :sku, :string, & &1.sku
        field :offers, JSONLD.Schema.Offer, &%{price: &1.price, price_currency: "NOK", availability: :in_stock}
        field :aggregateRating, JSONLD.Schema.AggregateRating, &%{rating_value: &1.rating, review_count: &1.reviews}
        field :url, :current_url
      end

  https://developers.google.com/search/docs/appearance/structured-data/product-snippet
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Product",
            "@id": nil,
            name: nil,
            description: nil,
            image: nil,
            sku: nil,
            url: nil,
            offers: nil,
            aggregateRating: nil,
            review: nil
end
