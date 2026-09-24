defmodule Brando.Content.Transfer.Ownership do
  @moduledoc false
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

      # The copy holds the same images and videos, so gallery overrides (keyed
      # by media) carry over unchanged.
      gallery =
        %Brando.Galleries.Gallery{}
        |> Brando.Galleries.Gallery.changeset(
          %{"config_target" => original["config_target"], "gallery_objects" => objects},
          actor
        )
        |> Repo.insert!()

      {value |> Map.delete("gallery") |> Map.put("gallery_id", gallery.id), available}
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

  def retained_slots(%{"type" => "slot", "uid" => uid} = params),
    do: [uid | retained_slots(Map.delete(params, "type"))]

  def retained_slots(params) when is_map(params), do: Enum.flat_map(Map.values(params), &retained_slots/1)
  def retained_slots(params) when is_list(params), do: Enum.flat_map(params, &retained_slots/1)
  def retained_slots(_), do: []
end
