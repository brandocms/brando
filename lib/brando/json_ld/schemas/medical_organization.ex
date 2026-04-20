defmodule Brando.JSONLD.Schema.MedicalOrganization do
  @moduledoc """
  MedicalOrganization schema
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "MedicalOrganization",
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
            medicalSpecialty: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
