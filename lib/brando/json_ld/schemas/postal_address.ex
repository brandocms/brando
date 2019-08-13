defmodule Brando.JSONLD.Schema.PostalAddress do
  @moduledoc """
  PostalAddress schema
  """

  @derive Jason.Encoder
  defstruct "@type": "PostalAddress",
            addressCountry: nil,
            addressLocality: nil,
            addressRegion: nil,
            postalCode: nil

  def build(organization) do
    %__MODULE__{
      addressCountry: organization.country || nil,
      addressLocality: organization.city || nil,
      addressRegion: organization.city || nil,
      postalCode: organization.zipcode || nil
    }
  end
end
