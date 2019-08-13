defmodule Brando.JSONLD.Schema.ExhibitionEvent do
  @moduledoc """
  Organization schema
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@type": "ExhibitionEvent",
            startDate: nil,
            endDate: nil,
            location: nil,
            image: nil,
            description: nil,
            artist: nil

  # def build(%Sites.Organization{} = organization) do
  #   %__MODULE__{
  #     "@id": Path.join(organization.url, "#identity"),
  #     address: Schemas.PostalAddress.build(organization),
  #     alternateName: organization.alternate_name,
  #     description: organization.description,
  #     email: organization.email,
  #     image: Schemas.ImageObject.build(organization.image),
  #     logo: Schemas.ImageObject.build(organization.logo),
  #     name: organization.name,
  #     sameAs: build_social_media(organization),
  #     url: organization.url
  #   }
  # end
end
