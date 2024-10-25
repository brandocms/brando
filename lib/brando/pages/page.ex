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

  use Gettext, backend: Brando.Gettext
  alias Brando.Pages
  alias Brando.Pages.Fragment

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
  trait Brando.Trait.Blocks

  # --

  alias Brando.JSONLD

  @derived_fields ~w(
    id
    uri
    language
    title
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

  identifier "{{ entry.title }}"

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

  attributes do
    attribute :title, :string, required: true
    attribute :uri, :string, required: true, unique: [prevent_collision: :language]
    attribute :template, :string, required: true
    attribute :is_homepage, :boolean
    attribute :has_url, :boolean, default: true
    attribute :css_classes, :string
  end

  relations do
    relation :parent, :belongs_to, module: __MODULE__
    relation :children, :has_many, module: __MODULE__, foreign_key: :parent_id
    relation :fragments, :has_many, module: Fragment
    relation :blocks, :has_many, module: :blocks

    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      cast: true,
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids
  end

  @derive {Jason.Encoder, only: @derived_fields}

  translations do
    context :naming do
      translate :singular, t("page")
      translate :plural, t("pages")
    end
  end

  listings do
    listing do
      query %{
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

      filter label: t("URI"), filter: "uri"
      filter label: t("Title"), filter: "title"
      action label: t("Create subpage"), event: "create_subpage"
      action label: t("Create fragment"), event: "create_fragment"
      child_listing name: :fragment_children, schema: Brando.Pages.Fragment
      child_listing name: :page_children, schema: Brando.Pages.Page
      component &__MODULE__.listing_row/1
    end

    listing :fragment_children do
      action label: t("Edit fragment"), event: "edit_fragment"
      action label: t("Duplicate fragment"), event: "duplicate_fragment"
      action label: t("Delete fragment"), event: "delete_fragment", confirm: t("Are you sure?")
      default_actions false
      component &__MODULE__.listing_fragment_row/1
    end

    listing :page_children do
      action label: t("Edit sub page"), event: "edit_subpage"
      action label: t("Duplicate sub page"), event: "duplicate_entry"
      action label: t("Delete sub page"), event: "delete_entry", confirm: t("Are you sure?")
      default_actions false
      component &__MODULE__.listing_child_row/1
    end
  end

  def listing_row(assigns) do
    assigns =
      assign(
        assigns,
        :url,
        assigns.entry.has_url && (Brando.HTML.absolute_url(assigns.entry) || gettext("<no URL>"))
      )

    ~H"""
    <div class="col-1 center">
      <div
        :if={@entry.is_homepage}
        class="badge"
        data-popover={gettext("This page is marked as the homepage.")}
      >
        <Brando.HTML.icon name="hero-home" class="s" />
      </div>
    </div>
    <.update_link entry={@entry} columns={7}>
      <%= @entry.title %>
      <:outside>
        <br />
        <div :if={@entry.has_url} class="badge lowercase no-border">
          <a class="flex-h" href={@url} target="_blank">
            <Brando.HTML.icon name="hero-globe-alt" class="s mr-1" />
            <%= @url %>
          </a>
        </div>
      </:outside>
    </.update_link>
    <.children_button entry={@entry} fields={[:fragments, :children]} />
    """
  end

  def listing_fragment_row(assigns) do
    ~H"""
    <div class="center col-1">⤷</div>
    <.update_link entry={@entry} columns={6}>
      <%= @entry.title %>
      <:outside>
        <br />
        <div class="badge no-border">
          <Brando.HTML.icon name="hero-key" class="mr-1" /> <%= @entry.parent_key %>/<%= @entry.key %>
        </div>
      </:outside>
    </.update_link>
    <div class="col-3">
      <div class="badge uppercase">
        <%= gettext("Fragment") %>
      </div>
    </div>
    """
  end

  def listing_child_row(assigns) do
    assigns =
      assign(assigns, :url, Brando.HTML.absolute_url(assigns.entry))

    ~H"""
    <div class="center col-1">⤷</div>
    <.update_link entry={@entry} columns={6}>
      <%= @entry.title %>
      <:outside>
        <br />

        <div class="badge no-border lowercase">
          <a class="flex-h" href={@url} target="_blank">
            <Brando.HTML.icon name="hero-globe-alt" class="s mr-1" />
            <%= @url %>
          </a>
        </div>
      </:outside>
    </.update_link>
    <div class="col-2">
      <div class="badge uppercase">
        <%= gettext("Sub page") %>
      </div>
    </div>
    """
  end

  forms do
    form do
      default_params %{status: :draft, template: "default.html", uri: "uri"}
      blocks :blocks, label: t("Blocks")

      tab t("Content") do
        fieldset do
          input :status, :status, label: t("Status")
        end

        fieldset do
          size :half
          input :title, :text, label: t("Title")
          input :uri, :slug, show_url: true, monospace: true, label: t("URI")
        end

        fieldset do
          size :half

          input :language, :select,
            options: :languages,
            narrow: true,
            label: t("Language")

          input :parent_id, :select,
            options: &__MODULE__.get_parents/2,
            resetable: true,
            label: t("Parent page")
        end
      end

      tab t("Advanced") do
        fieldset do
          size :half

          input :is_homepage, :toggle,
            label: t("Homepage"),
            instructions: t("Page is loaded at root address")

          input :has_url, :toggle,
            label: t("Has URL"),
            instructions: t("Page has an URL and should be included in sitemap")

          input :template, :select,
            options: &__MODULE__.get_templates/2,
            monospace: true,
            label: t("Template")

          input :css_classes, :text, label: t("CSS classes")
        end

        fieldset do
          inputs_for :vars do
            label t("Page variables")
            component BrandoAdmin.Components.Form.Input.Vars
          end
        end
      end
    end
  end

  meta_schema do
    field ["description", "og:description"], & &1.meta_description
    field ["title", "og:title"], &fallback([Map.get(&1, :meta_title), Map.get(&1, :title)])
    field "og:image", &Map.get(&1, :meta_image)
    field "og:locale", &encode_locale(try_path(&1, [:__meta__, :language]))
  end

  json_ld_schema JSONLD.Schema.Article do
    field :author, :identity
    field :copyrightHolder, :identity
    field :creator, :identity
    field :publisher, :identity
    field :copyrightYear, :integer, & &1.inserted_at.year
    field :dateModified, :datetime, & &1.updated_at
    field :datePublished, :datetime, & &1.inserted_at
    field :description, :string, & &1.meta_description
    field :headline, :string, & &1.title
    field :inLanguage, :language
    field :mainEntityOfPage, :current_url
    field :name, :string, & &1.title
    field :url, :current_url
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
    def to_iodata(%{rendered_blocks: html}) do
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
