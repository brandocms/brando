defmodule Brando.JSONLD.Schema.Architect do
  @moduledoc """
  Architect schema (subtype of ProfessionalService)
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "Architect",
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
            foundingDate: nil,
            areaServed: nil,
            knowsAbout: nil,
            # LocalBusiness subtype: Google recommends these for the local pack.
            openingHoursSpecification: nil,
            priceRange: nil,
            geo: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
