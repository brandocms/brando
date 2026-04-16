defmodule Brando.JSONLD.Schema.ProfessionalService do
  @moduledoc """
  ProfessionalService schema
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@id": "https://default/#identity",
            "@type": "ProfessionalService",
            address: nil,
            alternateName: nil,
            description: nil,
            email: nil,
            telephone: nil,
            image: nil,
            logo: nil,
            name: nil,
            sameAs: nil,
            url: nil

  def build({%Sites.Identity{} = identity, %Sites.SEO{} = seo}) do
    %__MODULE__{
      "@id": Path.join(Brando.Utils.hostname(), "#identity"),
      address: Schema.PostalAddress.build(identity),
      alternateName: identity.alternate_name,
      description: seo.fallback_meta_description,
      email: identity.email,
      telephone: identity.phone,
      image: Schema.ImageObject.build(seo.fallback_meta_image),
      logo: Schema.ImageObject.build(identity.logo),
      name: identity.name,
      sameAs: build_social_media(identity),
      url: seo.base_url
    }
  end

  def build_social_media(%{links: links}) when is_list(links) and links != [],
    do: Enum.map(links, & &1.url)

  def build_social_media(_), do: nil
end
