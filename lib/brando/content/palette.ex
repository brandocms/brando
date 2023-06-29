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

  import Brando.Gettext

  identifier "{{ entry.name }}"

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
        fieldset size: :half do
          input :status, :status
          input :global, :toggle
          input :name, :text
          input :key, :slug, for: :name, camel_case: true
          input :namespace, :text, monospace: true
          input :instructions, :textarea
        end

        fieldset size: :full do
          inputs_for :colors,
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Content.Palette.Color{} do
            input :hex_value, :color, monospace: true
            input :name, :text
            input :key, :text, monospace: true
            input :instructions, :text, break: true
          end
        end
      end
    end
  end

  listings do
    listing do
      listing_query %{
        order: [{:asc, :namespace}, {:asc, :sequence}, {:desc, :inserted_at}]
      }

      filters([
        [label: t("Name"), filter: "name"],
        [label: t("Color"), filter: "color"]
      ])

      template(
        """
        <div class="circle-stack">
          {% for color in entry.colors reversed %}
            <div class="circle" data-color-no="{{ forloop.index0 }}" data-popover="{{ color.hex_value }}" style="background-color: {{ color.hex_value }}"></div>
          {% endfor %}
        </div>
        """,
        columns: 3
      )

      template(
        """
        <div class="monospace small">{{ entry.namespace }}</div>
        """,
        columns: 3
      )

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/config/content/palettes/update/{{ entry.id }}"
          class="entry-link">
          <small>{{ entry.name }}</small>
        </a>
        """,
        columns: 4
      )
    end
  end

  translations do
    context :naming do
      translate :singular, t("palette")
      translate :plural, t("palettes")
    end
  end
end
