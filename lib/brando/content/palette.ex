defmodule Brando.Content.Palette do
  @moduledoc """
  Blueprint for palettes

  Palettes are used by container blocks via CSS variables to set a color scheme
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Palette",
    singular: "palette",
    plural: "palettes",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Brando.Blueprint.Listings.Components.Core

  content_icon "palette"

  identifier "[{{ entry.namespace }}] {{ entry.name }}"

  trait :creator
  trait :sequenced
  trait :soft_delete
  trait :status
  trait :timestamped

  # Key and namespace name the palette's section attribute and its CSS
  # custom properties (`[b-section="site-dark"]`, `--palette-site-dark-bg`).
  @css_name ~r/\A[\p{L}\p{N}_-]+\z/u

  attributes do
    attribute :name, :string, required: true
    attribute :key, :string, required: true, constraints: [format: @css_name]
    attribute :global, :boolean
    attribute :namespace, :string, default: "site", constraints: [format: @css_name]
    attribute :instructions, :text
    attribute :version, :integer, default: 1
    attribute :version_note, :text
    attribute :source_palette_id, :integer
    attribute :source_version, :integer
    attribute :acknowledged_version, :integer
    attribute :library_origin, :enum, values: [:local, :shared], default: :local, virtual: true
    attribute :update_available, :boolean, default: false, virtual: true
    attribute :override_id, :integer, virtual: true
  end

  relations do
    relation :colors, :embeds_many, module: Brando.Content.Palette.Color, on_replace: :delete
  end

  forms do
    form do
      tab t("Content") do
        fieldset do
          size :half
          input :status, :status
          input :global, :toggle
          input :name, :text
          input :key, :slug, source: :name, camel_case: true
          input :namespace, :text, monospace: true, instructions: t("Letters, digits, - and _")
          input :instructions, :textarea
        end

        fieldset do
          inputs_for :colors do
            style :inline
            cardinality :many
            default fn _entry, _ -> struct(Brando.Content.Palette.Color) end

            input :hex_value, :color, monospace: true
            input :name, :text
            input :key, :text, monospace: true, instructions: t("Letters, digits, - and _")
            input :instructions, :text
          end
        end
      end
    end
  end

  listings do
    listing do
      query %{
        status: :published,
        order: [{:asc, :namespace}, {:asc, :sequence}, {:desc, :inserted_at}]
      }

      filter label: t("Name"), key: "name"
      filter label: t("Color"), key: "color"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field columns={3}>
      <div class="circle-stack">
        <div
          :for={{color, idx} <- Enum.with_index(Enum.reverse(@entry.colors))}
          :key={idx}
          class="circle"
          data-color-no={idx}
          data-popover={color.hex_value}
          style={"background-color: #{color.hex_value}"}
        >
        </div>
      </div>
    </.field>
    <.field columns={3}>
      <div class="monospace small">{@entry.namespace}</div>
    </.field>
    <.update_link entry={@entry} columns={4}>
      <small>{@entry.name}</small>
    </.update_link>
    """
  end

  @doc """
  Whether `name` is a key or namespace the palette changeset accepts:
  letters (in any script), digits, `-` and `_`.
  """
  @spec css_name?(term()) :: boolean()
  def css_name?(name) when is_binary(name), do: Regex.match?(@css_name, name)
  def css_name?(_), do: false

  @doc """
  `name`, a palette's key or namespace or a colour's key, for CSS: as an
  identifier (`--\#{css_escape(key)}`) or inside a quoted string. A name the
  changeset accepts comes back as it is; any other character, in a name
  stored before names were checked, is hex-escaped, so it cannot leave its
  selector, declaration or `<style>` element. CSS reads the escape back as
  the character, so the escaped name still matches the attribute.
  """
  @spec css_escape(String.t() | nil) :: String.t()
  def css_escape(nil), do: ""

  def css_escape(name) when is_binary(name) do
    for <<char::utf8 <- name>>, into: "", do: css_escape_char(char)
  end

  # Six hex digits need no terminating space, which a minifier could drop
  defp css_escape_char(char)
       when char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?-, ?_] or char >= 0x80,
       do: <<char::utf8>>

  defp css_escape_char(char), do: "\\" <> String.pad_leading(Integer.to_string(char, 16), 6, "0")

  @doc """
  The palette colours whose value can be written into CSS: a colour stored
  before values were checked (`Brando.Color`) is left out.
  """
  @spec css_colors([Brando.Content.Palette.Color.t()] | nil) :: [Brando.Content.Palette.Color.t()]
  def css_colors(colors), do: Enum.filter(colors || [], &Brando.Color.valid?(&1.hex_value))

  translations do
    context :naming do
      translate :singular, t("palette")
      translate :plural, t("palettes")
    end
  end
end
