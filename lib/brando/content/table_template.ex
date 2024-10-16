defmodule Brando.Content.TableTemplate do
  @moduledoc """
  Blueprint for table templates

  Table templates are used in blocks that require a table structure.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "TableTemplate",
    singular: "table_template",
    plural: "table_templates",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  identifier "{{ entry.name }}"
  persist_identifier false

  attributes do
    attribute :name, :string, required: true
  end

  relations do
    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      cast: true,
      drop_param: :drop_var_ids
  end

  forms do
    form do
      tab t("Content") do
        fieldset do
          size :half
          input :name, :text
        end

        fieldset do
          inputs_for :vars do
            label t("Columns")
            component BrandoAdmin.Components.Form.Input.Vars
          end
        end
      end
    end
  end

  listings do
    listing do
      query %{order: [{:asc, :name}]}
      filter label: gettext("Name"), filter: "name"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={11}>
      <%= @entry.name %>
    </.update_link>
    """
  end

  translations do
    context :naming do
      translate :singular, t("table template")
      translate :plural, t("table templates")
    end
  end
end
