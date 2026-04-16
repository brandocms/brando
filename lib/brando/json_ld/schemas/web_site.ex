defmodule Brando.JSONLD.Schema.WebSite do
  @moduledoc """
  WebSite schema
  """

  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "WebSite",
            "@id": nil,
            url: nil,
            name: nil,
            publisher: nil

  def build({%Sites.Identity{} = identity, %Sites.SEO{} = seo}) do
    %__MODULE__{
      "@id": Path.join(Brando.Utils.hostname(), "#website"),
      url: seo.base_url,
      name: identity.name,
      publisher: %{"@id": Path.join(Brando.Utils.hostname(), "#identity")}
    }
  end

  def build(data) do
    %__MODULE__{
      url: Map.get(data, :url),
      name: Map.get(data, :name)
    }
  end
end
