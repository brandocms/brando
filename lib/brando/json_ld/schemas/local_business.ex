defmodule Brando.JSONLD.Schema.LocalBusiness do
  @moduledoc """
  LocalBusiness schema
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "LocalBusiness",
            address: nil,
            alternateName: nil,
            description: nil,
            email: nil,
            telephone: nil,
            image: nil,
            logo: nil,
            name: nil,
            sameAs: nil,
            url: nil,
            openingHours: nil,
            priceRange: nil,
            areaServed: nil,
            geo: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
