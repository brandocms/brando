defmodule Brando.Blueprint.Listings.Export do
  @moduledoc false
  defstruct __spark_metadata__: nil,
            name: nil,
            label: nil,
            type: :csv,
            fields: [],
            description: nil,
            query: %{},
            after_export: nil
end
