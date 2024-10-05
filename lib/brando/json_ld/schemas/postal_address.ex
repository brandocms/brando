defmodule Brando.JSONLD.Schema.PostalAddress do
  @moduledoc """
  PostalAddress schema
  """

  @derive Jason.Encoder
  defstruct "@type": "PostalAddress",
            addressCountry: nil,
            addressLocality: nil,
            addressRegion: nil,
            postalCode: nil,
            streetAddress: nil

  def build(organization) do
    %__MODULE__{
      addressCountry: organization.country || nil,
      addressLocality: organization.city || nil,
      addressRegion: organization.city || nil,
      postalCode: organization.zipcode || nil,
      streetAddress: build_street_adress(organization) || nil
    }
  end

  defp build_street_adress(organization) do
    [organization.address, organization.address2, organization.address3]
    |> Enum.filter(&(&1 != nil))
    |> Enum.join(", ")
  end
end
