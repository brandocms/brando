defmodule BrandoAdmin.LiveView.AssetListHelpers do
  @moduledoc """
  Shared folder browsing and utility functions for asset list LiveViews
  (ImageListLive, FileListLive, VideoListLive).
  """

  import Ecto.Query, only: [from: 2]

  require Phoenix.LiveView

  alias Brando.Authorization.Boundary
  alias BrandoAdmin.Components.Assets.SortByUse
  alias BrandoAdmin.Images.FolderBrowser
  alias BrandoAdmin.Media.Sweep
  alias Phoenix.Component

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
          |> Component.assign(:custom_folders, Enum.uniq([absolute | socket.assigns.custom_folders]))
          |> Component.assign(:show_new_folder_form, false)
          |> Component.assign(:new_folder, "")
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
      is_nil(folder_filter) or folder_filter in ["", "root", "all"] ->
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
    topic = Brando.Tenant.Topic.scoped("brando:listing:content_listing_#{schema}_default")
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  @doc "Returns the listing component ID for a schema."
  def listing_id(schema), do: "content_listing_#{schema}_default"

  @doc """
  Adds default folder filter to listing params.

  `filter:folder_id=all` lists every library folder and the root, leaving out
  hidden folders as the library always does: the command palette's "Images
  matching …" links search the whole library that way.
  """
  def list_params(params, root_folder_ids \\ []) when is_map(params) do
    case Map.get(params, "filter:folder_id") do
      "all" -> Map.put(params, "filter:folder_id", {:library, Brando.Media.Folders.hidden_folder_ids()})
      folder when folder in [nil, "", "root"] -> Map.put(params, "filter:folder_id", {:root, root_folder_ids})
      _ -> params
    end
  end

  @all_folders_filters ~w(path filename unused)

  @doc """
  Marks the library as listing all folders (`filter:folder_id=all`) and puts
  the number of assets it lists in `count_key`, for the folder header. `list`
  is the context's list function, such as `&Brando.Images.list_images/1`.
  """
  def assign_all_folders(socket, params, list, count_key) do
    if Map.get(params, "filter:folder_id") == "all" do
      filter =
        params
        |> list_params()
        |> Enum.flat_map(fn
          {"filter:folder_id", value} ->
            [{:folder_id, value}]

          {"filter:" <> key, value} when key in @all_folders_filters and value not in [nil, ""] ->
            [{String.to_existing_atom(key), value}]

          _ ->
            []
        end)
        |> Map.new()

      {:ok, entries} = list.(%{filter: filter, select: [:id]})

      socket
      |> Component.assign(:all_folders?, true)
      |> Component.assign(count_key, length(entries))
    else
      Component.assign(socket, :all_folders?, false)
    end
  end

  # "Sort by use" and "Delete unused" (see `BrandoAdmin.Media.Sweep` and
  # `BrandoAdmin.Components.Assets.SortByUse`). The LiveView keeps `:sweep`
  # (the open preview) and `:sweep_result` (what Undo puts back), and redraws
  # its folder state after each call.

  @doc "Opens the preview of sorting the current folder's `asset_type` assets."
  def open_sweep(socket, asset_type) do
    folder_id = FolderBrowser.folder_id_for(socket.assigns.current_folder, socket.assigns.upload_root)

    case Sweep.plan(asset_type, folder_id) do
      {:ok, plan} -> Component.assign(socket, :sweep, %{plan: plan, samples: Sweep.samples(plan)})
      {:error, _} -> socket
    end
  end

  @doc """
  Moves what the preview's form keeps (`include[key]`, `name[key]`) and keeps
  the result for Undo. Without an open preview, nothing happens.
  """
  def apply_sweep(%{assigns: %{sweep: %{plan: plan}}} = socket, params) do
    included = params |> Map.get("include", %{}) |> Enum.filter(&(elem(&1, 1) == "true")) |> Enum.map(&elem(&1, 0))
    {:ok, result} = Sweep.apply(plan, only: included, names: Map.get(params, "name", %{}))
    update_list_entries(socket.assigns.schema)

    socket
    |> Component.assign(:sweep, nil)
    |> Component.assign(:sweep_result, if(result.moved > 0, do: result))
  end

  def apply_sweep(socket, _params), do: socket

  @doc "Puts back what the last sort moved, with a toast."
  def undo_sweep(%{assigns: %{sweep_result: %{asset_type: asset_type} = result}} = socket) do
    {:ok, count} = Sweep.undo(result)
    update_list_entries(socket.assigns.schema)
    send(self(), {:toast, SortByUse.moved_back(asset_type, count)})
    Component.assign(socket, :sweep_result, nil)
  end

  def undo_sweep(socket), do: socket

  @doc "Whether the listing's \"Not in use\" filter is on."
  def unused_filter?(params), do: Map.get(params || %{}, "filter:unused") in ["true", true]

  @doc """
  The filter the library's listing applies for `params`: every `filter:`
  parameter, as `Content.List` passes them on, with the folder as
  `list_params/2` resolves it.
  """
  def listing_filter(params, root_folder_ids) do
    params
    |> list_params(root_folder_ids)
    |> Enum.flat_map(fn
      {"filter:" <> key, value} ->
        try do
          [{String.to_existing_atom(key), value}]
        rescue
          ArgumentError -> []
        end

      _ ->
        []
    end)
    |> Map.new()
  end

  @doc """
  With the "Not in use" filter on, keeps the ids of the unused assets the
  listing shows (`:unused_ids`) and their number (`:unused_count`): what the
  Delete unused confirmation offers. `list` is the context's list function.
  """
  def assign_unused_count(socket, params, list) do
    ids = if unused_filter?(params), do: listed_ids(socket, params, list), else: []

    socket
    |> Component.assign(:unused_ids, ids)
    |> Component.assign(:unused_count, length(ids))
  end

  @doc """
  Recounts what the header shows after a change, as `handle_params` does:
  the unused assets (`assign_unused_count/3`) and, in the "All folders"
  view, everything it lists (`assign_all_folders/4`).
  """
  def refresh_counts(socket, list, count_key) do
    params = socket.assigns[:params] || %{}

    socket
    |> assign_unused_count(params, list)
    |> assign_all_folders(params, list, count_key)
  end

  @doc """
  Deletes the unused assets the confirmation offered (`:unused_ids`) that
  the listing still shows as unused: one used or moved away since stays, and
  one added since is not deleted unseen. Runs in the background
  (`:delete_unused`); the LiveView passes the result to
  `finish_delete_unused/2` from its `handle_async/3`.

  Images are soft deleted in one go; videos and files one by one through
  their delete mutation, as the listing's Delete does, which checks the
  user's permission and removes a video's remote copy when its provider
  deletes on delete.
  """
  def delete_unused(%{assigns: %{deleting_unused?: true}} = socket, _asset_type, _list), do: socket

  def delete_unused(socket, asset_type, list) do
    still_unused = MapSet.new(listed_ids(socket, socket.assigns.params, list))
    ids = Enum.filter(socket.assigns.unused_ids, &MapSet.member?(still_unused, &1))
    user = socket.assigns.current_user

    # The task works as this process would: in its site and environment,
    # with its authorization scope, and in the E2E server's test sandbox.
    scope = Boundary.current_scope()
    parent = self()

    work =
      Brando.Tenant.capture_context(fn ->
        if Application.get_env(Brando.config(:otp_app), :sql_sandbox),
          do: Ecto.Adapters.SQL.Sandbox.allow(Brando.Repo.repo(), parent, self())

        Boundary.with_scope(scope, fn -> {asset_type, delete_assets(asset_type, ids, user)} end)
      end)

    socket
    |> Component.assign(:deleting_unused?, true)
    |> Phoenix.LiveView.start_async(:delete_unused, work)
  end

  @doc "Reports what `delete_unused/3` did and refreshes the listing."
  def finish_delete_unused(socket, result) do
    message =
      case result do
        {:ok, {asset_type, count}} -> SortByUse.deleted(asset_type, count)
        {:exit, _reason} -> SortByUse.delete_failed()
      end

    update_list_entries(socket.assigns.schema)
    send(self(), {:toast, message})
    Component.assign(socket, :deleting_unused?, false)
  end

  defp delete_assets(:image, ids, _user) do
    Brando.Images.delete_images(ids)
    length(ids)
  end

  defp delete_assets(:video, ids, user), do: Enum.count(ids, &match?({:ok, _}, Brando.Videos.delete_video(&1, user)))
  defp delete_assets(:file, ids, user), do: Enum.count(ids, &match?({:ok, _}, Brando.Files.delete_file(&1, user)))

  defp listed_ids(socket, params, list) do
    {:ok, entries} = list.(%{filter: listing_filter(params, socket.assigns.root_folder_ids), select: [:id]})
    Enum.map(entries, & &1.id)
  end

  @doc "Toggles children row visibility for the navigation component and legacy child buttons."
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
