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
    plural: "pages"

  alias Brando.Pages.Fragment
  alias Brando.Pages.Property

  # ++ Traits
  trait Brando.Trait.Creator
  trait Brando.Trait.Meta
  trait Brando.Trait.Revisioned
  trait Brando.Trait.ScheduledPublishing
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete, obfuscated_fields: [:uri]
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
    properties
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
    attribute :status, :status
    attribute :css_classes, :string
  end

  relations do
    relation :parent, :belongs_to, module: __MODULE__
    relation :children, :has_many, module: __MODULE__, foreign_key: :parent_id
    relation :fragments, :has_many, module: Fragment
    relation :properties, :has_many, module: Property, on_replace: :delete, cast: true
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

  defimpl Phoenix.HTML.Safe, for: __MODULE__ do
    def to_iodata(%{html: html}) do
      html
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
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
