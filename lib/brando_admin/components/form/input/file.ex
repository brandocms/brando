defmodule BrandoAdmin.Components.Form.Input.File do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data show_edit_meta, :boolean, default: false
  # data focal, :any
  # data file, :any
  # data file_name, :any
  # data relation_field, FormField

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:relation_field, fn -> nil end)
     |> assign_new(:file, fn -> nil end)
     |> assign_new(:opts, fn -> [] end)
     |> assign_new(:previous_file_id, fn -> nil end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:instructions, fn -> nil end)
     |> assign_new(:path, fn -> [] end)
     |> assign_new(:form_id, fn -> nil end)
     |> assign_new(:placeholder, fn -> nil end)}
  end

  def update(assigns, socket) do
    relation_field_atom = String.to_existing_atom("#{assigns.field.field}_id")
    relation_field = assigns.field.form[relation_field_atom]
    changeset = assigns.field.form.source
    file_from_changeset = get_field(changeset, assigns.field.field)

    file_id =
      changeset
      |> get_field(relation_field_atom)
      |> try_force_int()

    file = resolve_file(file_from_changeset, file_id)
    path = Brando.Utils.get_path_from_field_name(assigns.field.form.name)
    module_from_form = changeset.data.__struct__

    module =
      if path == [] do
        module_from_form
      else
        Brando.Utils.get_parent_module_from_field_name(assigns.field.form.name, module_from_form)
      end

    form_id = "#{module.__naming__().singular}_form"

    file_name =
      cond do
        is_map(file) && !is_struct(file, Ecto.Association.NotLoaded) ->
          file.filename

        is_struct(file, Ecto.Changeset) ->
          Ecto.Changeset.get_field(file, :filename)

        true ->
          "<unknown>"
      end

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:file, file)
     |> assign(:file_id, file_id)
     |> assign(:file_name, file_name)
     |> assign(:relation_field, relation_field)
     |> assign(:path, path)
     |> assign(:form_id, form_id)
     |> assign(:editable, Keyword.get(assigns.opts, :editable, true))}
  end

  defp resolve_file(%Brando.Files.File{} = file, _file_id), do: file
  defp resolve_file(%Ecto.Changeset{} = changeset, _file_id), do: apply_changes(changeset)

  defp resolve_file(%Ecto.Association.NotLoaded{}, file_id), do: fetch_file(file_id)
  defp resolve_file(nil, file_id), do: fetch_file(file_id)
  defp resolve_file(file, _file_id), do: file

  defp fetch_file(nil), do: nil

  defp fetch_file(file_id) do
    case Brando.Files.get_file(file_id) do
      {:ok, file} -> file
      _ -> nil
    end
  end

  def try_force_int(str) when is_binary(str), do: String.to_integer(str)
  def try_force_int(int) when is_integer(int), do: int
  def try_force_int(val), do: val

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}
        relation
      >
        <div>
          <div class="input-file">
            <.file_preview
              file={@file}
              field={@field}
              relation_field={@relation_field}
              click={@editable && open_file(@myself)}
              file_name={@file_name}
              editable={@editable}
              compact={@compact}
            />
          </div>
        </div>
      </Form.field_base>
    </div>
    """
  end

  def open_file(js \\ %JS{}, target) do
    js
    |> JS.push("open_file", target: target)
    |> toggle_drawer("#file-drawer")
  end

  def handle_event(
        "open_file",
        _,
        %{
          assigns: %{
            field: field,
            relation_field: relation_field,
            file_id: file_id,
            file: file,
            myself: myself,
            path: path,
            form_id: form_id
          }
        } = socket
      ) do
    send_update(BrandoAdmin.Components.FilePicker,
      id: "file-picker",
      config_target: {"file", field.form.data.__struct__, field.field},
      event_target: myself,
      multi: false,
      selected_files: if(file_id, do: [file_id], else: [])
    )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_edit_file,
      edit_file: %{
        id: file_id,
        path: path,
        field: field.field,
        relation_field: relation_field,
        schema: field.form.data.__struct__,
        file: file
      }
    )

    {:noreply, socket}
  end

  def handle_event("select_file", %{"id" => selected_file_id}, socket) do
    {:ok, file} = Brando.Files.get_file(selected_file_id)

    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      action: :update_edit_file,
      file: file
    )

    {:noreply, socket}
  end

  @doc """
  Show preview if we have a file with a filename
  """
  def file_preview(assigns) do
    assigns =
      assigns
      |> assign_new(:value, fn -> nil end)
      |> assign_new(:publish, fn -> false end)
      |> assign_new(:editable, fn -> true end)
      |> assign_new(:compact, fn -> false end)
      |> assign_new(:file_id, fn ->
        if assigns[:file] do
          assigns[:file].id
        end
      end)

    ~H"""
    <div class="file-preview">
      <Input.input
        :if={@editable}
        type={:hidden}
        field={@relation_field}
        value={@value || @file_id}
        publish={@publish}
      />

      <%= if @file do %>
        <div class="img-placeholder">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M20 22H4a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1zm-1-2V4H5v16h14zM8 7h8v2H8V7zm0 4h8v2H8v-2zm0 4h5v2H8v-2z" />
          </svg>
        </div>
        <div :if={@editable} class="file-info">
          <div>
            <div class="name">
              {@file_name} ({Brando.Utils.human_size(@file.filesize)})
            </div>
            <div :if={!@compact} class="updated">
              {gettext("Last updated")}: {Brando.Utils.Datetime.format_datetime(@file.updated_at, "%d/%m/%y, %H:%M")}
            </div>
          </div>
          <button class="btn tiny mt-1" type="button" phx-click={@click}>
            {gettext("Edit file")}
          </button>
        </div>
      <% else %>
        <div class="img-placeholder">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M20 22H4a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1zm-1-2V4H5v16h14zM8 7h8v2H8V7zm0 4h8v2H8v-2zm0 4h5v2H8v-2z" />
          </svg>
        </div>
        <div :if={@editable} class="file-info">
          <span :if={!@compact}>{gettext("No file associated with field")}</span>
          <button class="tiny" type="button" phx-click={@click} phx-value-id={"edit-file-#{@field.id}"}>
            {gettext("Add file")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
