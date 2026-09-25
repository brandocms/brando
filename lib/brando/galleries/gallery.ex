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
  import Brando.Blueprint.Listings.Components.Core
  import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]

  alias BrandoAdmin.Components.Image
  import Ecto.Query, only: [from: 2]

  trait :timestamped
  trait :soft_delete

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
      tab t("Content") do
        fieldset do
          size :full

          inputs_for :gallery_objects do
            label t("Images and videos")
            cardinality :many
            component :gallery_objects
          end
        end

        fieldset do
          size :full
          label t("Technical")
          superuser true
          input :config_target, :text, label: t("Configuration target"), monospace: true
        end
      end
    end
  end

  @doc """
  Listing row component for gallery entries
  """
  def listing_row(assigns) do
    images =
      (assigns.entry.gallery_objects || [])
      |> Enum.flat_map(fn
        %{image: %Brando.Images.Image{} = image} -> [image]
        %{video: %{thumbnail: %Brando.Images.Image{} = image}} -> [image]
        _ -> []
      end)
      |> Enum.take(3)

    object_count = length(assigns.entry.gallery_objects || [])

    assigns =
      assigns
      |> assign(:images, images)
      |> assign(:object_count, object_count)

    ~H"""
    <.cover :if={length(@images) < 2} image={List.first(@images)} columns={2} size={:smallest} />
    <%!-- More than one image: the first three lie in a stack, so the row reads as a set. --%>
    <div :if={length(@images) > 1} class="cover col-2 gallery-stack" data-count={length(@images)}>
      <Image.image :for={image <- @images} image={image} size={:smallest} />
    </div>
    <.update_link entry={@entry} columns={7}>
      {gettext("Gallery")} #{@entry.id}
      <:outside>
        <span class="gallery-description">{gettext("Images and videos")}</span>
      </:outside>
    </.update_link>
    <.field columns={3} class="listing-gallery-count">
      <span class="workspace-badge">{ngettext("1 object", "%{count} objects", @object_count)}</span>
    </.field>
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
