defmodule Brando.Content.Section do
  @moduledoc """
  Blueprint for section templates

  A section template is used by Container blocks
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Section",
    singular: "section",
    plural: "sections",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  identifier "{{ entry.name }}"

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped

  attributes do
    attribute :name, :string, required: true
    attribute :namespace, :string, default: "general"
    attribute :instructions, :text
    attribute :class, :string, required: true
    attribute :color_bg, :text
    attribute :color_fg, :text
    attribute :css, :text
    attribute :rendered_css, :text
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset size: :half do
          input :name, :text
          input :namespace, :text, monospace: true
          input :class, :text, monospace: true
          input :instructions, :textarea
          input :color_bg, :text, monospace: true
          input :color_fg, :text, monospace: true
        end

        fieldset size: :half do
          input :css, :code
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
        [label: gettext("Name"), filter: "name"]
      ])

      actions([
        [label: gettext("Edit section"), event: "edit_entry"],
        [
          label: gettext("Delete section"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ],
        [label: gettext("Duplicate section"), event: "duplicate_entry"]
      ])

      template(
        """
        <div class="circle" style="background-color: {{ entry.color_bg }}"></div>
        """,
        columns: 1
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
          href="/admin/config/content/sections/update/{{ entry.id }}"
          class="entry-link">
          {{ entry.name }}
        </a>
        <div class="monospace tiny">{{ entry.color_bg }} / {{ entry.color_fg }}</div>
        """,
        columns: 6
      )
    end
  end
end
