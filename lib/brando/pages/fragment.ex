defmodule Brando.Pages.Fragment do
  @moduledoc """
  Ecto schema for the Fragment schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Pages",
    schema: "Fragment",
    singular: "fragment",
    plural: "fragments",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable
  trait Brando.Trait.Villain
  trait Brando.Trait.Villain.PreventCircularReferences

  identifier "{{ entry.title }}"

  @derived_fields ~w(
    id
    title
    parent_key
    key
    language
    data
    html
    wrapper
    sequence
    creator_id
    page_id
    inserted_at
    updated_at
    deleted_at
  )a

  @derive {Jason.Encoder, only: @derived_fields}

  attributes do
    attribute :title, :string
    attribute :parent_key, :string, required: true
    attribute :key, :string, required: true
    attribute :data, :villain, required: true
    attribute :wrapper, :string
  end

  relations do
    relation :page, :belongs_to, module: Brando.Pages.Page
  end

  translations do
    context :naming do
      translate :singular, t("user")
      translate :plural, t("users")
    end
  end

  defimpl Phoenix.HTML.Safe, for: Brando.Pages.Fragment do
    def to_iodata(%{wrapper: nil} = fragment) do
      fragment.html
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{wrapper: wrapper} = fragment) do
      wrapper
      |> String.replace("{{ content }}", fragment.html)
      |> String.replace("{{ parent_key }}", fragment.parent_key)
      |> String.replace("{{ key }}", fragment.key)
      |> String.replace("{{ language }}", to_string(fragment.language))
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
