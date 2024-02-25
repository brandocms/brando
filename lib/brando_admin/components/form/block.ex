defmodule BrandoAdmin.Components.Form.Block do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Input
  # import Brando.Gettext

  def update(assigns, socket) do
    changeset = assigns.form.source

    socket =
      socket
      |> assign(assigns)
      |> assign(:form_has_changes, changeset.valid? && changeset.changes !== %{})
      |> assign_new(:deleted, fn -> false end)
      |> maybe_assign_children()

    {:ok, socket}
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    socket
    |> stream(:children_forms, children_forms)
  end

  def maybe_assign_children(
        %{assigns: %{type: :module, multi: true, children: children}} = socket
      ) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    socket
    |> stream(:children_forms, children_forms)
  end

  def maybe_assign_children(socket) do
    socket
  end

  # <input type="hidden" name="list[notifications_order][]" value={f_nested.index} />
  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div>
      <h2>MODULE MULTI</h2>
      <%= render_slot(@inner_block) %>
      <div class="form">
        <.form
          for={@form}
          class="mt-1"
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-submit="save_block"
          phx-target={@myself}
        >
          <%= if @belongs_to == :root do %>
            <.inputs_for :let={block} field={@form[:block]}>
              <div class="brando-input">
                <Input.text field={block[:uid]} label="UID" />
                <Input.text field={block[:description]} label="Description" />
              </div>
            </.inputs_for>
          <% else %>
            <div class="brando-input">
              <Input.text field={@form[:uid]} label="UID" />
              <Input.text field={@form[:description]} label="Description" />
            </div>
          <% end %>
        </.form>
      </div>

      <div
        id="blocks-children"
        phx-update="stream"
        phx-hook="Brando.SortableBlocks"
        data-sortable-id={"sortable-blocks-multi-#{@uid}"}
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <div
          :for={{id, child_block_form} <- @streams.children_forms}
          id={id}
          data-id={child_block_form.data.id}
          data-uid={child_block_form.data.uid}
          data-parent_id={child_block_form.data.parent_id}
          class="block draggable"
        >
          <.live_component
            module={__MODULE__}
            id={"#{@id}-blocks-#{id}"}
            uid={child_block_form.data.uid}
            type={child_block_form.data.type}
            multi={child_block_form.data.multi}
            children={child_block_form.data.children}
            parent_id={child_block_form.data.parent_id}
            form={child_block_form}
            current_user_id={@current_user_id}
            belongs_to={:multi}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def render(%{type: :module} = assigns) do
    ~H"""
    <div data-dirty={@form_has_changes}>
      <h2>MODULE<span :if={@form_has_changes} style="color: red;"> [*]</span></h2>
      <small>
        —— belongs to <%= inspect(@belongs_to) %> — deleted: <%= @deleted %><br />
      </small>
      <button
        type="button"
        phx-click={JS.push("insert_block", value: %{type: "BASE"}, target: @myself)}
      >
        Add block over
      </button>
      <button type="button" phx-click={JS.push("move_block", target: @myself)}>
        Move to bottom
      </button>
      <%= render_slot(@inner_block) %>
      <div class="form">
        <.form
          for={@form}
          class="mt-1"
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-submit="save_block"
          phx-target={@myself}
        >
          <.toolbar myself={@myself} />
          <%= if @belongs_to == :root do %>
            <%!-- <Input.text field={@form[:entry_id]} label="ENTRY ID" /> --%>
            <.inputs_for :let={block} field={@form[:block]}>
              <.inputs_for :let={var} field={block[:vars]}>
                <.var var={var} />
              </.inputs_for>
              <button>Save</button>
              —— description fv: <%= block[:description].value %><br />
              —— description cdv: <%= block.source.data.description %><br />
              —— sequence: <%= @form[:sequence].value %><br />
              <div class="brando-input">
                <Input.text field={block[:uid]} label="UID" />
                <Input.text field={block[:description]} label="Description" />
              </div>
            </.inputs_for>
          <% else %>
            <.inputs_for :let={var} field={@form[:vars]}>
              <.var var={var} />
            </.inputs_for>
            <div class="brando-input">
              <Input.text field={@form[:uid]} label="UID" />
              <Input.text field={@form[:description]} label="Description" />
            </div>
          <% end %>
          <%!-- <div>
            <code>
              <pre style="font-size: 9px;font-family: Monospace;"><%= inspect @form, pretty: true %></pre>
            </code>
          </div> --%>
        </.form>
      </div>
    </div>
    """
  end

  def render(%{type: :container} = assigns) do
    ~H"""
    <div>
      <h2>CONTAINER</h2>
      <%= render_slot(@inner_block) %>
      <div class="form">
        <.form
          for={@form}
          class="mt-1"
          phx-value-id={@form.data.id}
          phx-change="validate_container"
          phx-submit="save_container"
          phx-target={@myself}
        >
          <div class="brando-input">
            <.inputs_for :let={block} field={@form[:block]}>
              <Input.text field={block[:uid]} label="UID" />
              <Input.text field={block[:description]} label="Description" />
            </.inputs_for>
          </div>
        </.form>
      </div>

      <div
        id="blocks-children"
        phx-update="stream"
        phx-hook="Brando.SortableBlocks"
        data-sortable-id="sortable-blocks"
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <div
          :for={{id, child_block_form} <- @streams.children_forms}
          id={id}
          data-id={child_block_form.data.id}
          data-uid={child_block_form.data.uid}
          data-parent_id={child_block_form.data.parent_id}
          class="block draggable"
        >
          <.live_component
            module={__MODULE__}
            id={"#{@id}-blocks-#{id}"}
            uid={child_block_form.data.uid}
            type={child_block_form.data.type}
            multi={child_block_form.data.multi}
            children={child_block_form.data.children}
            parent_id={child_block_form.data.parent_id}
            form={child_block_form}
            current_user_id={@current_user_id}
            belongs_to={:container}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def var(assigns) do
    ~H"""
    <div class="block-var">
      <%= @var.data.key %> - <%= @var.data.type %>
      <Input.hidden field={@var[:key]} />
      <Input.hidden field={@var[:type]} />
      <Input.text field={@var[:value]} label="Value" />
    </div>
    """
  end

  def toolbar(assigns) do
    ~H"""
    <.handle />
    <.delete myself={@myself} />
    """
  end

  def delete(assigns) do
    ~H"""
    <button type="button" phx-click="delete_block" phx-target={@myself}>
      Delete
    </button>
    """
  end

  def handle(assigns) do
    ~H"""
    <div class="sort-handle" data-sortable-group={1}>
      <.icon name="hero-arrows-up-down" />
    </div>
    """
  end

  def handle_event("move_block", _params, socket) do
    parent_cid = socket.assigns.parent_cid
    send_update(parent_cid, %{event: "move_block", form: socket.assigns.form})
    {:noreply, socket}
  end

  def handle_event("insert_block", %{"type" => "BASE"}, socket) do
    parent_cid = socket.assigns.parent_cid
    require Logger

    Logger.error("""

    == insert block to parent_cid: #{inspect(parent_cid)} -- before id: #{inspect(socket.assigns.uid)}

    """)

    send_update(parent_cid, %{
      event: "insert_block",
      type: "BASE",
      before_id: socket.assigns.uid,
      parent_id: socket.assigns.parent_id
    })

    {:noreply, socket}
  end

  # reposition a main block
  def handle_event(
        "reposition",
        %{"id" => _id, "new" => new_idx, "old" => old_idx, "parent_id" => parent_id},
        socket
      )
      when new_idx == old_idx do
    require Logger

    Logger.error("""

    Repositioning CHILD block (parent_id: #{parent_id})
    --> No move needed.

    """)

    {:noreply, socket}
  end

  def handle_event(
        "reposition",
        %{"id" => _id, "new" => new_idx, "old" => old_idx, "parent_id" => parent_id},
        socket
      ) do
    require Logger

    Logger.error("""

    Repositioning CHILD block (parent_id: #{parent_id})
    --> #{old_idx} to #{new_idx}

    """)

    {:noreply, socket}
  end

  def handle_event("delete_block", _params, socket) do
    {:noreply, assign(socket, :deleted, true)}
  end

  def handle_event("validate_container", unsigned_params, socket) do
    require Logger

    Logger.error("""

    validate_container:
    #{inspect(unsigned_params, pretty: true)}

    """)

    {:noreply, socket}
  end

  def handle_event("save_block", %{"entry_block" => params}, socket) do
    parent_cid = socket.assigns.parent_cid
    form = socket.assigns.form
    action = (form[:id].value && :update) || :insert
    user_id = socket.assigns.current_user_id

    updated_form = to_base_change_form(form.source, params, user_id)
    updated_changeset = updated_form.source

    updated_form =
      if action == :insert and Ecto.Changeset.changed?(updated_changeset, :block) do
        entry_block = Ecto.Changeset.apply_changes(updated_changeset)
        to_base_change_form(entry_block, %{}, user_id, :insert)
      else
        updated_form
      end

    updated_changeset = updated_form.source

    require Logger

    Logger.error("""

    save_block -cs action #{inspect(action)}
    #{inspect(updated_changeset, pretty: true)}

    data:
    #{inspect(updated_changeset.data, pretty: true)}
    """)

    # save changeset
    case Brando.repo().insert_or_update(updated_changeset) do
      {:ok, entry} ->
        preloaded_entry = Brando.repo().preload(entry, Brando.Content.Block.preloads())
        updated_form = to_base_change_form(preloaded_entry, %{}, user_id, :validate)
        send_update(parent_cid, %{event: "update_block", type: "BASE", form: updated_form})

      {:error, changeset} ->
        updated_form = to_base_change_form(changeset, %{}, user_id, :validate)
        send_update(parent_cid, %{event: "update_block", type: "BASE", form: updated_form})
    end

    {:noreply, socket}
  end

  def handle_event("validate_block", %{"child_block" => _params}, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_block", %{"entry_block" => params}, socket) do
    parent_cid = socket.assigns.parent_cid
    form = socket.assigns.form

    updated_form =
      to_base_change_form(
        form.source,
        params,
        socket.assigns.current_user_id,
        :validate
      )

    send_update(parent_cid, %{event: "update_block", type: "BASE", form: updated_form})

    {:noreply, socket}
  end

  # for forms that are on the base level, meaning
  # they are a join schema between an entry and a block
  defp to_base_change_form(entry_block_or_cs, params, user, action \\ nil) do
    # start from data or entry
    data =
      if entry_block_or_cs.__struct__ == Ecto.Changeset do
        entry_block_or_cs.data
      else
        entry_block_or_cs
      end

    changeset =
      data
      |> Brando.Pages.Page.Blocks.changeset(params, user)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{changeset.data.block.uid}"
    )
  end

  defp to_change_form(child_block_or_cs, params, user, action \\ nil) do
    changeset =
      child_block_or_cs
      |> Brando.Content.Block.changeset(params, user)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "child_block",
      id: "child_block_form-#{changeset.data.parent_id}-#{changeset.data.id}"
    )
  end
end
