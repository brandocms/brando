defmodule Brando.JSONLD.Schema.BreadcrumbList do
  @moduledoc false
  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "BreadcrumbList",
            "@id": nil,
            itemListElement: []

  def build(breadcrumbs) do
    %__MODULE__{
      "@id": "#{Brando.Utils.hostname()}/#breadcrumb",
      itemListElement: breadcrumbs
    }
  end
end
