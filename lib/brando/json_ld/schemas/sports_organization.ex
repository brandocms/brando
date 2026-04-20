defmodule Brando.JSONLD.Schema.SportsOrganization do
  @moduledoc """
  SportsOrganization schema
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "SportsOrganization",
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
            numberOfEmployees: nil,
            sport: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
