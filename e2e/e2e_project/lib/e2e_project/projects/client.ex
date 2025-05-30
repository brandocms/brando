defmodule E2eProject.Projects.Client do
  @moduledoc """
  Blueprint for Client
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Projects",
    schema: "Client",
    singular: "client",
    plural: "clients"

  use Gettext, backend: E2eProjectAdmin.Gettext

  alias E2eProject.Projects

  trait Brando.Trait.Creator
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  identifier "{{ entry.name }}"
  absolute_url "{% route_i18n entry.language client_path detail { entry.slug } %}"

  attributes do
    attribute :name, :text, required: true
    attribute :slug, :slug, unique: [prevent_collision: true], required: true
  end

  relations do
    relation :projects, :has_many, module: Projects.Project
  end

    forms do
    form do
      default_params %{"status" => "draft"}

      tab gettext("Content") do
        fieldset do
          size :full
          input :status, :status
        end

        fieldset do
          size :half
          input :name, :text, label: t("Name")
          input :slug, :slug, source: :name, label: t("Slug")
        end
      end
    end
  end

  listings do
    listing do
      query %{
        order: [{:asc, :name}]
      }

      filter(
        label: gettext("Name"),
        filter: "name"
      )

      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>
      <%= @entry.name %>
    </.update_link>
    """
  end

  translations do
    context :naming do
      translate :singular, t("client")
      translate :plural, t("clients")
    end
  end
end
