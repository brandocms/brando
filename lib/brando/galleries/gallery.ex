defmodule Brando.Galleries.Gallery do
  @moduledoc """
  Collection of images and videos
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Galleries",
    schema: "Gallery",
    singular: "gallery",
    plural: "galleries",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Brando.Blueprint.Listings.Components
  import Ecto.Query

  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete

  identifier false
  persist_identifier false

  attributes do
    attribute :config_target, :text
  end

  relations do
    relation :gallery_objects, :has_many,
      module: Brando.Galleries.GalleryObject,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      sort_param: :sort_gallery_object_ids,
      drop_param: :drop_gallery_object_ids,
      cast: true
  end

  listings do
    listing do
      query %{
        order: [{:desc, :id}],
        preload: [{:gallery_objects, [:image, video: [:thumbnail]]}]
      }

      component &__MODULE__.listing_row/1
    end
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset do
          size :full
          input :config_target, :text, label: t("Configuration target"), monospace: true
        end

        fieldset do
          size :full

          inputs_for :gallery_objects do
            label t("Gallery objects")
            cardinality :many
            component BrandoAdmin.Components.Form.Input.GalleryObjects
          end
        end
      end
    end
  end

  @doc """
  Listing row component for gallery entries
  """
  def listing_row(assigns) do
    first_image =
      case assigns.entry.gallery_objects do
        [%{image: image} | _] when not is_nil(image) -> image
        _ -> nil
      end

    object_count = length(assigns.entry.gallery_objects || [])

    assigns =
      assigns
      |> assign(:first_image, first_image)
      |> assign(:object_count, object_count)

    ~H"""
    <.field columns={1}>
      <small class="monospace">#{@entry.id}</small>
    </.field>
    <.cover image={@first_image} columns={2} size={:smallest} />
    <.update_link entry={@entry} columns={12}>
      {gettext("Gallery")} #{@entry.id}
      <:outside>
        <br />
        <small>{ngettext("1 object", "%{count} objects", @object_count)}</small>
        <br />
        <small :if={@entry.config_target} class="monospace">{@entry.config_target}</small>
      </:outside>
    </.update_link>
    """
  end

  @doc """
  Returns preloaded gallery query
  """
  def preloads_for do
    gallery_objects_query =
      from go in Brando.Galleries.GalleryObject,
        order_by: [asc: go.sequence],
        preload: [:image, video: [:thumbnail]]

    from g in Brando.Galleries.Gallery,
      preload: [gallery_objects: ^gallery_objects_query]
  end
end
