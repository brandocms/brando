defmodule BrandoAdmin.LiveView.AssetListHelpers do
  @moduledoc """
  Shared folder browsing and utility functions for asset list LiveViews
  (ImageListLive, FileListLive, VideoListLive).
  """

  import Ecto.Query, only: [from: 2]

  alias BrandoAdmin.Images.FolderBrowser

  @doc "Navigates to the parent folder by patching the URL filter."
  def go_parent(%{assigns: %{current_folder: ""}} = socket), do: socket

  def go_parent(socket) do
    parent =
      socket.assigns.current_folder
      |> String.split("/", trim: true)
      |> Enum.drop(-1)
      |> Enum.join("/")

    folder_id = FolderBrowser.folder_id_for(parent, socket.assigns.upload_root)
    patch_folder_filter(socket, folder_id)
  end

  @doc "Creates a new folder and navigates to it."
  def create_folder(socket, folder_name) do
    cleaned = FolderBrowser.normalize_folder(folder_name)

    if cleaned do
      absolute =
        if socket.assigns.current_folder in ["", nil] do
          cleaned
        else
          Path.join(socket.assigns.current_folder, cleaned)
        end
        |> FolderBrowser.normalize_folder()

      case FolderBrowser.create_folder(absolute, socket.assigns.upload_root) do
        {:ok, _folder} ->
          folder_id = FolderBrowser.folder_id_for(absolute, socket.assigns.upload_root)

          socket
          |> Phoenix.Component.assign(:custom_folders, Enum.uniq([absolute | socket.assigns.custom_folders]))
          |> Phoenix.Component.assign(:show_new_folder_form, false)
          |> Phoenix.Component.assign(:new_folder, "")
          |> patch_folder_filter(folder_id)

        {:error, _reason} ->
          socket
      end
    else
      socket
    end
  end

  @doc "Patches the URL to filter by the given folder."
  def patch_folder_filter(socket, folder) do
    uri = socket.assigns.uri
    current_params = URI.decode_query(uri.query || "")
    folder_filter = if is_nil(folder), do: "root", else: to_string(folder)

    new_params =
      current_params
      |> Map.drop(["filter:path", "page"])
      |> Map.put("filter:folder_id", folder_filter)
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    to =
      if new_params == "" do
        uri.path
      else
        uri.path <> "?" <> new_params
      end

    Phoenix.LiveView.push_patch(socket, to: to)
  end

  @doc "Resolves a folder filter parameter to a relative folder path."
  def resolve_current_folder(folder_filter, upload_root) do
    cond do
      is_nil(folder_filter) or folder_filter in ["", "root"] ->
        ""

      is_integer(folder_filter) ->
        FolderBrowser.folder_path_for_id(folder_filter, upload_root)

      is_binary(folder_filter) ->
        case Integer.parse(folder_filter) do
          {folder_id, ""} ->
            FolderBrowser.folder_path_for_id(folder_id, upload_root)

          _ ->
            FolderBrowser.relative_folder(folder_filter, upload_root) || ""
        end

      true ->
        ""
    end
  end

  @doc "Parses selected entry IDs from various input formats."
  def parse_selected_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_int/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  def parse_selected_ids(ids) when is_binary(ids) do
    case Jason.decode(ids) do
      {:ok, parsed} -> parse_selected_ids(parsed)
      _ -> []
    end
  end

  def parse_selected_ids(_), do: []

  @doc "Checks whether a folder path is within the upload root."
  def folder_under_root?(folder, upload_root) do
    normalized_folder = FolderBrowser.normalize_folder(folder)
    normalized_root = FolderBrowser.normalize_folder(upload_root)

    normalized_folder == normalized_root ||
      String.starts_with?(normalized_folder || "", (normalized_root || "") <> "/")
  end

  @doc "Moves entries to a target folder by updating their folder_id."
  def move_entries_to_folder(schema_module, ids, folder_id) when is_list(ids) do
    timestamp = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(entry in schema_module, where: entry.id in ^ids)
    |> Brando.Repo.update_all(set: [folder_id: folder_id, updated_at: timestamp])
  end

  @doc "Broadcasts a listing update for the given schema."
  def update_list_entries(schema) do
    topic = "brando:listing:content_listing_#{schema}_default"
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  @doc "Returns the listing component ID for a schema."
  def listing_id(schema), do: "content_listing_#{schema}_default"

  @doc "Adds default folder filter to listing params."
  def list_params(params) when is_map(params) do
    Map.put_new(params, "filter:folder_id", "root")
  end

  @doc "Toggles children row visibility. Shared between ChildrenButton and Nav."
  def toggle_children_row(socket) do
    %{fields: child_fields, singular: singular, entry: %{id: id}} = socket.assigns
    row_id = "list-row-#{singular}-#{id}"

    Phoenix.LiveView.send_update(BrandoAdmin.Components.Content.List.Row,
      id: row_id,
      show_children: !socket.assigns.active,
      child_fields: child_fields
    )

    Phoenix.Component.assign(socket, :active, !socket.assigns.active)
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
