defmodule Brando.Images.Image do
  @moduledoc """
  Embedded image
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Image",
    singular: "image",
    plural: "images",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  alias Brando.Images.Focal

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Focal

  identifier false
  persist_identifier false

  attributes do
    attribute :status, :enum, values: [:processed, :unprocessed]
    attribute :title, :text
    attribute :credits, :text
    attribute :alt, :text

    attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]

    attribute :path, :text, required: true
    attribute :width, :integer
    attribute :height, :integer
    attribute :sizes, :map
    attribute :cdn, :boolean, default: false
    attribute :dominant_color, :text
    attribute :config_target, :text
    attribute :fetchpriority, :enum, values: [:high, :low, :auto], default: :auto
  end

  relations do
    relation :focal, :embeds_one, module: Focal
  end

  listings do
    listing do
      query %{order: [{:desc, :id}]}
      filter label: t("Path"), filter: "path"
      filter label: t("Config target"), filter: "config_target_search"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.cover image={@entry} columns={2} size={:smallest} padded />
    <.field columns={9}>
      <small class="monospace">#{@entry.id}</small>
      <br />
      <small class="monospace">{@entry.path}</small>
      <br />
      <small>{@entry.width}&times;{@entry.height}</small>
      <br />
      <small>{inspect(@entry.config_target)}</small>
      <br />
      <div :if={@entry.title} class="badge mini">{gettext("Title")}</div>
      <div :if={@entry.alt} class="badge mini">Alt</div>
    </.field>
    """
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset do
          size :half
          input :title, :text, label: t("Title")
          input :credits, :text, label: t("Credits")
          input :alt, :text, label: t("Alt. text")
          input :path, :text, label: t("Path"), monospace: true
        end

        fieldset do
          size :half

          input :cdn, :toggle,
            label: t("CDN"),
            instructions: t("Asset has been transferred to CDN")

          input :width, :number, label: t("Width"), monospace: true
          input :height, :number, label: t("Height"), monospace: true
          input :dominant_color, :color, label: t("Dominant color"), monospace: true
          input :config_target, :text, label: t("Configuration target"), monospace: true

          inputs_for :focal do
            label t("Focal")
            cardinality :one
            style :inline
            default %{x: 50, y: 50}

            input :x, :text, label: t("x", Focal)
            input :y, :text, label: t("y", Focal)
          end
        end
      end
    end
  end

  @derive {Jason.Encoder,
           only: [
             :title,
             :credits,
             :formats,
             :alt,
             :focal,
             :path,
             :sizes,
             :width,
             :height,
             :cdn,
             :dominant_color,
             :config_target
           ]}
end
