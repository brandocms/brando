defmodule Brando.JSONLD.Schema.BreadcrumbList do
  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "BreadcrumbList",
            itemListElement: []

  def build(breadcrumbs) do
    %__MODULE__{
      itemListElement: breadcrumbs
    }
  end
end
