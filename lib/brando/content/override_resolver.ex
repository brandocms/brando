defmodule Brando.Content.OverrideResolver do
  @moduledoc """
  Single source of truth for media override semantics.

  Convention: `nil` = use default from media record. Non-nil = explicit override.
  """

  @doc """
  Merge block data overrides into media struct, skipping nil values.
  nil values mean "use the default from the media record".

  Raises if `override_attrs` carries a key the media struct cannot hold.
  `Kernel.struct/2` drops such keys silently, which is how block-level
  presentation settings (`lazyload`, `placeholder`, `play_button`, …) used to
  vanish between the ref and the renderer: the merged struct simply did not
  have the field, and the parser's `Map.get(data, key, default)` fell back to
  the default. A caller that needs to pass a field the media schema does not
  have should add it to the schema as a virtual attribute — see the block
  override attributes on `Brando.Images.Image` and `Brando.Videos.Video`.
  """
  # No media to merge into (e.g. an unresolved/not-yet-loaded association) — nothing
  # to override, so return nil instead of crashing on `Map.from_struct(nil)`.
  def merge_overrides(nil, _override_attrs), do: nil

  def merge_overrides(media_struct, override_attrs) when is_map(override_attrs) do
    non_nil_overrides =
      override_attrs
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    ensure_holdable!(media_struct, non_nil_overrides)

    struct(media_struct, Map.merge(Map.from_struct(media_struct), non_nil_overrides))
  end

  defp ensure_holdable!(%schema{} = media_struct, overrides) do
    case Map.keys(overrides) -- Map.keys(Map.from_struct(media_struct)) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError, """
        #{inspect(schema)} has no field for the override keys #{inspect(unknown)}.

        `Kernel.struct/2` would drop them without a word and the renderer would fall
        back to its defaults. Either stop passing these keys, or declare them on
        #{inspect(schema)} as virtual attributes.
        """
    end
  end

  @doc "Check if a field is overridden (non-nil)"
  def overridden?(data, field), do: Map.get(data, field) != nil
end
