defmodule Brando.Villain.Blocks.TextBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "text"

  defmodule Data do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    @style_elements ~w(p h1 h2 h3 h4 h5 h6 span)
    @style_class_regex ~r/^[A-Za-z_][A-Za-z0-9_-]*$/

    embedded_schema do
      field :text, :string
      field :type, Ecto.Enum, values: [:paragraph, :lede, :lead], default: :paragraph
      field :extensions, {:array, :string}
      field :styles, {:array, :map}, default: []
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w(text type extensions styles)a)
      |> maybe_validate_styles()
    end

    def default_styles do
      [
        %{
          "element" => "p",
          "class" => "lede",
          "label" => "Lede",
          "icon" => "hero-circle"
        }
      ]
    end

    def normalize_styles(styles) when is_list(styles) do
      {normalized, _seen} =
        Enum.reduce(styles, {[], MapSet.new()}, fn entry, {acc, seen} ->
          case normalize_style(entry) do
            {:ok, style} ->
              dedupe_key = {style["element"], style["class"]}

              if MapSet.member?(seen, dedupe_key) do
                {acc, seen}
              else
                {[style | acc], MapSet.put(seen, dedupe_key)}
              end

            :error ->
              {acc, seen}
          end
        end)

      Enum.reverse(normalized)
    end

    def normalize_styles(_), do: []

    defp maybe_validate_styles(%{changes: %{styles: styles}} = changeset) do
      {valid_styles, invalid_indexes} =
        styles
        |> List.wrap()
        |> Enum.with_index()
        |> Enum.reduce({[], []}, fn {entry, index}, {valid, invalid} ->
          case normalize_style(entry) do
            {:ok, style} -> {[style | valid], invalid}
            :error -> {valid, [index | invalid]}
          end
        end)

      if invalid_indexes == [] do
        put_change(changeset, :styles, normalize_styles(Enum.reverse(valid_styles)))
      else
        add_error(
          changeset,
          :styles,
          "contains invalid entries at indexes: #{invalid_indexes |> Enum.reverse() |> Enum.join(", ")}"
        )
      end
    end

    defp maybe_validate_styles(changeset), do: changeset

    defp normalize_style(entry) when is_map(entry) do
      normalized_entry =
        Enum.reduce(entry, %{}, fn
          {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
          {key, value}, acc when is_binary(key) -> Map.put(acc, key, value)
          _, acc -> acc
        end)

      with {:ok, element} <- normalize_element(normalized_entry["element"]),
           {:ok, class_name} <- normalize_class_name(normalized_entry["class"]) do
        {:ok,
         %{"element" => element, "class" => class_name}
         |> maybe_put_optional("label", normalized_entry["label"])
         |> maybe_put_optional("icon", normalized_entry["icon"])}
      end
    end

    defp normalize_style(_), do: :error

    defp normalize_element(element) when is_atom(element), do: normalize_element(Atom.to_string(element))

    defp normalize_element(element) when is_binary(element) do
      normalized = element |> String.trim() |> String.downcase()

      if normalized in @style_elements do
        {:ok, normalized}
      else
        :error
      end
    end

    defp normalize_element(_), do: :error

    defp normalize_class_name(class_name) when is_atom(class_name),
      do: normalize_class_name(Atom.to_string(class_name))

    defp normalize_class_name(class_name) when is_binary(class_name) do
      normalized = String.trim(class_name)

      if Regex.match?(@style_class_regex, normalized) do
        {:ok, normalized}
      else
        :error
      end
    end

    defp normalize_class_name(_), do: :error

    defp maybe_put_optional(map, _key, nil), do: map

    defp maybe_put_optional(map, key, value) when is_atom(value),
      do: maybe_put_optional(map, key, Atom.to_string(value))

    defp maybe_put_optional(map, key, value) when is_binary(value) do
      case String.trim(value) do
        "" -> map
        normalized -> Map.put(map, key, normalized)
      end
    end

    defp maybe_put_optional(map, _key, _value), do: map
  end

  def protected_attrs do
    [:text]
  end
end
