defmodule Brando.Uploads.AssetIntent do
  @moduledoc """
  Validates and normalizes the browser-to-upload-manager target contract.

  The browser sends string-keyed data because the same descriptor is carried
  through JavaScript, LiveView upload state, PubSub, and finally a field/var/ref
  adapter. Keeping that wire map is useful; allowing every caller to invent its
  shape is not. This module is the single intake boundary for that map.

  An intent describes *where an uploaded asset will be used*. It deliberately
  does not contain usage overrides such as captions, crops, or playback flags;
  those belong to the context editor after selection.
  """

  @asset_types ~w(image file video)
  @kinds ~w(
    block_var
    block_var_gallery
    block_ref_picture
    block_ref_file
    block_ref_video
    block_ref_gallery
    entry_var
    entry_var_gallery
    entry_field
    entry_field_gallery
    transformer_video
    video_picker
  )

  @known_keys ~w(
    kind
    component_id
    var_key
    field
    path
    asset_type
    config_target
    deliver_topic
    folder
    folder_id
  )

  @doc """
  Normalize a client target into the canonical string-keyed wire map.
  """
  def normalize(params) when is_map(params) do
    target = Map.new(@known_keys, &{&1, get(params, &1)})

    with {:ok, kind} <- enum(target["kind"], @kinds, "target kind"),
         {:ok, asset_type} <- enum(target["asset_type"], @asset_types, "asset type"),
         :ok <- validate_compatibility(kind, asset_type),
         {:ok, topic} <- deliver_topic(target["deliver_topic"]),
         {:ok, path} <- path(target["path"]),
         :ok <- validate_destination(kind, target) do
      {:ok,
       target
       |> Map.put("kind", kind)
       |> Map.put("asset_type", asset_type)
       |> Map.put("config_target", config_target(target["config_target"]))
       |> Map.put("deliver_topic", topic)
       |> Map.put("path", path)}
    end
  rescue
    ArgumentError -> {:error, "Invalid upload configuration target"}
  end

  def normalize(_), do: {:error, "Invalid upload target"}

  defp get(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp enum(value, allowed, label) do
    if value in allowed, do: {:ok, value}, else: {:error, "Unsupported #{label}"}
  end

  defp validate_compatibility(kind, asset_type) do
    compatible? =
      case kind do
        "block_ref_picture" ->
          asset_type == "image"

        "block_ref_file" ->
          asset_type == "file"

        "block_ref_video" ->
          asset_type == "video"

        kind when kind in ["transformer_video", "video_picker"] ->
          asset_type == "video"

        kind when kind in ["block_ref_gallery", "block_var_gallery", "entry_var_gallery", "entry_field_gallery"] ->
          asset_type in ["image", "video"]

        _ ->
          true
      end

    if compatible?, do: :ok, else: {:error, "Asset type is not valid for this upload target"}
  end

  defp validate_destination(kind, target)
       when kind in ["entry_field", "entry_field_gallery"] do
    validate_existing_field(target["field"])
  end

  defp validate_destination(kind, target)
       when kind in ["block_var", "block_var_gallery", "entry_var", "entry_var_gallery"] do
    with :ok <- required_binary(target["component_id"], "component id"),
         :ok <- required_binary(target["var_key"], "var key") do
      :ok
    end
  end

  defp validate_destination(_kind, target), do: required_binary(target["component_id"], "component id")

  defp validate_existing_field(field) when is_binary(field) and field != "" do
    String.to_existing_atom(field)
    :ok
  rescue
    ArgumentError -> {:error, "Unknown upload field"}
  end

  defp validate_existing_field(_), do: {:error, "Missing upload field"}

  defp required_binary(value, _label) when is_binary(value) and value != "", do: :ok
  defp required_binary(_value, label), do: {:error, "Missing #{label}"}

  defp deliver_topic("form:" <> uuid = topic) do
    case Ecto.UUID.cast(uuid) do
      {:ok, _uuid} -> {:ok, topic}
      :error -> {:error, "Invalid upload delivery topic"}
    end
  end

  defp deliver_topic(_), do: {:error, "Invalid upload delivery topic"}

  defp path(nil), do: {:ok, []}

  defp path(path) when is_list(path) do
    Enum.reduce_while(path, {:ok, []}, fn
      segment, {:ok, acc} when is_integer(segment) and segment >= 0 ->
        {:cont, {:ok, [segment | acc]}}

      segment, {:ok, acc} when is_binary(segment) and segment != "" ->
        try do
          String.to_existing_atom(segment)
          {:cont, {:ok, [segment | acc]}}
        rescue
          ArgumentError -> {:halt, {:error, "Unknown upload path segment"}}
        end

      _segment, _acc ->
        {:halt, {:error, "Invalid upload path"}}
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp path(_), do: {:error, "Invalid upload path"}

  defp config_target(nil), do: "default"
  defp config_target(target), do: Brando.Assets.ConfigTarget.serialize(target)
end
