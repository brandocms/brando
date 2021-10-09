defmodule Brando.Pages.Page do
  @moduledoc """
  Ecto schema for the Page schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Pages",
    schema: "Page",
    singular: "page",
    plural: "pages",
    gettext_module: Brando.Gettext

  alias Brando.Content.Var
  alias Brando.Pages
  alias Brando.Pages.Fragment

  import Brando.Gettext

  # ++ Traits
  trait Brando.Trait.CastPolymorphicEmbeds
  trait Brando.Trait.Creator
  trait Brando.Trait.Meta
  trait Brando.Trait.Revisioned
  trait Brando.Trait.ScheduledPublishing
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete, obfuscated_fields: [:uri]
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable
  trait Brando.Trait.Villain

  # --

  alias Brando.JSONLD

  @derived_fields ~w(
    id
    uri
    language
    title
    data
    html
    is_homepage
    template
    status
    css_classes
    creator_id
    parent_id
    meta_title
    meta_description
    meta_image
    sequence
    vars
    inserted_at
    updated_at
    deleted_at
    publish_at
  )a

  attributes do
    attribute :title, :string, required: true
    attribute :uri, :string, required: true, unique: [prevent_collision: :language]
    attribute :template, :string, required: true
    attribute :is_homepage, :boolean
    attribute :data, :villain
    attribute :css_classes, :string

    attribute :vars, {:array, PolymorphicEmbed},
      types: [
        boolean: Var.Boolean,
        text: Var.Text,
        string: Var.String,
        datetime: Var.Datetime,
        html: Var.Html,
        color: Var.Color
      ],
      type_field: :type,
      on_type_not_found: :raise,
      on_replace: :delete
  end

  relations do
    relation :parent, :belongs_to, module: __MODULE__
    relation :children, :has_many, module: __MODULE__, foreign_key: :parent_id
    relation :fragments, :has_many, module: Fragment
  end

  @derive {Jason.Encoder, only: @derived_fields}
  identifier "{{ entry.title }} [{{ entry.language }}]"

  absolute_url """
  {% if entry.uri == "index" %}
    {% route page_path index %}
  {% else %}
    {% route page_path show { entry.uri } %}
  {% endif %}
  """

  listings do
    listing do
      listing_query %{
        status: :published,
        preload: [fragments: :creator, children: :creator],
        order: [{:asc, :sequence}, {:desc, :inserted_at}]
      }

      filters([
        [label: gettext("URI"), filter: "uri"],
        [label: gettext("Title"), filter: "title"]
      ])

      actions([
        [label: gettext("Edit page"), event: "edit_entry"],
        [
          label: gettext("Delete page"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ],
        [label: gettext("Duplicate page"), event: "duplicate_entry"],
        [label: gettext("Create subpage"), event: "create_subpage"],
        [label: gettext("Create fragment"), event: "create_fragment"]
      ])

      selection_actions([
        [label: gettext("Delete pages"), event: "delete_selected"]
      ])

      field(:language, :language, columns: 1)

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/pages/update/{{ entry.id }}"
          class="entry-link">
          {% if entry.is_homepage %}
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16" style="display: inline;margin-top: -2px;"><path fill="none" d="M0 0h24v24H0z"/><path d="M6 19h12V9.157l-6-5.454-6 5.454V19zm13 2H5a1 1 0 0 1-1-1v-9H1l10.327-9.388a1 1 0 0 1 1.346 0L23 11h-3v9a1 1 0 0 1-1 1zM7.5 13h2a2.5 2.5 0 1 0 5 0h2a4.5 4.5 0 1 1-9 0z"/></svg>
          {% endif %}
          {{ entry.title }}
        </a>
        <br>
        <div class="badge lowercase no-border"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> {{ entry.uri }}</div><br>
        """,
        columns: 8
      )

      field([:fragments, :children], :children_button, columns: 1)

      child_listing([
        {Brando.Pages.Fragment, :fragment_children},
        {Brando.Pages.Page, :page_children}
      ])
    end

    listing :fragment_children do
      template """
               <div class="center">⤷</div>
               """,
               columns: 1

      field :language, :language, columns: 1

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/pages/fragments/update/{{ entry.id }}"
          class="entry-link smaller">
          {{ entry.title }}
        </a>
        <br>
        <div class="badge"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M10 10.111V1l11 6v14H3V7l7 3.111zm2-5.742v8.82l-7-3.111V19h14V8.187L12 4.37z"/></svg> {{ entry.parent_key }}/{{ entry.key }}</div><br>
        """,
        columns: 9
      )

      actions([
        [label: gettext("Edit fragment"), event: "edit_entry"],
        [
          label: gettext("Delete fragment"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ]
      ])
    end

    listing :page_children do
      template """
               <div class="center">⤷</div>
               """,
               columns: 1

      field :language, :language, columns: 1

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/pages/update/{{ entry.id }}"
          class="entry-link smaller">
          {{ entry.title }}
        </a>
        <br>
        <div class="badge"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> {{ entry.uri }}</div><br>
        """,
        columns: 9
      )

      actions([
        [label: gettext("Edit sub page"), event: "edit_entry"],
        [
          label: gettext("Delete sub page"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ]
      ])
    end
  end

  forms do
    form default_params: %{status: :draft} do
      tab gettext("Content") do
        fieldset size: :full do
          input :status, :status
        end

        fieldset size: :half do
          input :title, :text
          input :uri, :text, monospace: true
        end

        fieldset size: :half do
          input :language, :select, options: :languages, narrow: true
          input :parent_id, :select, options: &__MODULE__.get_parents/2, resetable: true
        end

        fieldset size: :full do
          input :data, :blocks
        end
      end

      tab gettext("Advanced") do
        fieldset size: :half do
          input :is_homepage, :toggle
          input :template, :select, options: &__MODULE__.get_templates/2
          input :css_classes, :text
        end

        fieldset size: :full do
          inputs_for :vars, {:component, BrandoAdmin.Components.Form.Input.PageVars}
        end
      end
    end
  end

  meta_schema do
    meta_field ["description", "og:description"], [:meta_description]
    meta_field ["title", "og:title"], &fallback(&1, [:meta_title, :title])
    meta_field "og:image", [:meta_image]
    meta_field "og:locale", [:language], &encode_locale/1
  end

  json_ld_schema JSONLD.Schema.Article do
    json_ld_field :author, {:references, :identity}
    json_ld_field :copyrightHolder, {:references, :identity}
    json_ld_field :copyrightYear, :string, [:inserted_at, :year]
    json_ld_field :creator, {:references, :identity}
    json_ld_field :dateModified, :string, [:updated_at], &JSONLD.to_datetime/1
    json_ld_field :datePublished, :string, [:inserted_at], &JSONLD.to_datetime/1
    json_ld_field :description, :string, [:meta_description]
    json_ld_field :headline, :string, [:title]
    json_ld_field :inLanguage, :string, [:language]
    json_ld_field :mainEntityOfPage, :string, [:__meta__, :current_url]
    json_ld_field :name, :string, [:title]
    json_ld_field :publisher, {:references, :identity}
    json_ld_field :url, :string, [:__meta__, :current_url]
  end

  def get_templates(_, _) do
    {:ok, templates} = Pages.list_templates()
    Enum.map(templates, &%{value: &1, label: &1})
  end

  def get_parents(_, _) do
    {:ok, parents} = Pages.list_pages(%{filter: %{parents: true}})

    Enum.map(
      parents,
      &%{value: to_string(&1.id), label: "[#{String.upcase(to_string(&1.language))}] #{&1.title}"}
    )
  end

  defimpl Phoenix.HTML.Safe, for: __MODULE__ do
    def to_iodata(%{html: html}) do
      html
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
      |> Brando.HTML.replace_timestamp()
    end

    def to_iodata(_) do
      raise """

      Failed to auto generate protocol for #{inspect(__MODULE__)} struct.
      Missing `:html` key.

      Call `use Brando.Villain.Schema, generate_protocol: false` instead

      """
    end
  end
end
