defmodule BrandoAdmin.Components.Form.Input.File do
  use BrandoAdmin, :live_component

  import Ecto.Changeset
  import Brando.Gettext

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
  # data upload_field, :any
  # data relation_field, :atom

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:relation_field, fn -> nil end)
     |> assign_new(:file, fn -> nil end)
     |> assign_new(:opts, fn -> [] end)
     |> assign_new(:previous_file_id, fn -> nil end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:instructions, fn -> nil end)
     |> assign_new(:placeholder, fn -> nil end)}
  end

  def update(assigns, socket) do
    relation_field = String.to_existing_atom("#{assigns.field}_id")

    file_id =
      assigns.form.source
      |> get_field(relation_field)
      |> try_force_int()

    file = get_field(assigns.form.source, assigns.field)
    file_name = (is_map(file) && file.filename) || "<unknown>"

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:file, file)
     |> assign(:file_id, file_id)
     |> assign(:file_name, file_name)
     |> assign(:upload_field, assigns.parent_uploads[assigns.field])
     |> assign(:relation_field, relation_field)}
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
        relation>
        <div>
          <div class="input-file">
            <%= if @file && @file.filename do %>
              <.file_preview
                file={@file}
                field={@field}
                relation_field={@relation_field}
                click={open_file(@myself)}
                file_name={@file_name} />
            <% else %>
              <.empty_preview
                field={@field}
                relation_field={@relation_field}
                click={open_file(@myself)} />
            <% end %>
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
            form: form,
            field: field,
            relation_field: relation_field,
            file_id: file_id,
            file: file,
            myself: myself
          }
        } = socket
      ) do
    path =
      ~r/\[(\w+)\]/
      |> Regex.scan(form.name, capture: :all_but_first)
      |> Enum.map(&(List.first(&1) |> String.to_existing_atom()))

    module = form.source.data.__struct__

    send_update(BrandoAdmin.Components.FilePicker,
      id: "file-picker",
      config_target: {"file", form.data.__struct__, field},
      event_target: myself,
      multi: false,
      selected_files: []
    )

    send_update(BrandoAdmin.Components.Form,
      id: "#{module.__naming__().singular}_form",
      action: :update_edit_file,
      edit_file: %{
        id: file_id,
        path: path,
        field: field,
        relation_field: relation_field,
        file: file
      }
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_file",
        %{"id" => selected_file_id},
        %{assigns: %{field: field}} = socket
      ) do
    {:ok, file} = Brando.Files.get_file(selected_file_id)
    module = field.form.source.data.__struct__

    send_update(BrandoAdmin.Components.Form,
      id: "#{module.__naming__().singular}_form",
      action: :update_edit_file,
      file: file
    )

    {:noreply, socket}
  end

  def empty_preview(assigns) do
    ~H"""
    <div class="file-preview-empty">
      <Input.input type={:hidden} field={@relation_field} value={""} />

      <div>
        <%= gettext "No file associated with field" %>
      </div>

      <button
        class="btn-small"
        type="button"
        phx-click={@click}
        phx-value-id={"edit-file-#{@field.id}"}><%= gettext "Add file" %></button>
    </div>
    """
  end

  @doc """
  Show preview if we have a file with a filename
  """
  def file_preview(assigns) do
    assigns = assign_new(assigns, :value, fn -> nil end)

    ~H"""
    <div class="file-preview">
      <Input.input type={:hidden} field={@relation_field} value={@value || @file.id} />
      <div class="img-placeholder">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M20 22H4a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1zm-1-2V4H5v16h14zM8 7h8v2H8V7zm0 4h8v2H8v-2zm0 4h5v2H8v-2z"/></svg>
      </div>
      <div class="file-info">
        <%= @file_name %> (<%= Brando.Utils.human_size(@file.filesize) %>)
        <button
          class="btn-small"
          type="button"
          phx-click={@click}>
          <%= gettext "Edit file" %>
        </button>
      </div>
    </div>
    """
  end
end
