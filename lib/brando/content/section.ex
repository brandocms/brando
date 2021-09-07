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
        <div class="monospace">{{ entry.namespace }}</div><br>
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
        """,
        columns: 9
      )
    end
  end
end
