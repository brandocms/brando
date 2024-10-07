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

  use Gettext, backend: Brando.Gettext

  identifier false
  persist_identifier false

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Blocks

  attributes do
    attribute :name, :string, required: true
    attribute :namespace, :string, required: true
    attribute :instructions, :text
  end

  relations do
    relation :blocks, :has_many, module: :blocks
  end

  listings do
    listing do
      query %{order: [{:asc, :namespace}, {:asc, :sequence}, {:desc, :inserted_at}]}
      filter label: t("Name"), filter: "name"
      filter label: t("Namespace"), filter: "namespace"
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.cover image={@entry.cover} columns={2} size={:smallest} padded />
    <.field columns={3}>
      <div class="badge">{{ entry.namespace }}</div>
    </.field>
    <.update_link entry={@entry} columns={6}>
      <%= @entry.name %>
      <:outside>
        <br />
        <small>{{ entry.instructions }}</small>
      </:outside>
    </.update_link>
    <.url entry={@entry} />
    """
  end

  #

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
