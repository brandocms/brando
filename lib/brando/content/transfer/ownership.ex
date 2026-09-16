defmodule Brando.Content.Transfer.Ownership do
  @moduledoc false
  alias Brando.Content.Transfer.Error
  alias Brando.Repo

  # A newly inserted bundle gallery can be claimed once. Existing galleries
  # (including module defaults and recovery snapshots) always need a new owner.
  def galleries(params, actor, available \\ MapSet.new()), do: copy(params, actor, available)

  defp copy(%{"gallery_id" => id} = value, actor, available) when not is_nil(id) do
    if MapSet.member?(available, id) do
      {Map.delete(value, "gallery"), MapSet.delete(available, id)}
    else
      original =
        value["gallery"] ||
          Brando.Content.Transfer.Dependencies.load!("gallery", id, actor)
          |> Repo.preload(:gallery_objects)
          |> Brando.Drafts.Params.snapshot()

      objects = Enum.map(original["gallery_objects"], &Map.take(&1, ~w(image_id video_id config sequence)))

      Enum.each(objects, fn object ->
        if object["image_id"], do: Brando.Content.Transfer.Dependencies.load!("image", object["image_id"], actor)
        if object["video_id"], do: Brando.Content.Transfer.Dependencies.load!("video", object["video_id"], actor)
      end)

      Brando.Content.Transfer.Catalog.authorize!(actor, :create, Brando.Galleries.Gallery)

      gallery =
        %Brando.Galleries.Gallery{}
        |> Brando.Galleries.Gallery.changeset(
          %{"config_target" => original["config_target"], "gallery_objects" => objects},
          actor
        )
        |> Repo.insert!()
        |> Repo.preload(:gallery_objects)

      mapping =
        Enum.zip(original["gallery_objects"], gallery.gallery_objects)
        |> Map.new(fn {old, new} -> {to_string(old["id"]), to_string(new.id)} end)

      {value |> Map.delete("gallery") |> Map.put("gallery_id", gallery.id) |> remap_objects(mapping), available}
    end
  end

  defp copy(value, actor, seen) when is_map(value) do
    {pairs, seen} =
      Enum.map_reduce(value, seen, fn {key, value}, seen ->
        {value, seen} = copy(value, actor, seen)
        {{key, value}, seen}
      end)

    {Map.new(pairs), seen}
  end

  defp copy(value, actor, seen) when is_list(value), do: Enum.map_reduce(value, seen, &copy(&1, actor, &2))
  defp copy(value, _, seen), do: {value, seen}

  defp remap_objects(map, mapping) when is_map(map),
    do:
      Map.new(map, fn
        {"object_id", id} ->
          {"object_id",
           Map.get(mapping, to_string(id)) || Error.fail!("A gallery override references an unknown placement.")}

        {key, value} ->
          {key, remap_objects(value, mapping)}
      end)

  defp remap_objects(list, mapping) when is_list(list), do: Enum.map(list, &remap_objects(&1, mapping))
  defp remap_objects(value, _), do: value

  def retained_slots(%{"type" => "slot", "uid" => uid} = params),
    do: [uid | retained_slots(Map.delete(params, "type"))]

  def retained_slots(params) when is_map(params), do: Enum.flat_map(Map.values(params), &retained_slots/1)
  def retained_slots(params) when is_list(params), do: Enum.flat_map(params, &retained_slots/1)
  def retained_slots(_), do: []
end
