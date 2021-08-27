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
  alias Brando.Pages

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
    attribute :data, :villain
    attribute :wrapper, :string
  end

  relations do
    relation :page, :belongs_to, module: Brando.Pages.Page
  end

  translations do
    context :naming do
      translate :singular, t("fragment")
      translate :plural, t("fragments")
    end

    context :fields do
      translate :title do
        label t("Title")
        placeholder t("Title")
      end

      translate :parent_key do
        label t("Parent key")
        placeholder t("parent_key")
      end

      translate :key do
        label t("Key")
        placeholder t("key")
      end

      translate :data do
        label t("Content")
      end

      translate :wrapper do
        label t("Wrapper")

        instructions t(
                       "You can access the fragment's rendered content as <code>{{ content }}</code>"
                     )
      end
    end
  end

  forms do
    form do
      redirect_on_save &__MODULE__.redirect/2

      tab "Content" do
        fieldset size: :half do
          input :title, :text
          input :parent_key, :text, monospace: true
          input :key, :text, monospace: true
        end

        fieldset size: :half do
          input :language, :select, options: :languages, narrow: true
          input :page_id, :select, options: &__MODULE__.get_pages/2, resetable: true
        end

        fieldset size: :full do
          input :data, :blocks
        end
      end

      tab "Advanced" do
        fieldset size: :full do
          input :wrapper, :code
        end
      end
    end
  end

  def redirect(socket, _entry) do
    Brando.routes().live_path(socket, BrandoAdmin.PageListLive)
  end

  def get_pages(_, _) do
    {:ok, pages} = Pages.list_pages()

    Enum.map(
      pages,
      &%{value: to_string(&1.id), label: "[#{String.upcase(to_string(&1.language))}] #{&1.title}"}
    )
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
