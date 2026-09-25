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
  import Brando.Blueprint.Listings.Components.Core
  import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]

  alias Brando.Images.Focal

  trait :creator, derived: [:sizes, :formats, :status, :cdn, :dominant_color]
  trait :timestamped
  trait :soft_delete
  trait :focal

  identifier false
  persist_identifier false

  attributes do
    attribute :status, :enum, values: [:processed, :unprocessed]
    # Language → text maps; read them with `Brando.Images.text/3`.
    attribute :title, :i18n_string
    attribute :credits, :i18n_string
    attribute :alt, :i18n_string

    attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]

    attribute :path, :text, required: true
    attribute :width, :integer
    attribute :height, :integer
    attribute :sizes, :map
    attribute :cdn, :boolean, default: false
    attribute :dominant_color, :text
    attribute :config_target, :text
    attribute :folder_id, :integer
    attribute :fetchpriority, :enum, values: [:high, :low, :auto], default: :auto

    # Block-level presentation settings, declared on
    # `Brando.Villain.Blocks.PictureBlock.Data` and merged onto the image at
    # render time by `Brando.Content.OverrideResolver`. They describe how *this
    # placement* of the image should render, never the image itself, so they are
    # virtual — nothing here is persisted on the image record, and nothing here
    # is set for an image outside a picture block.
    attribute :picture_class, :text, virtual: true
    attribute :img_class, :text, virtual: true
    attribute :link, :text, virtual: true
    attribute :srcset, :text, virtual: true

    # Where it is used, filled in by the listing (see `Brando.Content.Usage`).
    attribute :usage, :map, virtual: true
    attribute :lazyload, :boolean, virtual: true, default: false
    attribute :moonwalk, :boolean, virtual: true, default: false
    attribute :placeholder, :any, virtual: true
  end

  relations do
    relation :focal, :embeds_one, module: Focal
  end

  listings do
    listing do
      query %{order: [{:desc, :id}]}
      filter label: t("Path"), key: "path"
      filter label: t("Config target"), key: "config_target_search"
      filter label: t("Not in use"), key: "unused", type: :boolean
      decorate &__MODULE__.put_usage/1
      component &__MODULE__.listing_row/1
    end
  end

  # A local capture: the listing DSL keeps the function at compile time, and a
  # remote capture would make this Blueprint compile against the usage lookup
  # and all it reaches (issue #2737).
  @doc false
  def put_usage(entries), do: Brando.Content.Usage.put(entries, :image)

  def listing_row(assigns) do
    formats =
      case assigns.entry.formats do
        formats when is_list(formats) and formats != [] -> formats
        _ -> [:original]
      end
      |> Enum.map(fn
        :original -> assigns.entry.path |> Path.extname() |> String.trim_leading(".")
        format -> Atom.to_string(format)
      end)
      |> Enum.map(&String.upcase/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    assigns =
      assigns
      |> assign(:image_formats, formats)
      |> assign(:size_count, map_size(assigns.entry.sizes || %{}))
      |> assign(:title, Brando.Images.text(assigns.entry, :title, nil))
      |> assign(:alt_missing, Brando.Images.AltText.missing_languages(assigns.entry))
      |> assign(:language_count, length(Brando.Images.AltText.languages()))

    ~H"""
    <.cover image={@entry} columns={2} size={:smallest} class="library-thumbnail" />
    <.update_link entry={@entry} columns={9} class="library-image-info">
      {Path.basename(@entry.path)}
      <:outside>
        <p :if={@title} class="library-image-title">{@title}</p>
        <div class="library-image-meta">
          <span :if={@image_formats != []} class="library-formats" role="group" aria-label={gettext("Formats")}>
            <span :for={format <- @image_formats} class="library-format">{format}</span>
          </span>
          <span :if={@entry.width && @entry.height}>{@entry.width} × {@entry.height}</span>
          <span :if={@size_count > 0} class="library-size-count">
            {ngettext("%{count} size", "%{count} sizes", @size_count)}
          </span>
          <span class={["library-alt", @alt_missing != [] && "missing"]}>
            <%= cond do %>
              <% @alt_missing == [] -> %>
                {gettext("Alt text added")}
              <% length(@alt_missing) == @language_count -> %>
                {gettext("No alt text")}
              <% true -> %>
                {gettext("No alt text in %{languages}", languages: Enum.join(@alt_missing, ", "))}
            <% end %>
          </span>
          <span :if={@entry.status != :processed}>{gettext("Processing")}</span>
        </div>
        <BrandoAdmin.Components.Usage.inline usages={@entry.usage} />
      </:outside>
    </.update_link>
    """
  end

  forms do
    form do
      tab t("Content") do
        fieldset do
          size :half
          input :title, :i18n_text, label: t("Title"), languages: :content
          input :credits, :i18n_text, label: t("Credits"), languages: :content
          input :alt, :i18n_text, label: t("Alt. text"), languages: :content
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

  translations do
    context :naming do
      translate :singular, t("image")
      translate :plural, t("images")
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
             :config_target,
             :folder_id
           ]}
end
