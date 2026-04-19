defmodule Brando.JSONLD.Schema.IdentitySchema do
  @moduledoc """
  Shared builder for all identity-type JSON-LD schemas.

  Handles the common fields for Organization, Corporation,
  ProfessionalService, LocalBusiness, and Restaurant.
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @doc """
  Builds a keyword list of shared identity fields from cached Identity and SEO data.
  """
  def build_base({%Sites.Identity{} = identity, %Sites.SEO{} = seo}) do
    %{
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

  @doc """
  Extracts social media URLs from identity links.
  """
  def build_social_media(%{links: links}) when is_list(links) and links != [],
    do: Enum.map(links, & &1.url)

  def build_social_media(_), do: nil
end
