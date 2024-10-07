defmodule Brando.Blueprint.Listings.Listing do
  defstruct __identifier__: nil,
            name: nil,
            query: %{},
            fields: [],
            filters: [],
            sortable: true,
            default_actions: true,
            actions: [],
            selection_actions: [],
            exports: [],
            child_listings: [],
            component: nil
end
