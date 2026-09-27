defmodule Brando.JSONLD.Schema.IdentityPerson do
  @moduledoc """
  The site identity as a schema.org Person — a site about one person: an
  artist, a writer, a freelancer.

  `jobTitle` and `hasOccupation` say what they do; `additionalType` can point
  at a more specific type schema.org doesn't have, such as Wikidata's
  "visual artist" (https://www.wikidata.org/wiki/Q3391743). `sameAs` lists
  their profiles elsewhere (the identity's links).
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "Person",
            additionalType: nil,
            address: nil,
            alternateName: nil,
            description: nil,
            email: nil,
            hasOccupation: nil,
            image: nil,
            jobTitle: nil,
            knowsAbout: nil,
            name: nil,
            sameAs: nil,
            telephone: nil,
            url: nil

  def build(args) do
    struct(__MODULE__, Brando.JSONLD.Schema.IdentitySchema.build_base(args))
  end
end
