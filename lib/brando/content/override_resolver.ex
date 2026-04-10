defmodule Brando.Content.OverrideResolver do
  @moduledoc """
  Single source of truth for media override semantics.

  Convention: `nil` = use default from media record. Non-nil = explicit override.
  """

  @doc """
  Merge block data overrides into media struct, skipping nil values.
  nil values mean "use the default from the media record".
  """
  def merge_overrides(media_struct, override_attrs) when is_map(override_attrs) do
    non_nil_overrides =
      override_attrs
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    struct(media_struct, Map.merge(Map.from_struct(media_struct), non_nil_overrides))
  end

  @doc "Check if a field is overridden (non-nil)"
  def overridden?(data, field), do: Map.get(data, field) != nil
end
