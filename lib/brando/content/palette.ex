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

  identifier "[{{ entry.namespace }}] {{ entry.name }}"

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped

  attributes do
    attribute :name, :string, required: true
    attribute :key, :string, required: true
    attribute :global, :boolean
    attribute :namespace, :string, default: "site"
    attribute :instructions, :text
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
          input :namespace, :text, monospace: true
          input :instructions, :textarea
        end

        fieldset do
          inputs_for :colors do
            style :inline
            cardinality :many
            default %Brando.Content.Palette.Color{}

            input :hex_value, :color, monospace: true
            input :name, :text
            input :key, :text, monospace: true
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

      filter label: t("Name"), filter: "name"
      filter label: t("Color"), filter: "color"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field columns={3}>
      <div class="circle-stack">
        <div
          :for={{color, idx} <- Enum.with_index(Enum.reverse(@entry.colors))}
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

  translations do
    context :naming do
      translate :singular, t("palette")
      translate :plural, t("palettes")
    end
  end
end
