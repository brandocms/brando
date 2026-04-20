defmodule Brando.JSONLD.Schema.EmploymentAgency do
  @moduledoc """
  EmploymentAgency schema (subtype of LocalBusiness)
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "EmploymentAgency",
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
            openingHoursSpecification: nil,
            priceRange: nil,
            areaServed: nil,
            geo: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
