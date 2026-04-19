defmodule Brando.JSONLD.Schema.Article do
  @moduledoc """
  Article schema
  """

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Article",
            "@id": nil,
            author: nil,
            copyrightHolder: nil,
            copyrightYear: nil,
            creator: nil,
            dateModified: nil,
            datePublished: nil,
            description: nil,
            headline: nil,
            image: nil,
            inLanguage: nil,
            mainEntityOfPage: nil,
            name: nil,
            publisher: nil,
            url: nil
end
