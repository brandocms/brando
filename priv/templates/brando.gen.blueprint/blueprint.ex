defmodule <%= app_module %>.<%= domain %>.<%= schema %> do
  @moduledoc """
  Blueprint for <%= schema %>.
  """

  use Brando.Blueprint,
    application: "<%= app_module %>",
    domain: "<%= domain %>",
    schema: "<%= schema %>",
    singular: "<%= singular %>",
    plural: "<%= plural %>"

  use Gettext, backend: <%= admin_module %>.Gettext
  import Brando.Blueprint.Listings.Components.Core, only: [update_link: 1]

  trait :creator
  trait :status
  trait :timestamped

  identifier ~H"{@entry.title}"
  absolute_url false

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  listings do
    listing do
      query %{order: [desc: :inserted_at]}
      component &__MODULE__.listing_row/1
    end
  end

  forms do
    form do
      tab t("Content") do
        fieldset do
          input :title, :text, label: t("Title")
          input :slug, :slug, from: :title, label: t("Slug")
          input :status, :status, label: t("Status")
        end
      end
    end
  end

  translations do
    context :naming do
      translate :singular, t("<%= String.replace(singular, "_", " ") %>")
      translate :plural, t("<%= String.replace(plural, "_", " ") %>")
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={12}>{@entry.title}</.update_link>
    """
  end
end
