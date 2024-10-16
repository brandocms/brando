defmodule BrandoAdmin.Components.Form.BlockField do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker
  alias Ecto.Changeset
  use Gettext, backend: Brando.Gettext

  def mount(socket) do
    socket
    |> stream_configure(:entry_blocks_forms,
      dom_id: fn %{source: changeset} ->
        block_cs = Changeset.get_assoc(changeset, :block)
        uid = Changeset.get_field(block_cs, :uid)
        "base-#{uid}"
      end
    )
    |> assign(:first_run, true)
    |> then(&{:ok, &1})
  end

  def update(%{event: "duplicate_block", uid: uid, changeset: changeset}, socket) do
    block_module = socket.assigns.block_module
    block_list = socket.assigns.block_list
    root_changesets = socket.assigns.root_changesets
    sequence = Enum.find_index(block_list, &(&1 == uid))
    current_user_id = socket.assigns.current_user.id
    entry_id = socket.assigns.entry.id

    uid = Brando.Utils.generate_uid()
    block_cs = Changeset.get_assoc(changeset, :block)

    updated_block_cs =
      block_cs
      # |> Changeset.put_change(:id, nil)
      |> put_in([Access.key(:data), Access.key(:id)], nil)
      |> Changeset.put_change(:uid, uid)
      |> remove_pk_from_vars()
      |> remove_pk_from_table_rows()
      |> add_uid_to_refs()
      |> Map.put(:action, :insert)

    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: entry_id})
      |> Changeset.put_assoc(:block, updated_block_cs)
      |> Map.put(:action, :insert)

    uid = Changeset.get_field(updated_block_cs, :uid)

    # insert the new block uid into the block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        current_user_id
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    socket
    |> stream_insert(:entry_blocks_forms, entry_block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "delete_block", uid: uid}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_list = socket.assigns.block_list
    updated_root_changesets = delete_root_changeset(root_changesets, uid)
    new_block_list = List.delete(block_list, uid)

    socket
    |> assign(:root_changesets, updated_root_changesets)
    |> assign(:block_list, new_block_list)
    |> stream_delete_by_dom_id(:entry_blocks_forms, "base-#{uid}")
    |> update(:block_count, &(&1 - 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
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

  def update(%{event: "provide_root_block", changeset: changeset, uid: uid, tag: tag}, socket) do
    root_changesets = socket.assigns.root_changesets
    form_cid = socket.assigns.form_cid
    block_field = socket.assigns.block_field
    updated_root_changesets = update_root_changeset(root_changesets, uid, changeset)

    if Enum.any?(updated_root_changesets, &(elem(&1, 1) == nil)) do
      {:ok, assign(socket, :root_changesets, updated_root_changesets)}
    else
      send_update(form_cid, %{
        event: "provide_root_blocks",
        root_changesets: updated_root_changesets,
        block_field: block_field,
        tag: tag
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
    source = socket.assigns.block_module
    empty_block_cs = build_block(module_id, user_id, parent_id, source, :module)

    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)
      |> Changeset.put_change(:sequence, sequence)
      |> Map.put(:action, :insert)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_form(entry_block_cs,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    selector = "[data-block-uid=\"#{uid}\"]"

    socket
    |> stream_insert(:entry_blocks_forms, entry_block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_container", sequence: sequence}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    source = socket.assigns.block_module
    empty_block_cs = build_container(user_id, parent_id, source)
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
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_fragment", sequence: sequence}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    source = socket.assigns.block_module
    empty_block_cs = build_fragment(user_id, parent_id, source)

    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)
      |> Map.put(:action, :insert)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_form(entry_block_cs,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    socket
    |> stream_insert(:entry_blocks_forms, entry_block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "fetch_root_blocks", tag: tag}, socket) do
    block_list = socket.assigns.block_list
    block_field = socket.assigns.block_field
    form_cid = socket.assigns.form_cid

    if block_list == [] do
      send_update(form_cid, %{
        event: "provide_root_blocks",
        root_changesets: [],
        block_field: block_field,
        tag: tag
      })
    else
      # for each root block in block_list, send_update requesting their changeset
      for block_uid <- block_list do
        send_update(
          Block,
          id: "block-#{block_uid}",
          event: "fetch_root_block",
          tag: tag
        )
      end
    end

    {:ok, socket}
  end

  def update(%{event: "fetch_root_renders"}, socket) do
    block_list = socket.assigns.block_list
    block_field = socket.assigns.block_field
    form_cid = socket.assigns.form_cid

    if block_list == [] do
      send_update(form_cid, %{
        event: "provide_root_renders",
        renders: [],
        block_field: block_field
      })
    else
      # for each root block in block_list, send_update requesting their rendered_html
      for block_uid <- block_list do
        send_update(Block, id: "block-#{block_uid}", event: "fetch_root_render")
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

  def update(%{event: "signal_position_update", uid: uid}, socket) do
    form_cid = socket.assigns.form_cid
    position_response_tracker = socket.assigns.position_response_tracker

    position_response_tracker =
      Enum.map(position_response_tracker, fn
        {^uid, _} -> {uid, true}
        item -> item
      end)

    if Enum.any?(position_response_tracker, &(elem(&1, 1) == false)) do
      {:ok, assign(socket, :position_response_tracker, position_response_tracker)}
    else
      send_update(form_cid, %{event: "update_live_preview"})
      {:ok, assign(socket, :position_response_tracker, position_response_tracker)}
    end
  end

  def update(%{event: "enable_live_preview", cache_key: cache_key}, socket) do
    block_list = socket.assigns.block_list

    for block_uid <- block_list do
      send_update(Block,
        id: "block-#{block_uid}",
        event: "enable_live_preview",
        cache_key: cache_key
      )
    end

    {:ok, socket}
  end

  def update(%{event: "disable_live_preview"}, socket) do
    block_list = socket.assigns.block_list

    for block_uid <- block_list do
      send_update(Block,
        id: "block-#{block_uid}",
        event: "disable_live_preview"
      )
    end

    {:ok, socket}
  end

  def update(%{event: "reload_all_blocks"}, socket) do
    {:ok, reload_all_blocks(socket)}
  end

  def update(assigns, socket) do
    block_module = assigns.block_module
    user_id = assigns.current_user.id
    entry_blocks = assigns.entry_blocks || []
    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))

    socket
    |> assign(assigns)
    |> assign_new(:block_list, fn -> Enum.map(entry_blocks, & &1.block.uid) end)
    |> assign_new(:block_count, fn %{block_list: block_list} -> Enum.count(block_list) end)
    |> assign_new(:root_changesets, fn -> Enum.map(entry_blocks, &{&1.block.uid, nil}) end)
    |> maybe_stream(entry_blocks_forms)
    |> assign_templates()
    |> assign_module_namespace()
    |> reset_position_response_tracker()
    |> maybe_sequence_blocks()
    |> assign(:first_run, false)
    |> then(&{:ok, &1})
  end

  defp assign_module_namespace(socket) do
    assign_new(socket, :module_namespace, fn ->
      opts = socket.assigns.opts
      opts[:module_namespace] || "all"
    end)
  end

  defp reload_all_blocks(socket) do
    # reset the stream
    user_id = socket.assigns.current_user.id
    block_module = socket.assigns.block_module
    entry_blocks = socket.assigns.entry_blocks || []
    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))

    socket
    |> assign_new(:block_list, fn -> Enum.map(entry_blocks, & &1.block.uid) end)
    |> assign_new(:block_count, fn %{block_list: block_list} -> Enum.count(block_list) end)
    |> assign_new(:root_changesets, fn -> Enum.map(entry_blocks, &{&1.block.uid, nil}) end)
    |> stream(:entry_blocks_forms, entry_blocks_forms)
  end

  defp maybe_sequence_blocks(%{assigns: %{first_run: true}} = socket) do
    block_list = socket.assigns.block_list
    send_block_entry_position_update(socket, block_list)
  end

  defp maybe_sequence_blocks(socket) do
    socket
  end

  def maybe_stream(%{assigns: %{first_run: true}} = socket, entry_blocks_forms) do
    stream(socket, :entry_blocks_forms, entry_blocks_forms)
  end

  def maybe_stream(socket, _) do
    socket
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

  def delete_root_changeset(root_changesets, uid) do
    Enum.reject(root_changesets, fn
      {^uid, _} -> true
      _ -> false
    end)
  end

  defp add_uid_to_refs(changeset) do
    refs = Changeset.get_embed(changeset, :refs)

    updated_refs = Brando.Villain.add_uid_to_ref_changesets(refs)
    Changeset.put_embed(changeset, :refs, updated_refs)
  end

  defp remove_pk_from_vars(changeset) do
    vars = Changeset.get_assoc(changeset, :vars)

    vars_without_pk =
      Enum.map(
        vars,
        fn var ->
          var
          |> put_in([Access.key(:data), Access.key(:id)], nil)
          |> Map.put(:action, :insert)
        end
      )

    Changeset.put_change(changeset, :vars, vars_without_pk)
  end

  defp remove_pk_from_table_rows(changeset) do
    table_rows = Changeset.get_assoc(changeset, :table_rows)

    table_rows_without_pk =
      Enum.map(table_rows, fn table_row ->
        table_row
        |> put_in([Access.key(:data), Access.key(:id)], nil)
        |> Map.put(:action, :insert)
      end)

    Changeset.put_change(changeset, :table_rows, table_rows_without_pk)
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
    root_changesets = socket.assigns.root_changesets

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, id)

    # we must reposition the root_changesets list according to the new block_list
    new_root_changesets =
      Enum.map(new_block_list, fn uid ->
        Enum.find(root_changesets, fn
          {^uid, _} -> true
          _ -> false
        end)
      end)

    socket
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, new_root_changesets)
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:noreply, &1})
  end

  def handle_event("show_block_picker", _, socket) do
    # message block picker
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    block_count = socket.assigns.block_count
    module_namespace = socket.assigns.module_namespace

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: nil, namespace: module_namespace},
      module_namespace: module_namespace,
      type: :module,
      sequence: block_count + 1,
      parent_cid: socket.assigns.myself
    )

    {:noreply, socket}
  end

  def reset_position_response_tracker(socket) do
    block_list = socket.assigns.block_list
    assign(socket, :position_response_tracker, Enum.map(block_list, &{&1, false}))
  end

  def send_block_entry_position_update(socket, block_list) do
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
                parent_path={[]}
                module_namespace={@module_namespace}
                entry={@entry}
                form={entry_block_form}
                form_cid={@form_cid}
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

  def build_block(module_id, user_id, parent_id, source, type) do
    module = get_module(module_id)
    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)
    vars_without_pk = Brando.Villain.remove_pk_from_vars(module.vars)

    var_changesets =
      Enum.map(vars_without_pk, &(Changeset.change(&1, %{}) |> Map.put(:action, :insert)))

    Changeset.change(
      %Brando.Content.Block{},
      %{
        uid: Brando.Utils.generate_uid(),
        type: type,
        creator_id: user_id,
        module_id: module_id,
        parent_id: parent_id,
        multi: module.multi,
        source: source,
        children: [],
        block_identifiers: [],
        table_rows: [],
        vars: var_changesets,
        refs: refs_with_generated_uids
      }
    )
  end

  def build_fragment(user_id, parent_id, source) do
    Changeset.change(
      %Brando.Content.Block{},
      %{
        uid: Brando.Utils.generate_uid(),
        type: :fragment,
        creator_id: user_id,
        parent_id: parent_id,
        fragment_id: nil,
        multi: false,
        source: source,
        children: [],
        block_identifiers: [],
        table_rows: [],
        vars: [],
        refs: []
      }
    )
  end

  def build_container(user_id, parent_id, source) do
    Changeset.change(%Brando.Content.Block{}, %{
      uid: Brando.Utils.generate_uid(),
      type: :container,
      creator_id: user_id,
      parent_id: parent_id,
      source: source,
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
