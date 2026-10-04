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
  import Brando.Blueprint.Listings.Components.Core

  alias E2eProject.Projects

  content_icon "handshake"

  trait Brando.Trait.Creator
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  identifier "{{ entry.name }}"
  absolute_url ~H|{route_i18n(@entry, :client_path, :detail, [@entry.slug])}|

  attributes do
    attribute :name, :text, required: true
    attribute :slug, :slug, unique: [prevent_collision: true], required: true
  end

  relations do
    relation :projects, :has_many, module: Projects.Project

    relation :inline_rows, :has_many,
      module: Projects.InlineRow,
      cast: true,
      drop_param: :drop_inline_rows_ids,
      sort_param: :sort_inline_rows_ids,
      on_replace: :delete,
      preload_order: [asc: :sequence]
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

      # Every input an inline subform can hold, on one line per row
      tab "Inline fields" do
        fieldset do
          size :full

          inputs_for :inline_rows do
            label "Inline rows"
            style :inline
            cardinality :many
            instructions "One of every input that fits on a line."
            default %{title: "New row", status: :published}

            input :status, :status, compact: true
            input :cover, :image, label: "Image"
            input :title, :text, label: "Title"
            input :slug, :slug, source: :title, label: "Slug"
            input :key, :text, monospace: true, label: "Key"
            input :notes, :textarea, label: "Notes"
            input :email, :email, label: "Email"
            input :phone, :phone, label: "Phone"
            input :amount, :number, label: "Amount"
            input :starts_on, :date, label: "Date"
            input :starts_at, :datetime, label: "Date and time"
            input :color, :color, label: "Colour"
            input :kind, :select, label: "Kind", options: &__MODULE__.kind_options/2

            input :size, :radios,
              label: "Size",
              show_if: {:kind, ["exhibition"]},
              options: &__MODULE__.size_options/2

            input :featured, :toggle, label: "Featured"
            input :confirmed, :checkbox, label: "Confirmed"
            input :aliases, :string_list, label: "Aliases"
            input :attachment, :file, label: "File"
            input :clip, :video, label: "Video"
          end
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
        key: "name"
      )

      component &__MODULE__.listing_row/1
    end
  end

  def kind_options(_, _) do
    [
      %{label: "Talk", value: "talk"},
      %{label: "Exhibition", value: "exhibition"},
      %{label: "Party", value: "party"}
    ]
  end

  def size_options(_form, _opts) do
    [%{label: "S", value: "s"}, %{label: "M", value: "m"}, %{label: "L", value: "l"}]
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>
      {@entry.name}
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
