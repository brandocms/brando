defmodule Brando.Blueprint.Listings.Filter do
  @moduledoc """
  Represents a filter for listing data.

  Supports three types:
  - `:text` - Text search input (default)
  - `:boolean` - Toggle switch
  - `:select` - Dropdown select with options
  """
  defstruct __spark_metadata__: nil,
            label: nil,
            key: nil,
            type: :text,
            options: [],
            default: nil
end
