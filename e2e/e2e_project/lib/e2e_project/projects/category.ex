defmodule E2eProject.Projects.Category do
  @moduledoc """
  Blueprint for Category
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Projects",
    schema: "Category",
    singular: "category",
    plural: "categories"

  use Gettext, backend: E2eProjectAdmin.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  identifier "{{ entry.title }}"
  absolute_url "{% route_i18n entry.language category_path detail { entry.slug } %}"

  attributes do
    attribute :title, :text, required: true
    attribute :slug, :slug, unique: [prevent_collision: true], required: true
  end

  forms do
    form do
      default_params %{"status" => "published"}

      tab gettext("Content") do
        fieldset do
          size :full
          input :status, :status
        end

        fieldset do
          size :half
          input :title, :text, label: t("Title")
          input :slug, :slug, source: :title, show_url: true, label: t("Slug")
        end
      end
    end
  end

  listings do
    listing do
      query %{
        status: :published,
        order: [{:asc, :title}, {:desc, :inserted_at}]
      }

      filter(
        label: gettext("Title"),
        filter: "title"
      )

      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={9}>
      <%= @entry.title %>
    </.update_link>
    """
  end

  translations do
    context :naming do
      translate :singular, t("category")
      translate :plural, t("categories")
    end
  end
end
