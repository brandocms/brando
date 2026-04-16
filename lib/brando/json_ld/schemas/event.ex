defmodule Brando.JSONLD.Schema.Event do
  @moduledoc """
   Event schema
  """
  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Event",
            startDate: nil,
            endDate: nil,
            location: nil,
            image: nil,
            description: nil,
            artist: nil,
            organizer: nil,
            eventStatus: nil,
            eventAttendanceMode: nil,
            offers: nil
end
