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
        [label: t("Name"), filter: "name"],
        [label: t("Namespace"), filter: "namespace"]
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
      blocks :blocks, label: t("Blocks")

      tab t("Content") do
        fieldset size: :half do
          input :name, :text
          input :namespace, :text, monospace: true
          input :instructions, :textarea
        end
      end
    end
  end
end
