defmodule BrandoAdmin.Components.Form.BlockField do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Block
  alias Ecto.Changeset
  # import Brando.Gettext

  def mount(socket) do
    {:ok, stream_configure(socket, :entry_blocks_forms, dom_id: &"base-#{&1.data.block.uid}")}
  end

  # drop this
  def update(
        %{
          event: "update_changeset",
          level: level,
          updated_changeset: updated_changeset,
          block_uid: uid,
          parent_uid: parent_uid
        },
        socket
      ) do
    # root_changesets = socket.assigns.root_changesets

    # {:ok, socket |> assign(:root_changesets, Map.put(root_changesets, uid, updated_changeset))}
    {:ok, socket}
  end

  def update(%{event: "update_root_sequence", sequence: sequence, form: form}, socket) do
    block_module = socket.assigns.block_module

    entry_block_form =
      to_change_form(
        block_module,
        form.source,
        %{sequence: sequence},
        socket.assigns.current_user.id
      )

    socket = stream_insert(socket, :entry_blocks_forms, entry_block_form)
    {:ok, socket}
  end

  def update(%{event: "update_block", level: _level, form: form}, socket) do
    socket = stream_insert(socket, :entry_blocks_forms, form)
    {:ok, socket}
  end

  def update(%{event: "gather_root_block", changeset: changeset, uid: uid}, socket) do
    root_changesets = socket.assigns.root_changesets

    {:ok, assign(socket, :root_changesets, Map.put(root_changesets, uid, changeset))}
  end

  def update(
        %{event: "insert_block", level: 0, sequence: sequence, parent_id: parent_id} = assigns,
        socket
      ) do
    # before_id = assigns.before_id
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    empty_block = build_block(2, user_id, parent_id)
    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block =
      struct(block_module, %{
        entry_id: socket.assigns.entry.id,
        block: empty_block,
        sequence: sequence
      })

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, empty_block.uid)

    entry_block_form =
      to_change_form(block_module, entry_block, %{}, socket.assigns.current_user.id)

    socket
    |> stream_insert(:entry_blocks_forms, entry_block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> send_root_sequence_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    block_module = assigns.block_module
    entry_blocks = assigns.entry.entry_blocks
    user_id = assigns.current_user.id

    entry_blocks_forms =
      Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:block_list, fn -> Enum.map(entry_blocks, & &1.block.uid) end)
      |> assign_new(:root_changesets, fn ->
        entry_blocks
        |> Enum.map(&{&1.block.uid, nil})
        |> Enum.into(%{})
      end)
      |> stream(:entry_blocks_forms, entry_blocks_forms)

    {:ok, socket}
  end

  # reposition a main block
  def handle_event("reposition", %{"new" => new_idx, "old" => old_idx}, socket)
      when new_idx == old_idx do
    # same index, no move needed
    {:noreply, socket}
  end

  def handle_event(
        "reposition",
        %{"uid" => id, "new" => new_idx, "old" => old_idx} = params,
        socket
      ) do
    block_list = socket.assigns.block_list

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, id)

    send_root_sequence_update(socket, new_block_list)

    {:noreply, assign(socket, :block_list, new_block_list)}
  end

  def handle_event("gather_root_blocks", _, socket) do
    block_list = socket.assigns.block_list
    parent_id = socket.assigns.id
    # for each root block in block_list, send_update requesting their changeset
    for block_uid <- block_list do
      id = "root-block-#{block_uid}"
      send_update(Block, id: id, event: "gather_root_block")
    end

    {:noreply, socket}
  end

  def send_root_sequence_update(socket, block_list) do
    # send_update to all components in block_list
    parent_id = socket.assigns.id

    for {block_uid, idx} <- Enum.with_index(block_list) do
      id = "root-block-#{block_uid}"
      send_update(Block, id: id, event: "update_sequence", sequence: idx)
    end

    socket
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="block-list">
        <code>
          <pre phx-no-format>
    <%= inspect(@root_changesets, pretty: true) %>
          </pre>
        </code>
        <button type="button" phx-click="gather_root_blocks" phx-target={@myself}>
          Gather Blocks
        </button>
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
            id={"root-block-#{entry_block_form.data.block.uid}"}
            uid={entry_block_form.data.block.uid}
            block_module={@block_module}
            type={entry_block_form.data.block.type}
            multi={entry_block_form.data.block.multi}
            children={entry_block_form.data.block.children}
            parent_id={entry_block_form.data.block.parent_id}
            parent_cid={@myself}
            parent_uid={}
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

  def to_change_form(block_module, entry_block_or_cs, params, user_id, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> block_module.changeset(params, user_id)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{changeset.data.block.uid}"
    )
  end

  def build_block(module_id, user_id, parent_id) do
    {:ok, module} = Brando.Content.get_module(%{matches: %{id: module_id}, preload: [:vars]})

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
