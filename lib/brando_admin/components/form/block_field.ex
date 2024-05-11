defmodule BrandoAdmin.Components.Form.BlockField do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker
  alias Ecto.Changeset
  import Brando.Gettext

  def mount(socket) do
    {:ok,
     stream_configure(socket, :entry_blocks_forms,
       dom_id: fn form ->
         changeset = form.source
         block_cs = Changeset.get_assoc(changeset, :block)
         uid = Changeset.get_field(block_cs, :uid)
         "base-#{uid}"
       end
     )}
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

    {:ok, stream_insert(socket, :entry_blocks_forms, entry_block_form)}
  end

  def update(%{event: "update_block", level: _level, form: form}, socket) do
    {:ok, stream_insert(socket, :entry_blocks_forms, form)}
  end

  def update(%{event: "provide_root_block", changeset: changeset, uid: uid}, socket) do
    root_changesets = socket.assigns.root_changesets
    form_cid = socket.assigns.form_cid
    block_field = socket.assigns.block_field
    updated_root_changesets = update_root_changeset(root_changesets, uid, changeset)

    require Logger

    Logger.error("""
    [!] provide_root_block #{uid}
    """)

    if Enum.any?(updated_root_changesets, &(elem(&1, 1) == nil)) do
      require Logger

      Logger.error("""
      [!] still missing some root blocks
      """)

      {:ok, assign(socket, :root_changesets, updated_root_changesets)}
    else
      require Logger

      Logger.error("""
      [!] got all root blocks! :)
      """)

      send_update(form_cid, %{
        event: "provide_root_blocks",
        root_changesets: updated_root_changesets,
        block_field: block_field
      })

      {:ok, assign(socket, :root_changesets, updated_root_changesets)}
    end
  end

  # INSERT ROOT BLOCK

  def update(%{event: "insert_block", sequence: sequence, module_id: module_id}, socket) do
    module_id = String.to_integer(module_id)
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    empty_block_cs = build_block(module_id, user_id, parent_id, :module)
    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        socket.assigns.current_user.id
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    socket
    |> stream_insert(:entry_blocks_forms, entry_block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> assign(:root_changesets, updated_root_changesets)
    |> send_root_sequence_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_container", sequence: sequence}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    empty_block_cs = build_container(user_id, parent_id)
    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    ## --

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        socket.assigns.current_user.id
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    socket
    |> stream_insert(:entry_blocks_forms, entry_block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> assign(:root_changesets, updated_root_changesets)
    |> send_root_sequence_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "fetch_root_blocks"}, socket) do
    block_list = socket.assigns.block_list
    block_field = socket.assigns.block_field
    form_cid = socket.assigns.form_cid

    require Logger

    Logger.error("""
    -> fetch_root_blocks [block_field:#{block_field}]
    """)

    if block_list == [] do
      send_update(form_cid, %{
        event: "provide_root_blocks",
        root_changesets: [],
        block_field: block_field
      })
    else
      # for each root block in block_list, send_update requesting their changeset
      for block_uid <- block_list do
        require Logger

        Logger.error("""
        --> fetch_root_block [uid:#{block_uid}]
        """)

        send_update(Block, id: "block-#{block_uid}", event: "fetch_root_block")
      end
    end

    socket
    |> then(&{:ok, &1})
  end

  def update(%{event: "clear_root_changesets"}, socket) do
    block_list = socket.assigns.block_list
    # for each root block in block_list, send_update to clear their (child) changesets
    for block_uid <- block_list do
      send_update(Block, id: "block-#{block_uid}", event: "clear_changesets")
    end

    cleared_root_changesets = Enum.map(socket.assigns.root_changesets, &{elem(&1, 0), nil})
    {:ok, assign(socket, :root_changesets, cleared_root_changesets)}
  end

  def update(assigns, socket) do
    block_module = assigns.block_module
    entry_blocks = assigns.entry_blocks
    user_id = assigns.current_user.id

    entry_blocks_forms =
      Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))

    socket
    |> assign(assigns)
    |> assign_new(:block_list, fn -> Enum.map(entry_blocks, & &1.block.uid) end)
    |> assign_new(:block_count, fn %{block_list: block_list} -> Enum.count(block_list) end)
    |> assign_new(:root_changesets, fn ->
      Enum.map(entry_blocks, &{&1.block.uid, nil})
    end)
    |> stream(:entry_blocks_forms, entry_blocks_forms)
    |> assign_templates()
    |> then(&{:ok, &1})
  end

  def update_root_changeset(root_changesets, uid, new_changeset) do
    Enum.map(root_changesets, fn
      {^uid, _changeset} -> {uid, new_changeset}
      {uid, changeset} -> {uid, changeset}
    end)
  end

  def insert_root_changeset(root_changesets, uid, position) do
    List.insert_at(root_changesets, position, {uid, nil})
  end

  # reposition a main block
  def handle_event("reposition", %{"new" => new_idx, "old" => old_idx}, socket)
      when new_idx == old_idx do
    # same index, no move needed
    {:noreply, socket}
  end

  def handle_event(
        "reposition",
        %{"uid" => id, "new" => new_idx, "old" => old_idx},
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

  def handle_event("show_block_picker", _, socket) do
    # message block picker
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    block_list = socket.assigns.block_list

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      type: :module,
      sequence: Enum.count(block_list) + 1,
      parent_cid: socket.assigns.myself
    )

    {:noreply, socket}
  end

  def handle_event("fetch_root_blocks", _, socket) do
    block_list = socket.assigns.block_list
    # for each root block in block_list, send_update requesting their changeset
    for block_uid <- block_list do
      send_update(Block, id: "block-#{block_uid}", event: "fetch_root_block")
    end

    {:noreply, socket}
  end

  def handle_event("crash", _, socket) do
    raise "Crash"
    {:noreply, socket}
  end

  def send_root_sequence_update(socket, block_list) do
    # send_update to all components in block_list
    for {block_uid, idx} <- Enum.with_index(block_list) do
      send_update(Block, id: "block-#{block_uid}", event: "update_sequence", sequence: idx)
    end

    socket
  end

  def render(assigns) do
    ~H"""
    <div class="blocks-wrapper">
      <.live_component
        module={BrandoAdmin.Components.Form.BlockField.ModulePicker}
        id={"block-field-#{assigns.block_field}-module-picker"}
        templates={[]}
        hide_fragments={false}
        hide_sections={false}
      />
      <div style="font-family: 'Mono'; font-size: 11px;">
        ROOT CHANGESETS<br /><br />
        <%= inspect(@root_changesets, pretty: true, width: 0) %>
      </div>
      <%= if @block_count == 0 do %>
        <div class="blocks-empty-instructions">
          <%= gettext("Click the plus to start adding content blocks") %>
          <%= if @templates && @templates != [] do %>
            <br /><%= gettext("or get started with a prefab'ed template") %>:<br />
            <div class="blocks-templates">
              <%= for template <- @templates do %>
                <button
                  type="button"
                  phx-click={JS.push("use_template", target: @myself)}
                  phx-value-id={template.id}
                >
                  <%= template.name %><br />
                  <small><%= template.instructions %></small>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <div
        id={"block-field-#{@block_field}"}
        phx-update="stream"
        phx-hook="Brando.SortableBlocks"
        data-sortable-id="sortable-blocks"
        data-sortable-handle=".sort-handle"
        data-sortable-selector=".block"
      >
        <%= for {id, entry_block_form} <- @streams.entry_blocks_forms do %>
          <.inputs_for :let={block} field={entry_block_form[:block]} skip_hidden>
            <div
              id={id}
              data-id={entry_block_form[:id].value}
              data-uid={block[:uid].value}
              class="entry-block draggable"
            >
              <.live_component
                module={Block}
                id={"block-#{block[:uid].value}"}
                block_module={@block_module}
                block_field={@block_field}
                children={block[:children].value}
                parent_uploads={@parent_uploads}
                parent_cid={@myself}
                parent_uid={}
                entry={@entry}
                form={entry_block_form}
                current_user_id={@current_user.id}
                belongs_to={:root}
                level={0}
              />
            </div>
          </.inputs_for>
        <% end %>
      </div>

      <Block.plus click={JS.push("show_block_picker", target: @myself)} />
    </div>
    """
  end

  def to_change_form(block_module, entry_block_or_cs, params, user_id, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> block_module.changeset(params, user_id)
      |> Map.put(:action, action)

    block_cs = Changeset.get_assoc(changeset, :block)
    uid = Changeset.get_field(block_cs, :uid)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{uid}"
    )
  end

  def build_block(module_id, user_id, parent_id, type) do
    module = get_module(module_id)
    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)
    vars_without_pk = Brando.Villain.remove_pk_from_vars(module.vars)

    var_changesets =
      Enum.map(vars_without_pk, &(Changeset.change(&1, %{}) |> Map.put(:action, :insert)))

    Changeset.change(%Brando.Content.Block{children: []}, %{
      uid: Brando.Utils.generate_uid(),
      type: type,
      creator_id: user_id,
      module_id: module_id,
      parent_id: parent_id,
      multi: module.wrapper,
      children: [],
      vars: var_changesets,
      refs: refs_with_generated_uids
    })
  end

  def build_container(user_id, parent_id) do
    Changeset.change(%Brando.Content.Block{}, %{
      uid: Brando.Utils.generate_uid(),
      type: :container,
      creator_id: user_id,
      parent_id: parent_id,
      children: []
    })
  end

  defp get_module(module_id) do
    modules = Brando.Content.list_modules!(%{cache: {:ttl, :infinite}, preload: [:vars]})
    Enum.find(modules, &(&1.id == module_id))
  end

  defp assign_templates(socket) do
    assign_new(socket, :templates, fn ->
      if template_namespace = socket.assigns.opts[:template_namespace] do
        Brando.Content.list_templates!(%{filter: %{namespace: template_namespace}})
      else
        nil
      end
    end)
  end
end
