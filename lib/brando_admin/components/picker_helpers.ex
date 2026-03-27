defmodule BrandoAdmin.Components.PickerHelpers do
  @moduledoc """
  Shared helpers for asset picker components (ImagePicker, VideoPicker).

  Provides folder navigation event handlers, organize selection helpers,
  and ID parsing utilities.

  ## Usage

      use BrandoAdmin.Components.PickerHelpers

  ## Required callbacks

  Each picker must implement:

    * `assign_folder_state(socket, requested_folder)` — picker-specific folder filtering and streaming
    * `push_selection_state(socket)` — push selection state to JS hooks
    * `on_folder_change(socket)` — called after `set_current_folder` for picker-specific post-actions
  """

  alias BrandoAdmin.Images.FolderBrowser

  defmacro __using__(_opts) do
    quote do
      # -- Folder navigation event handlers --

      def handle_event("go_root", _, socket) do
        {:noreply, set_current_folder(socket, "")}
      end

      def handle_event("go_folder", %{"folder" => folder}, socket) do
        {:noreply, set_current_folder(socket, folder)}
      end

      def handle_event("go_parent_folder", _, %{assigns: %{current_folder: ""}} = socket) do
        {:noreply, socket}
      end

      def handle_event("go_parent_folder", _, socket) do
        parent =
          socket.assigns.current_folder
          |> String.split("/", trim: true)
          |> Enum.drop(-1)
          |> Enum.join("/")

        {:noreply, set_current_folder(socket, parent)}
      end

      def handle_event("go_recent_folder", %{"folder" => folder}, socket) do
        relative = FolderBrowser.relative_folder(folder, socket.assigns.upload_root)
        {:noreply, set_current_folder(socket, relative)}
      end

      def handle_event("create_folder", %{"folder" => %{"name" => folder_name}}, socket) do
        cleaned = FolderBrowser.normalize_folder(folder_name)

        socket =
          if cleaned do
            current = socket.assigns.current_folder
            relative = if current in ["", nil], do: cleaned, else: Path.join(current, cleaned)
            custom_folders = Enum.uniq([relative | socket.assigns.custom_folders])

            case FolderBrowser.create_folder(relative, socket.assigns.upload_root) do
              {:ok, _folder} ->
                socket
                |> assign(:custom_folders, custom_folders)
                |> set_current_folder(relative)
                |> assign(:show_new_folder_form, false)

              {:error, _reason} ->
                socket
            end
          else
            socket
          end

        {:noreply, assign(socket, :new_folder, "")}
      end

      def handle_event("show_new_folder_form", _, socket) do
        {:noreply, assign(socket, :show_new_folder_form, true)}
      end

      def handle_event("cancel_new_folder_form", _, socket) do
        {:noreply,
         socket
         |> assign(:new_folder, "")
         |> assign(:show_new_folder_form, false)}
      end

      # -- Folder state helpers --

      defp set_current_folder(socket, folder) do
        folder = FolderBrowser.normalize_folder(folder) || ""

        custom_folders =
          if folder in ["", nil] do
            socket.assigns.custom_folders
          else
            Enum.uniq([folder | socket.assigns.custom_folders])
          end

        socket
        |> assign(:custom_folders, custom_folders)
        |> assign(:current_folder, folder)
        |> assign(:organize_selected, [])
        |> assign(:last_organize_selected_id, nil)
        |> assign_folder_state(folder)
        |> remember_folder(FolderBrowser.absolute_folder(folder, socket.assigns.upload_root))
        |> on_folder_change()
      end

      defp remember_folder(socket, nil), do: socket

      defp remember_folder(socket, folder) do
        recent_folders =
          socket.assigns.recent_folders
          |> FolderBrowser.push_recent_folder(folder)

        socket
        |> assign(:recent_folders, recent_folders)
        |> assign_folder_state(socket.assigns.current_folder)
      end

      defp folder_label_for_display(folder, upload_root) do
        case FolderBrowser.relative_folder(folder, upload_root) do
          relative when relative in [nil, ""] -> root_label(upload_root)
          relative -> relative
        end
      end

      defp root_label(upload_root) do
        case FolderBrowser.normalize_folder(upload_root) do
          nil -> "Root"
          root -> root
        end
      end

      defp folder_under_root?(folder, nil), do: not is_nil(FolderBrowser.normalize_folder(folder))

      defp folder_under_root?(folder, root) do
        normalized_folder = FolderBrowser.normalize_folder(folder)
        normalized_root = FolderBrowser.normalize_folder(root)

        normalized_folder == normalized_root ||
          String.starts_with?(normalized_folder || "", (normalized_root || "") <> "/")
      end

      # -- Organize selection helpers --

      defp organize_select_toggle(socket, id) do
        selected = socket.assigns.organize_selected

        updated =
          if id in selected,
            do: List.delete(selected, id),
            else: Enum.uniq([id | selected])

        last_id = if updated == [], do: nil, else: id

        socket
        |> assign(:organize_selected, updated)
        |> assign(:last_organize_selected_id, last_id)
      end

      defp organize_select_range(socket, id) do
        selected = socket.assigns.organize_selected
        anchor = socket.assigns.last_organize_selected_id
        visible_ids = socket.assigns.visible_item_ids
        range_ids = ids_between(visible_ids, anchor, id)

        updated =
          if range_ids == [],
            do: Enum.uniq([id | selected]),
            else: Enum.uniq(selected ++ range_ids)

        socket
        |> assign(:organize_selected, updated)
        |> assign(:last_organize_selected_id, id)
      end

      defp ids_between(_ids, nil, _to), do: []

      defp ids_between(ids, from, to) do
        from_idx = Enum.find_index(ids, &(&1 == from))
        to_idx = Enum.find_index(ids, &(&1 == to))

        if is_integer(from_idx) and is_integer(to_idx) do
          start_idx = min(from_idx, to_idx)
          end_idx = max(from_idx, to_idx)
          Enum.slice(ids, start_idx..end_idx)
        else
          []
        end
      end

      # -- ID/parse helpers --

      defp normalize_item_id(id) when is_integer(id), do: id

      defp normalize_item_id(id) when is_binary(id) do
        case Integer.parse(id) do
          {parsed, ""} -> parsed
          _ -> id
        end
      end

      defp normalize_item_id(%{id: id}), do: normalize_item_id(id)
      defp normalize_item_id(%{"id" => id}), do: normalize_item_id(id)
      defp normalize_item_id(id), do: id

      defp same_item_id?(left, right), do: normalize_item_id(left) == normalize_item_id(right)

      defp parse_item_id(id) when is_integer(id), do: {:ok, id}

      defp parse_item_id(id) when is_binary(id) do
        case Integer.parse(id) do
          {parsed, ""} -> {:ok, parsed}
          _ -> :error
        end
      end

      defp parse_item_id(_), do: :error

      defp parse_selected_ids(ids) when is_list(ids) do
        ids
        |> Enum.map(&parse_int/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
      end

      defp parse_selected_ids(ids) when is_binary(ids) do
        case Jason.decode(ids) do
          {:ok, parsed} -> parse_selected_ids(parsed)
          _ -> []
        end
      end

      defp parse_selected_ids(_), do: []

      defp parse_int(value) when is_integer(value), do: value

      defp parse_int(value) when is_binary(value) do
        case Integer.parse(value) do
          {id, ""} -> id
          _ -> nil
        end
      end

      defp parse_int(_), do: nil

      defp truthy?(value) when value in [true, "true", "1", 1], do: true
      defp truthy?(_value), do: false

      defp normalize_upload_name(nil), do: nil
      defp normalize_upload_name(name) when is_atom(name), do: Atom.to_string(name)
      defp normalize_upload_name(name) when is_binary(name), do: name
      defp normalize_upload_name(_), do: nil

      defp parse_nonnegative_int(value, _default) when is_integer(value), do: max(value, 0)

      defp parse_nonnegative_int(value, default) when is_binary(value) do
        case Integer.parse(value) do
          {parsed, ""} -> max(parsed, 0)
          _ -> default
        end
      end

      defp parse_nonnegative_int(_, default), do: default

      # Default callback stubs — each picker MUST override these
      defp assign_folder_state(socket, _requested_folder), do: socket
      defp push_selection_state(socket), do: socket
      defp on_folder_change(socket), do: socket

      defoverridable assign_folder_state: 2,
                     push_selection_state: 1,
                     on_folder_change: 1
    end
  end
end
