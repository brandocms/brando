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
            static_options: [],
            default: nil,
            off: :all

  @doc false
  # Nested `option` entities are collected in `static_options` — collected
  # into `options` they overwrote an `options:` callback with `[]`. Moved
  # over here when present, so readers only look at `options`.
  def merge_static_options(%__MODULE__{static_options: [_ | _] = static} = filter),
    do: {:ok, %{filter | options: static}}

  def merge_static_options(filter), do: {:ok, filter}
end
