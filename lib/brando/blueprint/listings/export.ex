defmodule Brando.Blueprint.Listings.Export do
  defstruct name: nil,
            label: nil,
            type: :csv,
            fields: [],
            description: nil,
            query: %{},
            after_export: nil
end
