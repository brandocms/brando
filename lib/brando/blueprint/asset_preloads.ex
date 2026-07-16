defmodule Brando.Blueprint.AssetPreloads do
  @moduledoc """
  Builds media-association preloads for complete Blueprint entry queries.

  Keeping this read concern separate prevents asset casting from depending on
  concrete gallery schemas and their transitive media graph.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.Assets

  @gallery_schema Module.concat(["Brando", "Galleries", "Gallery"])
  @gallery_object_schema Module.concat(["Brando", "Galleries", "GalleryObject"])

  @doc """
  Returns the media preloads declared by `schema`.

  Gallery assets include ordered gallery objects and their image/video assets.
  """
  @spec for_schema(module()) :: list()
  def for_schema(schema) do
    gallery_object_schema = @gallery_object_schema
    gallery_schema = @gallery_schema

    gallery_objects_query =
      from gallery_object in gallery_object_schema,
        order_by: [asc: gallery_object.sequence],
        preload: [:image, :video]

    gallery_query =
      from gallery in gallery_schema,
        preload: [gallery_objects: ^gallery_objects_query]

    Enum.reduce(Assets.__assets__(schema), [], fn asset, preloads ->
      case asset.type do
        type when type in [:file, :image, :video] -> [asset.name | preloads]
        :gallery -> [{asset.name, gallery_query} | preloads]
        _type -> preloads
      end
    end)
  end
end
