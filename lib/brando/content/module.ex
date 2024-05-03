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
  alias Brando.Content.OldVar
  alias Phoenix.LiveView.JS

  identifier "{{ entry.name }}"

  @derived_fields ~w(id type name sequence namespace help_text wrapper class code refs vars svg deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.CastPolymorphicEmbeds

  attributes do
    attribute :type, :enum, values: [:liquid, :heex], default: :liquid
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
  end

  relations do
    relation :children, :has_many, module: __MODULE__, on_replace: :delete_if_exists
    relation :parent, :belongs_to, module: __MODULE__, on_replace: :delete_if_exists
    relation :refs, :embeds_many, module: __MODULE__.Ref, on_replace: :delete

    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete_if_exists,
      cast: true
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
        <div class="svg">{% if entry.svg %}<img src="data:image/svg+xml;base64,{{ entry.svg }}">{% endif %}</div>
        """,
        columns: 2
      )

      template(
        """
        <div class="badge">{{ entry.namespace }}</div>
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
          {% if entry.datasource %}<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" style="stroke: blue; display: inline-block" width="12" height="12">
          <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
          </svg>{% endif %} {{ entry.name }}
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
