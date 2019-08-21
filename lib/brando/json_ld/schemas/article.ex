defmodule Brando.JSONLD.Schema.Article do
  @moduledoc """
  Organization schema
  """

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@type": "Article",
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
