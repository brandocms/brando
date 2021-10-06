defmodule Brando.Content.Template do
  @moduledoc """
  Villain templates
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Template",
    singular: "template",
    plural: "templates",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  identifier "{{ entry.name }}"

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Villain

  attributes do
    attribute :name, :string, required: true
    attribute :namespace, :string, required: true
    attribute :instructions, :text
    attribute :data, :villain
  end

  listings do
    listing do
      listing_query %{
        order: [{:asc, :namespace}, {:asc, :sequence}, {:desc, :inserted_at}]
      }

      filters([
        [label: gettext("Name"), filter: "name"],
        [label: gettext("Namespace"), filter: "namespace"]
      ])

      actions([
        [label: gettext("Edit template"), event: "edit_entry"],
        [
          label: gettext("Delete template"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ],
        [label: gettext("Duplicate template"), event: "duplicate_entry"]
      ])

      template(
        """
        <div class="badge">{{ entry.namespace }}</div><br>
        """,
        columns: 3
      )

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/config/content/templates/update/{{ entry.id }}"
          class="entry-link">
          {{ entry.name }}
        </a>
        <br>
        <small>{{ entry.instructions }}</small>
        """,
        columns: 7
      )
    end
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset size: :half do
          input :name, :text
          input :namespace, :text, monospace: true
          input :instructions, :textarea
        end

        fieldset size: :full do
          input :data, :blocks
        end
      end
    end
  end
end
