defmodule BrandoAdmin.Components.Form.Input.Gallery.Media do
  @moduledoc """
  Shared media bookkeeping for the two gallery editors.

  `Input.Gallery` (a gallery field on some other schema) and
  `Input.GalleryObjects` (the Gallery blueprint's own form) are different
  components with genuinely different write targets — the first has to reach an
  entry form that owns it at a path, the second edits the entry changeset
  directly. Everything *around* that write was duplicated line for line, which
  is how they came to carry the same two bugs (D4, D5): a fix landing in one
  copy said nothing about the other.

  So the write stays with each component and everything else lives here.
  """
  import Phoenix.LiveView, only: [send_update: 2]

  alias Brando.Galleries.GalleryObject
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker

  @doc "Renumber `sequence` to match list position."
  def sequence(gallery_objects) do
    gallery_objects
    |> Enum.with_index()
    |> Enum.map(fn {object, index} -> Map.put(object, :sequence, index) end)
  end

  @doc """
  Append a picked image or video, returning the new object list and selection.

  The appended object keeps its loaded `:image` / `:video` — that association is
  what renders the thumbnail, and it does not survive the trip through
  `slim_gallery_object/1` and back (see `Brando.Galleries.merge_loaded_media/2`).
  """
  def add(gallery_objects, media_type, media_id, current_user) do
    {:ok, media} = fetch(media_type, media_id)

    object =
      %GalleryObject{creator_id: current_user.id}
      |> Map.put(id_field(media_type), media.id)
      |> Map.put(assoc_field(media_type), media)

    updated = gallery_objects ++ [object]

    {updated, selected_ids(updated, id_field(media_type))}
  end

  @doc "Drop a picked image or video, returning the new object list and selection."
  def remove(gallery_objects, media_type, media_id) do
    field = id_field(media_type)
    id = parse_id(media_id)

    updated = Enum.reject(gallery_objects, &(Map.get(&1, field) == id))

    {updated, selected_ids(updated, field)}
  end

  @doc "The `put_assoc`-ready params for a list of gallery objects."
  def slim(gallery_objects) do
    gallery_objects
    |> Enum.map(&Brando.Galleries.slim_gallery_object/1)
    |> sequence()
  end

  @doc """
  Tell the picker what the editor currently holds.

  "Selection means current editing state" (see the uploads skill) — the picker
  marks the unsaved list, not the persisted one.
  """
  def notify_picker(:image, selected_ids),
    do: send_update(ImagePicker, id: "image-picker", selected_images: selected_ids)

  def notify_picker(:video, selected_ids),
    do: send_update(VideoPicker, id: "video-picker", selected_videos: selected_ids)

  def fetch(:image, id), do: Brando.Images.get_image(id)
  def fetch(:video, id), do: Brando.Videos.get_video(%{matches: %{id: id}, preload: [:thumbnail]})

  def id_field(:image), do: :image_id
  def id_field(:video), do: :video_id

  def assoc_field(:image), do: :image
  def assoc_field(:video), do: :video

  def selection_key(:image), do: :selected_images
  def selection_key(:video), do: :selected_videos

  def selected_ids(gallery_objects, id_field) do
    gallery_objects
    |> Enum.map(&Map.get(&1, id_field))
    |> Enum.reject(&is_nil/1)
  end

  def parse_id(id) when is_binary(id), do: String.to_integer(id)
  def parse_id(id), do: id

  @doc """
  Is this picker click selecting or deselecting?

  Both components dispatch on the same question, and both used to parse the id
  inline to ask it.
  """
  def selected?(selection, id), do: parse_id(id) in selection
end
