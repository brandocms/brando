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
      tab gettext("Content") do
        fieldset size: :half do
          input :global, :toggle
          input :name, :text
          input :key, :text, monospace: true
          input :namespace, :text, monospace: true
          input :instructions, :textarea
        end

        fieldset size: :full do
          inputs_for :colors,
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Content.Palette.Color{} do
            input :name, :text
            input :key, :text, monospace: true
            input :hex_value, :text, monospace: true
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
        [label: gettext("Name"), filter: "name"],
        [label: gettext("Color"), filter: "color"]
      ])

      actions([
        [label: gettext("Edit palette"), event: "edit_entry"],
        [
          label: gettext("Delete palette"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ],
        [label: gettext("Duplicate palette"), event: "duplicate_entry"]
      ])

      template(
        """
        <div class="circle-stack">
          {% for color in entry.colors reversed %}
            <div class="circle" data-color-no="{{ forloop.index0 }}" style="background-color: {{ color.hex_value }}"></div>
          {% endfor %}
        </div>
        """,
        columns: 2
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
          {{ entry.name }}
        </a>
        <div class="monospace tiny"></div>
        """,
        columns: 5
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
