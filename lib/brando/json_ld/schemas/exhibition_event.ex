defmodule Brando.JSONLD.Schema.ExhibitionEvent do
  @moduledoc """
  Organization schema
  """

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@type": "ExhibitionEvent",
            startDate: nil,
            endDate: nil,
            location: nil,
            image: nil,
            description: nil,
            artist: nil
end
