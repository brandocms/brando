defmodule Brando.Villain.Blocks.GalleryObjectOverride do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Villain",
    schema: "GalleryObjectOverride",
    singular: "gallery_object_override",
    plural: "gallery_object_overrides",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier false
  persist_identifier false

  attributes do
    # Names the override in the edit session (`BlockField.Ops`), so two
    # editors' changes to it meet however the gallery was reordered meanwhile;
    # see `object_uid/1`. Not a key: the media and `placement` are.
    attribute :uid, :string
    attribute :object_id, :string, required: true
    attribute :object_type, :enum, values: [:image, :video], required: true
    # Which placement of the media the override is for, when the gallery
    # holds it more than once: 0 for the first in gallery order. nil (one
    # placement, and every override stored before placements) applies to
    # each placement without one of its own.
    attribute :placement, :integer
    attribute :title, :string
    attribute :credits, :string
    attribute :alt, :string
    # A video's caption for this placement (rich text). An image's caption is
    # its `title`; a video's `title` stays plain, it names the player.
    attribute :caption, :string
    attribute :use_default_title, :boolean, default: true
    attribute :use_default_credits, :boolean, default: true
    attribute :use_default_alt, :boolean, default: true
    attribute :use_default_caption, :boolean, default: true

    # Video playback config overrides
    attribute :autoplay, :boolean
    attribute :loop, :boolean
    attribute :muted, :boolean
    attribute :controls, :boolean
    attribute :preload, :boolean
    # `Brando.Videos.Playback.qualities/0`; nil = use the video's
    attribute :quality, :enum, values: [:auto, :hls, :mp4_360, :mp4_480, :mp4_720, :mp4_1080]
    attribute :use_default_autoplay, :boolean, default: true
    attribute :use_default_loop, :boolean, default: true
    attribute :use_default_muted, :boolean, default: true
    attribute :use_default_controls, :boolean, default: true
    attribute :use_default_preload, :boolean, default: true
  end

  # `object_id` is the id of the image or video, and images and videos are
  # numbered by separate sequences — image 45 and video 45 can sit in the same
  # gallery. An override therefore only identifies its media together with
  # `object_type`. An override stored without a type matches on the id alone.
  #
  # A gallery may hold one image or video more than once. Each placement is its
  # own gallery object with its own override, told apart by `placement`: the
  # placement's position among that media's placements in gallery order. The
  # media key and the order carry over to copies of the gallery, which a gallery
  # object's id does not. An override without a placement applies to every
  # placement of its media that has none of its own: that is how galleries
  # stored before placements existed keep their captions.

  @text_fields ~w(title credits alt caption)

  @doc """
  Casts an override from editor params.

  The editor submits only the texts; an empty text inherits the media's own.
  Each `use_default_*` flag is derived from its text when the params carry the
  text but not the flag, so the flag the renderer reads always agrees with what
  the editor shows. Params that set a flag explicitly keep it.
  """
  def cast_override(override, params) do
    override
    |> changeset(params)
    |> derive_use_default(params)
  end

  defp derive_use_default(changeset, params) when is_map(params) do
    Enum.reduce(@text_fields, changeset, fn field, acc ->
      flag = "use_default_" <> field

      if param?(params, field) and not param?(params, flag) do
        Ecto.Changeset.put_change(acc, String.to_existing_atom(flag), not Brando.Captions.present?(param(params, field)))
      else
        acc
      end
    end)
  end

  defp derive_use_default(changeset, _params), do: changeset

  defp param?(params, key), do: Map.has_key?(params, key) or Map.has_key?(params, String.to_existing_atom(key))
  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  @doc """
  Returns `{object_type, object_id}` for an override given as a struct, a plain
  map (atom or string keys) or a changeset. `object_type` is `nil` when the
  override has none.
  """
  def media_key(%Ecto.Changeset{} = override) do
    media_key(%{
      object_id: Ecto.Changeset.get_field(override, :object_id),
      object_type: Ecto.Changeset.get_field(override, :object_type)
    })
  end

  def media_key(%{object_id: id} = override) when not is_nil(id) and id != "",
    do: {media_type(Map.get(override, :object_type)), to_string(id)}

  def media_key(%{"object_id" => id} = override) when not is_nil(id) and id != "",
    do: {media_type(Map.get(override, "object_type")), to_string(id)}

  def media_key(_), do: nil

  @doc """
  Whether `override` applies to the `type` media (`:image` or `:video`) with `id`.
  """
  def for_media?(override, type, id) do
    case media_key(override) do
      {nil, override_id} -> override_id == to_string(id)
      {override_type, override_id} -> override_type == type && override_id == to_string(id)
      nil -> false
    end
  end

  @doc """
  The `uid` for a new override of a gallery object: `g` and the object's id,
  or the media's type and id when the object is not saved yet (a gallery adds
  each media once, so no two unsaved objects share one). The same gallery
  object gives the same uid in each editor's browser, so two editors opening
  a gallery stored without uids name its overrides alike.

  The uid stays with its override when the object moves, is copied or has its
  media replaced. It only has to be unique within the gallery's overrides.
  """
  def object_uid(%{id: id}) when is_integer(id), do: "g#{id}"
  def object_uid(%{image_id: id}) when not is_nil(id), do: "image-#{id}"
  def object_uid(%{video_id: id}) when not is_nil(id), do: "video-#{id}"
  def object_uid(_object), do: nil

  @doc """
  `object_uid/1` for `object`, made unique among `taken` (a set of uids) by a
  numbered suffix: an override keeps its uid when its media is replaced, so a
  media added again afterwards would otherwise get the same one.
  """
  def unique_uid(object, taken) do
    case object_uid(object) do
      nil ->
        nil

      base ->
        [base]
        |> Stream.concat(Stream.map(Stream.iterate(2, &(&1 + 1)), &"#{base}-#{&1}"))
        |> Enum.find(&(not MapSet.member?(taken, &1)))
    end
  end

  @doc """
  Returns the override's `uid`, given as a struct, a plain map or a changeset.
  """
  def uid(%Ecto.Changeset{} = override), do: Ecto.Changeset.get_field(override, :uid)
  def uid(%{uid: uid}), do: uid
  def uid(%{"uid" => uid}), do: uid
  def uid(_), do: nil

  @doc """
  Returns the override's `placement`, given as a struct, a plain map (atom or
  string keys) or a changeset: an integer, or `nil` when it has none.
  """
  def placement(%Ecto.Changeset{} = override), do: override |> Ecto.Changeset.get_field(:placement) |> to_placement()
  def placement(%{placement: placement}), do: to_placement(placement)
  def placement(%{"placement" => placement}), do: to_placement(placement)
  def placement(_), do: nil

  @doc """
  Casts a placement from params or stored data: a non-negative integer, or `nil`.
  """
  def to_placement(placement) when is_integer(placement) and placement >= 0, do: placement

  def to_placement(placement) when is_binary(placement) do
    case Integer.parse(placement) do
      {number, ""} when number >= 0 -> number
      _ -> nil
    end
  end

  def to_placement(_), do: nil

  @doc """
  Whether `override` is the one stored for the `type` media with `id` at
  `placement` (`nil` for an override that applies to every placement).
  """
  def for_placement?(override, type, id, placement),
    do: for_media?(override, type, id) && placement(override) == placement

  @doc """
  Numbers the placements of a gallery's media. Takes the gallery's objects in
  order as `{type, id}` (or `nil` for an object without media) and returns
  `{type, id, placement}` for each, where `placement` is the object's position
  among the placements of its media, or `nil` when the gallery holds that media
  once. Overrides are stored under the same key.
  """
  def placements(media_keys) do
    media_keys = Enum.map(media_keys, &normalize_media_key/1)
    counts = media_keys |> Enum.reject(&is_nil/1) |> Enum.frequencies()

    {keys, _seen} =
      Enum.map_reduce(media_keys, %{}, fn
        nil, seen ->
          {nil, seen}

        {type, id} = key, seen ->
          position = Map.get(seen, key, 0)
          placement = if counts[key] > 1, do: position
          {{type, id, placement}, Map.put(seen, key, position + 1)}
      end)

    keys
  end

  defp normalize_media_key({type, id}) when not is_nil(id) and id != "", do: {type, to_string(id)}
  defp normalize_media_key(_), do: nil

  @doc """
  Indexes overrides by media and placement for `lookup/4`. A later override
  for the same media and placement replaces an earlier one.
  """
  def index(overrides) do
    Enum.reduce(overrides || [], %{}, fn override, acc ->
      case media_key(override) do
        nil -> acc
        {type, id} -> Map.put(acc, {type, id, placement(override)}, override)
      end
    end)
  end

  @doc """
  Finds the override for the `type` media with `id` at `placement` in an
  `index/1` map: the placement's own, else the one for every placement of the
  media. A typed override is preferred over one stored without a type. A
  media held once (`placement` nil) also takes an override stored for its
  first placement.
  """
  def lookup(index, type, id, placement \\ nil) do
    id = to_string(id)
    placements = if is_nil(placement), do: [nil, 0], else: [placement, nil]

    Enum.find_value(placements, fn placement ->
      Map.get(index, {type, id, placement}) || Map.get(index, {nil, id, placement})
    end)
  end

  @doc """
  Moves placement overrides with their gallery objects in a gallery ref's form
  params.

  The gallery block's form names gallery objects and overrides by their index
  in the form as it was rendered, and orders the objects by the gallery's
  `sort_gallery_object_ids` and `drop_gallery_object_ids` params. An override
  names a placement by its position among its media's placements, so when the
  order changes the repeats' positions, each override takes its object's new
  placement; a removed object's override goes with it, and a media left in the
  gallery once gets an override without a placement. Params for a gallery that
  holds each media once are returned as they are.
  """
  def follow_order(
        %{
          "gallery" => %{"gallery_objects" => %{} = objects} = gallery,
          "data" => %{"data" => %{"gallery_object_overrides" => overrides}}
        } = params
      )
      when is_map(overrides) or is_list(overrides) do
    with {:ok, indexes} <- form_indexes(objects),
         old_keys = Enum.map(indexes, &param_media_key(objects[&1])),
         true <- repeats?(old_keys) do
      order = form_order(indexes, gallery["sort_gallery_object_ids"], gallery["drop_gallery_object_ids"])
      before = Enum.zip(indexes, old_keys)
      after_order = Enum.map(order, &{&1 || make_ref(), &1 && param_media_key(objects[&1])})
      moves = placement_moves(before, after_order)
      put_in(params, ["data", "data", "gallery_object_overrides"], move_overrides(overrides, moves))
    else
      _ -> params
    end
  end

  def follow_order(params), do: params

  @doc """
  Settles a gallery ref's overrides in its params before they are saved.

  Two editors' changes to one gallery meet in the edit session, which merges
  each override's fields by its `uid`. A change to an override another editor
  removed meanwhile arrives without the rest of it: an override without media
  is dropped. And when one editor reorders a repeated image's copies while
  another removes one, an override can be left with a placement its copy no
  longer has. An override whose uid names one of the gallery's objects
  (`object_uid/1`: the gallery's own, not one copied from another gallery)
  takes that object's placement.
  """
  def settle(%{"data" => %{"data" => %{"gallery_object_overrides" => overrides}}} = params)
      when is_map(overrides) or is_list(overrides) do
    overrides = reject_overrides(overrides, &partial?/1)

    overrides =
      case final_objects(params["gallery"]) do
        {:ok, objects} -> place_by_uid(overrides, objects)
        :error -> overrides
      end

    put_in(params, ["data", "data", "gallery_object_overrides"], overrides)
  end

  def settle(params), do: params

  # No media, or a uid (given by the editor, which also gives the type)
  # without a type: the fields one editor changed, merged after another
  # removed the override. An override stored without a type and a uid is
  # from before types, and keeps matching its media by id.
  defp partial?(override) do
    case media_key(override) do
      nil -> true
      {nil, _id} -> uid(override) not in [nil, ""]
      _key -> false
    end
  end

  defp reject_overrides(overrides, fun) when is_list(overrides), do: Enum.reject(overrides, fun)

  defp reject_overrides(overrides, fun),
    do: overrides |> Enum.reject(fn {_index, override} -> fun.(override) end) |> Map.new()

  defp final_objects(%{"gallery_objects" => objects}) when is_list(objects), do: {:ok, objects}

  defp final_objects(%{"gallery_objects" => %{} = objects} = gallery) do
    with {:ok, indexes} <- form_indexes(objects) do
      order = form_order(indexes, gallery["sort_gallery_object_ids"], gallery["drop_gallery_object_ids"])
      {:ok, Enum.map(order, &(&1 && objects[&1]))}
    end
  end

  defp final_objects(_gallery), do: :error

  defp place_by_uid(overrides, objects) do
    keys = objects |> Enum.map(&param_media_key/1) |> placements()

    # A uid two objects give (two unsaved copies of one media) names neither
    by_uid =
      objects
      |> Enum.zip(keys)
      |> Enum.flat_map(fn
        {object, {_type, _id, _placement} = key} -> object |> param_object_uid() |> List.wrap() |> Enum.map(&{&1, key})
        _ -> []
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn
        {uid, [key]} -> [{uid, key}]
        _ -> []
      end)
      |> Map.new()

    place = fn override ->
      with uid when is_binary(uid) <- uid(override),
           {type, id, placement} <- Map.get(by_uid, uid),
           true <- for_media?(override, type, id) do
        put_param(override, "placement", placement)
      else
        _ -> override
      end
    end

    if is_list(overrides),
      do: Enum.map(overrides, place),
      else: Map.new(overrides, fn {index, override} -> {index, place.(override)} end)
  end

  defp param_object_uid(%{} = object) do
    id = object["id"]

    if present_id?(id) do
      case Integer.parse(to_string(id)) do
        {id, ""} -> object_uid(%{id: id})
        _ -> nil
      end
    else
      case param_media_key(object) do
        {type, id} -> "#{type}-#{id}"
        nil -> nil
      end
    end
  end

  defp param_object_uid(_object), do: nil

  @doc """
  Moves placement overrides from one order of a gallery's objects to another,
  as `follow_order/1` does for form params. `before` and `after_objects` list
  the objects as `{identity, {type, id}}`, where `identity` names the same
  object in both (an object only in `after_objects` needs one of its own).
  """
  def follow_objects(overrides, before, after_objects) do
    if before |> Enum.map(&elem(&1, 1)) |> repeats?(),
      do: move_overrides(overrides || [], placement_moves(before, after_objects)),
      else: overrides
  end

  defp form_indexes(objects) do
    indexes = Enum.map(Map.keys(objects), &form_index/1)
    if Enum.all?(indexes), do: {:ok, indexes |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))}, else: :error
  end

  defp form_index(key) when is_binary(key) do
    case Integer.parse(key) do
      {number, ""} -> {number, key}
      _ -> nil
    end
  end

  defp form_index(_key), do: nil

  defp repeats?(keys) do
    keys = Enum.reject(keys, &is_nil/1)
    length(keys) != length(Enum.uniq(keys))
  end

  # The order `Ecto.Changeset.cast_assoc/3` gives the objects: those the sort
  # param names first, then the rest by index, without the dropped ones. An
  # index the sort param names without a row becomes a new, empty object.
  defp form_order(indexes, sort, drop) do
    drop = if is_list(drop), do: Enum.map(drop, &to_string/1), else: []
    sort = if is_list(sort), do: Enum.map(sort, &to_string/1), else: []

    {sorted, pending} =
      Enum.map_reduce(sort -- drop, indexes, fn index, pending ->
        if index in pending, do: {index, List.delete(pending, index)}, else: {nil, pending}
      end)

    sorted ++ Enum.reject(pending, &(&1 in drop))
  end

  # `{type, id, old_placement}` => the placement in the new order, or `:removed`
  defp placement_moves(before, after_objects) do
    new =
      after_objects
      |> Enum.map(&elem(&1, 1))
      |> placements()
      |> then(&Enum.zip(Enum.map(after_objects, fn {identity, _key} -> identity end), &1))
      |> Map.new()

    before
    |> Enum.map(&elem(&1, 0))
    |> Enum.zip(placements(Enum.map(before, &elem(&1, 1))))
    |> Enum.flat_map(fn
      {identity, {type, id, placement}} when not is_nil(placement) ->
        moved =
          case Map.fetch(new, identity) do
            {:ok, {_type, _id, new_placement}} -> new_placement
            _ -> :removed
          end

        [{{type, id, placement}, moved}]

      _ ->
        []
    end)
    |> Map.new()
  end

  defp move_overrides(overrides, moves) when is_list(overrides),
    do: Enum.flat_map(overrides, &move_override(&1, moves))

  defp move_overrides(overrides, moves) do
    Enum.reduce(overrides, %{}, fn {index, override}, acc ->
      case move_override(override, moves) do
        [moved] -> Map.put(acc, index, moved)
        [] -> acc
      end
    end)
  end

  defp move_override(%{} = override, moves) do
    key =
      case media_key(override) do
        {type, id} when not is_nil(type) -> {type, id, placement(override)}
        _ -> nil
      end

    case Map.fetch(moves, key) do
      {:ok, :removed} -> []
      {:ok, placement} -> [put_param(override, "placement", placement && to_string(placement))]
      :error -> [override]
    end
  end

  defp move_override(override, _moves), do: [override]

  defp put_param(%{placement: _} = override, _key, value), do: %{override | placement: to_placement(value)}
  defp put_param(override, key, value), do: Map.put(override, key, value)

  defp param_media_key(%{} = object) do
    cond do
      present_id?(object["image_id"]) -> {:image, to_string(object["image_id"])}
      present_id?(object["video_id"]) -> {:video, to_string(object["video_id"])}
      true -> nil
    end
  end

  defp param_media_key(_object), do: nil

  defp present_id?(id), do: not is_nil(id) and id != ""

  defp media_type(type) when type in [:image, :video], do: type
  defp media_type("image"), do: :image
  defp media_type("video"), do: :video
  defp media_type(_), do: nil
end
