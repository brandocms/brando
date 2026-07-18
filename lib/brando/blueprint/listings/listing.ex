defmodule Brando.Blueprint.Listings.Listing do
  @moduledoc """
  Compiled metadata for one Blueprint admin listing.

  Values are produced by the `listings` DSL and consumed by listing LiveViews;
  applications normally declare them rather than constructing this struct.
  """
  @type t :: %__MODULE__{}

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            name: nil,
            query: %{},
            fields: [],
            filters: [],
            sorts: [],
            sortable: true,
            default_actions: true,
            actions: [],
            selection_actions: [],
            exports: [],
            child_listings: [],
            component: nil,
            limit: 25
end
