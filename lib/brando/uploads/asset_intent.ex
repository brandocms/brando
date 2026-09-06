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
    transformer_image
    transformer_video
    video_picker
    file_replace
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
    ref
    file_id
  )

  # Opaque client-generated correlation token. It is echoed back to the owning
  # component so a delivery can be matched to the placeholder the client
  # registered for that file. Never interpolated into a query or an atom, but
  # kept to a conservative charset since it does reach the DOM as an id.
  @ref_format ~r/^[A-Za-z0-9_-]{1,64}$/

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
         {:ok, ref} <- ref(target["ref"]),
         :ok <- validate_destination(kind, target) do
      {:ok,
       target
       |> Map.put("kind", kind)
       |> Map.put("asset_type", asset_type)
       |> Map.put("config_target", config_target(target["config_target"]))
       |> Map.put("deliver_topic", topic)
       |> Map.put("path", path)
       |> Map.put("ref", ref)}
    end
  rescue
    ArgumentError -> {:error, "Invalid upload configuration target"}
  end

  def normalize(_), do: {:error, "Invalid upload target"}

  # Targets arrive with string keys from the browser and atom keys from
  # server-side callers. `Map.get/3`'s default is evaluated eagerly, so the old
  # one-liner minted-or-looked-up an atom on EVERY call, including the common
  # one where the string key is already there — safe only because these
  # particular atoms happen to exist. Only reach for the atom if we have to.
  defp get(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, String.to_existing_atom(key))
    end
  rescue
    # An unknown key is simply absent; `normalize/1` reports it as missing.
    ArgumentError -> nil
  end

  defp enum(value, allowed, label) do
    if value in allowed, do: {:ok, value}, else: {:error, "Unsupported #{label}"}
  end

  defp validate_compatibility(kind, asset_type) do
    compatible? =
      case kind do
        "block_ref_picture" ->
          asset_type == "image"

        kind when kind in ["block_ref_file", "file_replace"] ->
          asset_type == "file"

        "block_ref_video" ->
          asset_type == "video"

        "transformer_image" ->
          asset_type == "image"

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

  defp validate_destination("file_replace", target) do
    case Ecto.Type.cast(:id, target["file_id"]) do
      {:ok, id} when is_integer(id) and id > 0 -> :ok
      _ -> {:error, "Invalid replacement file id"}
    end
  end

  defp validate_destination(kind, target)
       when kind in ["block_var", "block_var_gallery", "entry_var", "entry_var_gallery"] do
    with :ok <- required_binary(target["component_id"], "component id"),
         do: required_binary(target["var_key"], "var key")
  end

  defp validate_destination(_kind, target), do: required_binary(target["component_id"], "component id")

  defp validate_existing_field(field) when is_binary(field) and field != "" do
    _existing_field = String.to_existing_atom(field)
    :ok
  rescue
    ArgumentError -> {:error, "Unknown upload field"}
  end

  defp validate_existing_field(_), do: {:error, "Missing upload field"}

  defp required_binary(value, _label) when is_binary(value) and value != "", do: :ok
  defp required_binary(_value, label), do: {:error, "Missing #{label}"}

  defp deliver_topic(topic), do: validate_deliver_topic(topic)

  @doc """
  Validate an asset-delivery topic.

  Public because the form claims its own topic from the client now (so it
  survives a remount — see `BrandoAdmin.Components.Form`), and the *subscribe*
  side has to apply exactly the same rule as the intake side. A client that
  could name any topic could subscribe its form to another form's deliveries.
  """
  def validate_deliver_topic("form:" <> uuid = topic) do
    case Ecto.UUID.cast(uuid) do
      {:ok, _uuid} -> {:ok, topic}
      :error -> {:error, "Invalid upload delivery topic"}
    end
  end

  def validate_deliver_topic(_), do: {:error, "Invalid upload delivery topic"}

  defp path(nil), do: {:ok, []}

  defp path(path) when is_list(path) do
    Enum.reduce_while(path, {:ok, []}, fn
      segment, {:ok, acc} when is_integer(segment) and segment >= 0 ->
        {:cont, {:ok, [segment | acc]}}

      segment, {:ok, acc} when is_binary(segment) and segment != "" ->
        try do
          _existing_segment = String.to_existing_atom(segment)
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

  defp ref(nil), do: {:ok, nil}
  defp ref(""), do: {:ok, nil}

  defp ref(ref) when is_binary(ref) do
    if Regex.match?(@ref_format, ref), do: {:ok, ref}, else: {:error, "Invalid upload ref"}
  end

  defp ref(_), do: {:error, "Invalid upload ref"}

  defp config_target(nil), do: "default"
  defp config_target(target), do: Brando.Assets.ConfigTarget.serialize(target)
end
