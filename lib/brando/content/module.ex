defmodule Brando.Content.Module do
  @moduledoc """
  Ecto schema for the Villain Content Module schema

  A module can hold a setup for multiple blocks.

  ## Multi module

  A module can be setup as a multi module, meaning it can contain X other entries.

  If the entry template is not floating your boat, you can access the child entries directly
  from you main module's code:

  ```
  {% for link in entries %}
    <h2>{{ link.data.vars.header_text }}</h2>
  {% endfor %}

  {{ content | renderless }}
  ```

  We include `{{ content | renderless }}` at the bottom to show the proper UI for the
  child entries in the admin area, but since it runs through the `renderless` filter,
  it will be excluded from rendering in the frontend.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Module",
    singular: "module",
    plural: "modules",
    gettext_module: Brando.Gettext

  import Brando.Gettext
  alias Brando.Content.Var

  identifier "{{ entry.name }}"

  @derived_fields ~w(id name sequence namespace help_text multi wrapper class code refs vars svg deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.CastPolymorphicEmbeds

  attributes do
    attribute :name, :string, required: true
    attribute :namespace, :string, required: true
    attribute :help_text, :text, required: true
    attribute :class, :string, required: true
    attribute :code, :text, required: true
    attribute :svg, :text
    attribute :wrapper, :boolean

    attribute :vars, {:array, PolymorphicEmbed},
      types: Var.types(),
      type_field: :type,
      on_type_not_found: :raise,
      on_replace: :delete
  end

  relations do
    relation :entry_template, :embeds_one, module: __MODULE__.EmbeddedModule, on_replace: :delete
    relation :refs, :embeds_many, module: __MODULE__.Ref, on_replace: :delete
  end

  listings do
    listing do
      listing_query %{
        order: [{:asc, :namespace}, {:asc, :sequence}, {:desc, :inserted_at}]
      }

      filters([
        [label: t("Name"), filter: "name"],
        [label: t("Namespace"), filter: "namespace"],
        [label: t("Class"), filter: "class"]
      ])

      actions([
        [label: t("Edit module"), event: "edit_entry"],
        [
          label: t("Delete module"),
          event: "delete_entry",
          confirm: t("Are you sure?")
        ],
        [label: t("Duplicate module"), event: "duplicate_entry"]
      ])

      template(
        """
        <div class="svg">{{ entry.svg }}</div><br>
        """,
        columns: 2
      )

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
          href="/admin/config/content/modules/update/{{ entry.id }}"
          class="entry-link">
          {{ entry.name }}
        </a>
        <br>
        <small>{{ entry.help_text }}</small>
        """,
        columns: 9
      )
    end
  end

  translations do
    context :naming do
      translate :singular, t("module")
      translate :plural, t("modules")
    end
  end
end
