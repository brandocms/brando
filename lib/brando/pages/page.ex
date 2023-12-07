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

  alias Brando.Content.OldVar
  alias Brando.Pages
  alias Brando.Pages.Fragment

  import Brando.Gettext

  # ++ Traits
  trait Brando.Trait.CastPolymorphicEmbeds
  trait Brando.Trait.Creator
  trait Brando.Trait.Meta
  trait Brando.Trait.Revisioned
  trait Brando.Trait.ScheduledPublishing
  trait Brando.Trait.Sequenced, append: true
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
    has_url
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
    attribute :has_url, :boolean, default: true
    attribute :data, :villain
    attribute :css_classes, :string

    attribute :vars, {:array, Brando.PolymorphicEmbed},
      types: OldVar.types(),
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
  {%- assign language = entry.language|strip -%}
  {%- if config.scope_default_language_routes == true -%}
    /{{ entry.language }}
  {%- else -%}
    {%- if language != config.default_language -%}/{{ entry.language }}{%- endif -%}
  {%- endif -%}
  {%- if entry.uri == "index" -%}
    {%- route_i18n entry.language page_path index -%}
  {%- else -%}
    {%- route_i18n entry.language page_path show { entry.uri } -%}
  {%- endif -%}
  """

  translations do
    context :naming do
      translate :singular, t("page")
      translate :plural, t("pages")
    end
  end

  listings do
    listing do
      listing_query %{
        filter: %{parents: true},
        preload: [
          fragments: %{
            module: Fragment,
            order: [asc: :sequence],
            preload: [creator: :avatar],
            hide_deleted: true
          },
          children: %{
            module: __MODULE__,
            order: [asc: :sequence],
            preload: [:alternate_entries, creator: :avatar],
            hide_deleted: true
          }
        ],
        order: [{:asc, :sequence}, {:desc, :inserted_at}]
      }

      filters([
        [label: t("URI"), filter: "uri"],
        [label: t("Title"), filter: "title"]
      ])

      actions([
        [label: t("Create subpage"), event: "create_subpage"],
        [label: t("Create fragment"), event: "create_fragment"]
      ])

      field :language, :language, columns: 1

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/pages/update/{{ entry.id }}"
          class="entry-link">
          {% if entry.is_homepage %}
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" width="16" height="16" style="display: inline;margin-top: -2px;">
              <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 21v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21m0 0h4.5V3.545M12.75 21h7.5V10.75M2.25 21h1.5m18 0h-18M2.25 9l4.5-1.636M18.75 3l-1.5.545m0 6.205l3 1m1.5.5l-1.5-.5M6.75 7.364V3h-3v18m3-13.636l10.5-3.819" />
            </svg>
          {% endif %}
          {{ entry.title }}
        </a>
        {% if entry.has_url %}
          <br>
          <div class="badge lowercase no-border">
            <a class="flex-h" href="{{ entry | absolute_url }}" target="_blank">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" width="12" height="12">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418" />
              </svg>
              {{ entry | absolute_url }}
            </a>
          </div>
        {% endif %}
        """,
        columns: 7
      )

      field [:fragments, :children], :children_button, columns: 1

      child_listing [
        {Brando.Pages.Fragment, :fragment_children},
        {Brando.Pages.Page, :page_children}
      ]
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
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" style="display: inline;margin-top: -2px;" class="mr-1">
            <path stroke-linecap="round" stroke-linejoin="round" d="M14.25 6.087c0-.355.186-.676.401-.959.221-.29.349-.634.349-1.003 0-1.036-1.007-1.875-2.25-1.875s-2.25.84-2.25 1.875c0 .369.128.713.349 1.003.215.283.401.604.401.959v0a.64.64 0 01-.657.643 48.39 48.39 0 01-4.163-.3c.186 1.613.293 3.25.315 4.907a.656.656 0 01-.658.663v0c-.355 0-.676-.186-.959-.401a1.647 1.647 0 00-1.003-.349c-1.036 0-1.875 1.007-1.875 2.25s.84 2.25 1.875 2.25c.369 0 .713-.128 1.003-.349.283-.215.604-.401.959-.401v0c.31 0 .555.26.532.57a48.039 48.039 0 01-.642 5.056c1.518.19 3.058.309 4.616.354a.64.64 0 00.657-.643v0c0-.355-.186-.676-.401-.959a1.647 1.647 0 01-.349-1.003c0-1.035 1.008-1.875 2.25-1.875 1.243 0 2.25.84 2.25 1.875 0 .369-.128.713-.349 1.003-.215.283-.4.604-.4.959v0c0 .333.277.599.61.58a48.1 48.1 0 005.427-.63 48.05 48.05 0 00.582-4.717.532.532 0 00-.533-.57v0c-.355 0-.676.186-.959.401-.29.221-.634.349-1.003.349-1.035 0-1.875-1.007-1.875-2.25s.84-2.25 1.875-2.25c.37 0 .713.128 1.003.349.283.215.604.401.96.401v0a.656.656 0 00.658-.663 48.422 48.422 0 00-.37-5.36c-1.886.342-3.81.574-5.766.689a.578.578 0 01-.61-.58v0z" />
          </svg>
          {{ entry.title }}
        </a>
        <br>
        <div class="badge lowercase no-border"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> {{ entry.parent_key }}/{{ entry.key }}</div>
        """,
        columns: 8
      )

      actions(
        [
          [label: t("Edit fragment"), event: "edit_fragment"],
          [label: t("Duplicate fragment"), event: "duplicate_fragment"],
          [
            label: t("Delete fragment"),
            event: "delete_fragment",
            confirm: t("Are you sure?")
          ]
        ],
        default_actions: false
      )
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
        <div class="badge lowercase no-border"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg> {{ entry.uri }}</div>
        """,
        columns: 7
      )

      actions(
        [
          [label: t("Edit sub page"), event: "edit_subpage"],
          [label: t("Duplicate sub page"), event: "duplicate_entry"],
          [
            label: t("Delete sub page"),
            event: "delete_entry",
            confirm: t("Are you sure?")
          ]
        ],
        default_actions: false
      )
    end
  end

  forms do
    form default_params: %{status: :draft, template: "default.html"} do
      tab t("Content") do
        fieldset size: :full do
          input :status, :status, label: t("Status")
        end

        fieldset size: :half do
          input :title, :text, label: t("Title")
          input :uri, :slug, show_url: true, monospace: true, label: t("URI")
        end

        fieldset size: :half do
          input :language, :select,
            options: :languages,
            narrow: true,
            label: t("Language")

          input :parent_id, :select,
            options: &__MODULE__.get_parents/2,
            resetable: true,
            label: t("Parent page")
        end

        fieldset size: :full do
          input :data, :blocks, label: t("Blocks")
        end
      end

      tab t("Advanced") do
        fieldset size: :half do
          input :is_homepage, :toggle,
            label: t("Homepage"),
            instructions: t("Page is loaded at root address")

          input :has_url, :toggle,
            label: t("Has URL"),
            instructions: t("Page has an URL and should be included in sitemap")

          input :template, :select, options: &__MODULE__.get_templates/2, label: t("Template")
          input :css_classes, :text, label: t("CSS classes")
        end

        fieldset size: :full do
          inputs_for :vars, {:component, BrandoAdmin.Components.Pages.PageVars},
            label: t("Page variables")
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

  def get_parents(form, _) do
    {:ok, parents} = Pages.list_pages(%{filter: %{parents: true}})

    filtered_parents =
      parents
      |> filter_self(Ecto.Changeset.get_field(form.source, :id))
      |> filter_language(Ecto.Changeset.get_field(form.source, :language))

    filtered_parents
  end

  defp filter_self(parents, id) when not is_nil(id), do: Enum.filter(parents, &(&1.id != id))
  defp filter_self(parents, _), do: parents

  defp filter_language(parents, language) when not is_nil(language),
    do: Enum.filter(parents, &(&1.language == language))

  defp filter_language(parents, _), do: parents

  defimpl Phoenix.HTML.Safe do
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

  factory %{
    uri: "a-key",
    language: "en",
    title: "Page Title",
    html: nil,
    template: "default.html",
    data: nil,
    vars: [],
    status: :published,
    creator: nil,
    parent_id: nil,
    meta_image: nil
  }
end
