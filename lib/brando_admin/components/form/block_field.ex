defmodule BrandoAdmin.Components.Form.BlockField do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Block
  # import Brando.Gettext

  def mount(socket) do
    {:ok, stream_configure(socket, :entry_blocks_forms, dom_id: &"base-#{&1.data.block.uid}")}
  end

  def update(%{event: "update_root_sequence", sequence: sequence, form: form}, socket) do
    entry_block_form =
      to_change_form(form.source, %{sequence: sequence}, socket.assigns.current_user)

    socket = stream_insert(socket, :entry_blocks_forms, entry_block_form)
    {:ok, socket}
  end

  def update(%{event: "update_block", level: _level, form: form}, socket) do
    socket = stream_insert(socket, :entry_blocks_forms, form)
    {:ok, socket}
  end

  def update(%{event: "insert_block", level: 0, parent_id: parent_id} = assigns, socket) do
    # before_id = assigns.before_id
    user_id = socket.assigns.current_user.id
    empty_block = build_block(2, user_id, parent_id)

    # empty_block_cs = Brando.Content.Block.changeset(empty_block, %{}, socket.assigns.current_user)

    entry_block =
      %Brando.Pages.Page.Blocks{
        entry_id: socket.assigns.entry.id,
        block: empty_block,
        sequence: nil
      }

    entry_block_form = to_change_form(entry_block, %{sequence: 0}, socket.assigns.current_user)
    socket = stream_insert(socket, :entry_blocks_forms, entry_block_form, at: 0)
    {:ok, socket}
  end

  def update(%{event: "move_block", form: form} = assigns, socket) do
    require Logger

    form = to_change_form(form.source, %{sequence: 99}, socket.assigns.current_user)

    socket
    |> stream_delete(:entry_blocks_forms, form)
    |> stream_insert(:entry_blocks_forms, form, at: -1)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    entry_blocks = assigns.entry.entry_blocks

    entry_blocks_forms =
      Enum.map(entry_blocks, &to_change_form(&1, %{}, assigns.current_user))

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:block_list, fn ->
        Enum.map(entry_blocks, & &1.block.uid)
      end)
      |> stream(:entry_blocks_forms, entry_blocks_forms)

    {:ok, socket}
  end

  # reposition a main block
  def handle_event("reposition", %{"uid" => _id, "new" => new_idx, "old" => old_idx}, socket)
      when new_idx == old_idx do
    require Logger

    Logger.error("""

    Repositioning BASE block
    --> No move needed.

    """)

    {:noreply, socket}
  end

  def handle_event(
        "reposition",
        %{"uid" => id, "new" => new_idx, "old" => old_idx} = params,
        socket
      ) do
    require Logger

    Logger.error("""

    Repositioning BASE block
    --> [uid:#{id}] #{old_idx} to #{new_idx}

    #{inspect(params, pretty: true)}

    """)

    parent_id = socket.assigns.id
    block_list = socket.assigns.block_list

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, id)

    # send_update to all components in new_block_list
    for {block_uid, idx} <- Enum.with_index(new_block_list) do
      id = "#{parent_id}-blocks-#{block_uid}"
      send_update(Block, id: id, event: "update_sequence", sequence: idx)
    end

    {:noreply, assign(socket, :block_list, new_block_list)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="block-list">
        <code>
          <pre><%= inspect(@block_list, pretty: true, width: 0) %></pre>
        </code>
      </div>
      <div
        id="blocks"
        phx-update="stream"
        phx-hook="Brando.SortableBlocks"
        data-sortable-id="sortable-blocks"
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <div
          :for={{id, entry_block_form} <- @streams.entry_blocks_forms}
          id={id}
          data-id={entry_block_form.data.id}
          data-uid={entry_block_form.data.block.uid}
          data-parent_id={entry_block_form.data.block.parent_id}
          class="block draggable"
        >
          <.live_component
            module={Block}
            id={"#{@id}-blocks-#{entry_block_form.data.block.uid}"}
            uid={entry_block_form.data.block.uid}
            type={entry_block_form.data.block.type}
            multi={entry_block_form.data.block.multi}
            children={entry_block_form.data.block.children}
            parent_id={entry_block_form.data.block.parent_id}
            parent_cid={@myself}
            form={entry_block_form}
            current_user_id={@current_user.id}
            belongs_to={:root}
            level={0}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  defp to_change_form(entry_block_or_cs, params, user, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> Brando.Pages.Page.Blocks.changeset(params, user.id)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{changeset.data.block.uid}"
    )
  end

  def build_block(module_id, user_id, parent_id) do
    {:ok, module} = Brando.Content.get_module(%{matches: %{id: module_id}, preload: [:vars]})

    require Logger

    Logger.error("""

    vars:
    #{inspect(module.vars)}

    refs:
    #{inspect(module.refs)}

    """)

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)
    vars_without_pk = Brando.Villain.remove_pk_from_vars(module.vars)

    %Brando.Content.Block{
      uid: Brando.Utils.generate_uid(),
      type: :module,
      anchor: nil,
      sequence: nil,
      module_id: module_id,
      parent_id: parent_id,
      palette_id: nil,
      refs: refs_with_generated_uids,
      vars: vars_without_pk,
      creator_id: user_id
    }
  end
end
