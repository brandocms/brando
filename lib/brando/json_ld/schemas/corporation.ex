defmodule Brando.JSONLD.Schema.Corporation do
  @moduledoc """
  Corporation schema
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "Corporation",
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
            tickerSymbol: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
