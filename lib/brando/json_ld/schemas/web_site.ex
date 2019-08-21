defmodule Brando.JSONLD.Schema.WebSite do
  @moduledoc """
  Organization schema
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@type": "WebSite",
            url: nil,
            name: nil

  def build(data) do
    url = Map.get(data, :url)
    name = Map.get(data, :name)

    %__MODULE__{
      url: url,
      name: name
    }
  end
end
