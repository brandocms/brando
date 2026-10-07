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
      addressCountry: Map.get(organization, :country),
      addressLocality: Map.get(organization, :city),
      addressRegion: Map.get(organization, :region, nil),
      postalCode: Map.get(organization, :zipcode),
      streetAddress: build_street_adress(organization) || nil
    }
  end

  defp build_street_adress(organization) do
    [:address, :address2, :address3]
    |> Enum.map(&Map.get(organization, &1))
    |> Enum.filter(&(&1 != nil))
    |> Enum.join(", ")
  end
end
