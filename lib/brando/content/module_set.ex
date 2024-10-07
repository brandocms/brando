defmodule Brando.Content.ModuleSet do
  @moduledoc """
  Blueprint for the ModuleSet schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "ModuleSet",
    singular: "module_set",
    plural: "module_sets",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  alias Brando.Content

  # ++ Traits
  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  # --

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :module_set_modules, :has_many,
      module: Brando.Content.ModuleSetModule,
      preload_order: [asc: :sequence],
      sort_param: :sort_module_set_module_ids,
      on_replace: :delete_if_exists,
      cast: true
  end

  absolute_url ""

  forms do
    form do
      tab gettext("Content") do
        fieldset size: :full do
          input :title, :text, label: t("Title")

          input :module_set_modules, :multi_select,
            options: &__MODULE__.get_modules/2,
            relation_key: :module_id,
            relation: :module,
            resetable: true,
            label: t("Modules")
        end
      end
    end
  end

  def get_modules(_, _) do
    Content.list_modules!(%{filter: %{parent_id: nil}, order: "asc namespace, asc name"})
  end

  listings do
    listing do
      query %{
        preload: [:module_set_modules],
        order: [{:asc, :title}, {:desc, :inserted_at}]
      }

      filter label: gettext("Title"), filter: "title"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>
      <%= @entry.title %>
      <:outside>
        <br />
        <%= Enum.count(@entry.module_set_modules) %> <%= gettext("modules in this set") %>
      </:outside>
    </.update_link>
    <.url entry={@entry} />
    """
  end

  translations do
    context :naming do
      translate :singular, t("module set")
      translate :plural, t("module sets")
    end
  end

  factory %{}
end
