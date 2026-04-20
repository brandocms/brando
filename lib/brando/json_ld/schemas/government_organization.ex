defmodule Brando.JSONLD.Schema.GovernmentOrganization do
  @moduledoc """
  GovernmentOrganization schema
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "GovernmentOrganization",
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
            numberOfEmployees: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
