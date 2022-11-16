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
  alias Phoenix.LiveView.JS

  identifier "{{ entry.name }}"

  @derived_fields ~w(id name sequence namespace help_text wrapper class code refs vars svg deleted_at)a
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

    attribute :datasource, :boolean, default: false
    attribute :datasource_module, :string
    attribute :datasource_type, Ecto.Enum, values: [:list, :single, :selection]
    attribute :datasource_query, :string

    attribute :vars, {:array, Brando.PolymorphicEmbed},
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

      selection_actions([
        [
          label: t("Export modules"),
          event: JS.push("export_modules") |> BrandoAdmin.Utils.show_modal("#module-export-modal")
        ]
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

  factory %{
    class: "header middle",
    code: """
    <article data-v="text center" data-moonwalk-section>
      <div class="inner" data-moonwalk>
        <div class="text">
          {% ref refs.H2 %}
        </div>
      </div>
    </article>
    """,
    deleted_at: nil,
    help_text: "Help Text",
    name: "Heading",
    namespace: "general",
    refs: [
      %{
        "data" => %{
          "data" => %{
            "class" => nil,
            "id" => nil,
            "level" => 2,
            "text" => "Heading here"
          },
          "type" => "header"
        },
        "description" => "A heading",
        "name" => "H2"
      }
    ],
    vars: [],
    wrapper: false,
    uid: "abcdef"
  }
end
