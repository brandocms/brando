defmodule Brando.Blueprint.Listings.FilterMacro do
  @moduledoc false
  # `filter label: ..., key: ..., type: :select do option ... end` is
  # `filter/2` — options, then the block — but Spark only generates
  # `filter/1` (options with the block inside them). Fold the block in.

  defmacro filter(opts, do: block) when is_list(opts) do
    quote do
      filter(unquote(opts ++ [do: block]))
    end
  end
end
