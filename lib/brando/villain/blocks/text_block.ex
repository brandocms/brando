defmodule Brando.Villain.Blocks.TextBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "text"

  defmodule Style do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @style_elements ~w(p h1 h2 h3 h4 h5 h6 span)
    @style_class_regex ~r/^[A-Za-z_][A-Za-z0-9_-]*$/

    def style_elements, do: @style_elements

    @primary_key {:id, :binary_id, autogenerate: true}

    embedded_schema do
      field :element, :string
      field :class, :string
      field :label, :string
      field :icon, :string
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w(element class label icon)a)
      |> validate_required([:element, :class])
      |> validate_element()
      |> validate_class()
    end

    defp validate_element(changeset) do
      changeset
      |> update_change(:element, &(&1 |> String.trim() |> String.downcase()))
      |> validate_inclusion(:element, @style_elements)
    end

    defp validate_class(changeset) do
      changeset
      |> update_change(:class, &String.trim/1)
      |> validate_format(:class, @style_class_regex, message: "must be a valid CSS class name")
    end
  end

  defmodule Data do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    alias Brando.Villain.Blocks.TextBlock.Style

    @primary_key false

    embedded_schema do
      field :text, :string
      field :type, Ecto.Enum, values: [:paragraph, :lede, :lead], default: :paragraph
      field :extensions, {:array, :string}
      field :footnotes, :boolean, default: false
      field :footnote_module_set, :string, default: "Footnotes"
      embeds_many :styles, Style, on_replace: :delete
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w(text type extensions footnotes footnote_module_set)a)
      |> cast_embed(:styles,
        sort_param: :sort_style_ids,
        drop_param: :drop_style_ids
      )
    end

    def default_styles do
      [
        %Style{
          element: "p",
          class: "lede",
          label: "Lede",
          icon: "hero-circle-stack"
        }
      ]
    end

    @doc """
    Normalizes styles for JSON encoding to the TipTap component.
    Accepts a list of Style structs or maps.
    """
    def normalize_styles(styles) when is_list(styles) do
      {normalized, _seen} =
        Enum.reduce(styles, {[], MapSet.new()}, fn entry, {acc, seen} ->
          entry = to_style_map(entry)
          dedupe_key = {entry["element"], entry["class"]}

          if MapSet.member?(seen, dedupe_key) do
            {acc, seen}
          else
            {[entry | acc], MapSet.put(seen, dedupe_key)}
          end
        end)

      Enum.reverse(normalized)
    end

    def normalize_styles(_), do: []

    defp to_style_map(%Style{} = style) do
      %{"element" => style.element, "class" => style.class}
      |> maybe_put("label", style.label)
      |> maybe_put("icon", style.icon)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, _key, ""), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))
  end

  def protected_attrs do
    [:text]
  end
end
