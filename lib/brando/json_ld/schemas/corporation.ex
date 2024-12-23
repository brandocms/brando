defmodule Brando.JSONLD.Schema.Corporation do
  @moduledoc """
  Corporation schema
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
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
            url: nil

  def build({%Sites.Identity{} = corporation, %Sites.SEO{} = seo}) do
    %__MODULE__{
      "@id": Path.join(Brando.Utils.hostname(), "#identity"),
      address: Schema.PostalAddress.build(corporation),
      alternateName: corporation.alternate_name,
      description: seo.fallback_meta_description,
      email: corporation.email,
      telephone: corporation.phone,
      image: Schema.ImageObject.build(seo.fallback_meta_image),
      logo: Schema.ImageObject.build(corporation.logo),
      name: corporation.name,
      sameAs: build_social_media(corporation),
      url: seo.base_url
    }
  end

  def build_social_media(%{links: links}) when length(links) > 0, do: Enum.map(links, & &1.url)
  def build_social_media(_), do: nil
end
