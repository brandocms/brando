defmodule Brando.JSONLD.Schema.Organization do
  @moduledoc """
  Organization schema
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@id": "https://default/#identity",
            "@type": "Organization",
            address: nil,
            alternateName: nil,
            description: nil,
            email: nil,
            image: nil,
            logo: nil,
            name: nil,
            sameAs: nil,
            url: nil

  def build({%Sites.Identity{} = organization, %Sites.SEO{} = seo}) do
    %__MODULE__{
      "@id": Path.join(Brando.Utils.hostname(), "#identity"),
      address: Schema.PostalAddress.build(organization),
      alternateName: organization.alternate_name,
      description: seo.fallback_meta_description,
      email: organization.email,
      image: Schema.ImageObject.build(seo.fallback_meta_image),
      logo: Schema.ImageObject.build(organization.logo),
      name: organization.name,
      sameAs: build_social_media(organization),
      url: seo.base_url
    }
  end

  def build_social_media(%{links: links}) when length(links) > 0, do: Enum.map(links, & &1.url)
  def build_social_media(_), do: nil
end
