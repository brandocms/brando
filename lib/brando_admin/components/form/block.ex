defmodule BrandoAdmin.Components.Form.Block do
  alias Brando.Content.Var
  use BrandoAdmin, :live_component
  alias Ecto.Changeset
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Entries
  alias BrandoAdmin.Components.Form.Input.RenderVar

  alias Brando.Content.BlockIdentifier

  use Gettext, backend: Brando.Gettext
  import Phoenix.LiveView.TagEngine
  import PolymorphicEmbed.HTML.Component

  def mount(socket) do
    {:ok,
     assign(socket,
       block_initialized: false,
       container_not_found: false,
       module_not_found: false,
       entry_template: nil,
       initial_render: false,
       dom_id: nil,
       position_response_tracker: [],
       source: nil,
       live_preview_active?: false,
       live_preview_cache_key: nil
     )}
  end

  # duplicate block (that is not an entry block)
  # event is received in the parent block (multi or container)
  def update(%{event: "duplicate_block", uid: uid, changeset: block_cs}, socket) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets
    sequence = Enum.find_index(block_list, &(&1 == uid))
    current_user_id = socket.assigns.current_user_id

    new_uid = Brando.Utils.generate_uid()

    updated_block_cs =
      block_cs
      |> Changeset.apply_changes()
      |> Map.merge(%{id: nil, uid: new_uid, sequence: sequence, creator_id: current_user_id})
      |> Changeset.change()
      |> remove_pk_from_vars()
      |> remove_pk_from_table_rows()
      |> add_uid_to_refs()
      |> Map.put(:action, :insert)
      |> filter_replace_refs()
      |> Changeset.update_change(:refs, fn ref_changesets ->
        Enum.reject(ref_changesets, &(&1.action == :replace))
      end)

    # insert the new block uid into the block_list
    new_block_list = List.insert_at(block_list, sequence, new_uid)

    block_form =
      to_form(updated_block_cs,
        as: "child_block",
        id: "child_block_form-#{new_uid}"
      )

    updated_changesets = insert_child_changeset(changesets, new_uid, sequence)
    selector = "[data-block-uid=\"#{new_uid}\"]"

    socket
    |> stream_insert(:children_forms, block_form, at: sequence)
    |> assign(:has_children?, true)
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, updated_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  # event sent from RenderVar for :file, :image, :link vars
  def update(%{event: "update_block_var"} = params, socket) do
    %{var_key: var_key, var_type: var_type, data: data} = params

    socket
    |> update_changeset_data_block_var(var_key, var_type, data)
    |> update_liquex_block_var(var_key, var_type, data)
    |> then(&{:ok, &1})
  end

  def update(%{event: "enable_live_preview", cache_key: cache_key}, socket) do
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets
    id = socket.assigns.id

    if has_children? do
      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "enable_live_preview",
          cache_key: cache_key
        )
      end
    end

    socket
    |> assign(:live_preview_active?, true)
    |> assign(:live_preview_cache_key, cache_key)
    |> then(&{:ok, &1})
  end

  def update(%{event: "disable_live_preview"}, socket) do
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets
    id = socket.assigns.id

    if has_children? do
      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "disable_live_preview"
        )
      end
    end

    socket
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> then(&{:ok, &1})
  end

  def update(%{event: "delete_block", uid: uid, dom_id: dom_id}, socket) do
    changesets = socket.assigns.changesets
    block_list = socket.assigns.block_list
    updated_changesets = delete_child_changeset(changesets, uid)
    new_block_list = List.delete(block_list, uid)
    changeset = socket.assigns.form.source
    belongs_to = socket.assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    has_children? = new_block_list !== []

    # if we deleted the last child block, put_assoc the empty children list
    updated_block_cs =
      if has_children? do
        block_cs
      else
        Changeset.put_assoc(block_cs, :children, [])
      end

    updated_form =
      if belongs_to == :root do
        updated_changeset = Changeset.put_assoc(changeset, :block, updated_block_cs)

        to_form(
          updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(
          updated_block_cs,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    socket
    |> assign(:changesets, updated_changesets)
    |> assign(:block_list, new_block_list)
    |> assign(:has_children?, has_children?)
    |> assign(:form, updated_form)
    |> stream_delete_by_dom_id(:children_forms, dom_id)
    |> update(:block_count, &(&1 - 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> update_live_preview_on_empty_block_list()
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_sequence", sequence: sequence}, socket) do
    belongs_to = socket.assigns.belongs_to
    parent_cid = socket.assigns.parent_cid
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid

    updated_block_cs =
      changeset
      |> get_block_changeset(belongs_to)
      |> Changeset.put_change(:sequence, sequence)

    updated_form =
      if belongs_to == :root do
        updated_changeset =
          changeset
          |> Changeset.put_assoc(:block, updated_block_cs)
          |> Changeset.put_change(:sequence, sequence)

        to_form(
          updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(
          updated_block_cs,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    send_update(parent_cid, %{event: "signal_position_update", uid: uid})

    {:ok,
     socket
     |> assign(:form_has_changes, updated_form.source.changes !== %{})
     |> assign(:form, updated_form)}
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

  def update(%{event: "clear_changesets"}, socket) do
    id = socket.assigns.id
    has_children? = socket.assigns.has_children?

    if has_children? do
      changesets = socket.assigns.changesets
      cleared_changesets = Enum.map(changesets, &{elem(&1, 0), nil})

      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "clear_changesets"
        )
      end

      {:ok, assign(socket, :changesets, cleared_changesets)}
    else
      {:ok, socket}
    end
  end

  def update(%{event: "fetch_root_block", tag: tag}, socket) do
    # a message we will receive from the block field
    id = socket.assigns.id
    parent_cid = socket.assigns.parent_cid
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets

    if socket.assigns.deleted do
      # if the block is deleted, we don't message the children.
      send_update(parent_cid, %{
        event: "provide_root_block",
        changeset: nil,
        uid: uid,
        tag: tag
      })
    else
      # if the block has children we message them to gather their changesets
      if has_children? do
        for {block_uid, _} <- changesets do
          id = "#{id}-child-#{block_uid}"

          send_update(__MODULE__,
            id: id,
            event: "fetch_child_block",
            uid: block_uid,
            tag: tag
          )
        end
      else
        # if the block has no children we send the current changeset back to the parent
        send_update(parent_cid, %{
          event: "provide_root_block",
          changeset: changeset,
          uid: uid,
          tag: tag
        })
      end
    end

    {:ok, socket}
  end

  def update(%{event: "fetch_child_block", tag: tag}, socket) do
    # a message we will receive from parent block
    id = socket.assigns.id
    parent_cid = socket.assigns.parent_cid
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets

    # if the block has children we message them to gather their changesets
    if has_children? do
      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "fetch_child_block",
          uid: block_uid,
          tag: tag
        )
      end
    else
      # if the block has no children we send the current changeset back to the parent
      send_update(parent_cid, %{
        event: "provide_child_block",
        changeset: changeset,
        uid: uid,
        tag: tag
      })
    end

    {:ok, socket}
  end

  def update(
        %{
          event: "provide_child_block",
          changeset: child_changeset,
          uid: uid,
          tag: tag
        },
        socket
      ) do
    parent_uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    level = socket.assigns.level
    changeset = socket.assigns.form.source

    changesets = socket.assigns.changesets
    updated_changesets = update_child_changeset(changesets, uid, child_changeset)

    unless Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      updated_changesets_list = Enum.map(updated_changesets, &elem(&1, 1))

      # if the changeset struct is a block we put it directly,
      # but if it's an entry block we need to put it under the block association
      updated_changeset =
        if changeset.data.__struct__ == Brando.Content.Block do
          Changeset.put_assoc(
            changeset,
            :children,
            Enum.map(updated_changesets_list, &Brando.Utils.set_action/1)
          )
        else
          updated_block_changeset =
            changeset
            |> Changeset.get_assoc(:block)
            |> Changeset.put_assoc(
              :children,
              Enum.map(updated_changesets_list, &Brando.Utils.set_action/1)
            )

          Changeset.put_assoc(changeset, :block, updated_block_changeset)
        end

      if level == 0 do
        send_update(parent_cid, %{
          event: "provide_root_block",
          changeset: updated_changeset,
          uid: parent_uid,
          tag: tag
        })
      else
        send_update(parent_cid, %{
          event: "provide_child_block",
          changeset: updated_changeset,
          uid: parent_uid,
          tag: tag
        })
      end
    end

    {:ok, assign(socket, :changesets, updated_changesets)}
  end

  def update(%{event: "update_block", form: form}, socket) do
    {:ok, stream_insert(socket, :children_forms, form)}
  end

  def update(
        %{event: "insert_block", sequence: sequence, module_id: module_id, type: type},
        socket
      ) do
    module_id = String.to_integer(module_id)
    user_id = socket.assigns.current_user_id
    parent_id = nil
    sequence = (is_binary(sequence) && String.to_integer(sequence)) || sequence
    source = socket.assigns.block_module

    empty_block_cs = BlockField.build_block(module_id, user_id, parent_id, source, type)
    uid = Changeset.get_field(empty_block_cs, :uid)
    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    updated_block_list = List.insert_at(block_list, sequence, uid)

    block_form =
      to_change_form(
        empty_block_cs,
        %{sequence: sequence},
        user_id
      )

    changesets = socket.assigns.changesets
    updated_changesets = insert_child_changeset(changesets, uid, sequence)

    selector = "[data-block-uid=\"#{uid}\"]"

    socket
    |> stream_insert(:children_forms, block_form, at: sequence)
    |> assign(:has_children?, true)
    |> assign(:block_list, updated_block_list)
    |> assign(:changesets, updated_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(updated_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_ref", ref_name: ref_name, ref: new_ref_data}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?
    entry = socket.assigns.entry

    block_changeset = get_block_changeset(changeset, belongs_to)
    refs = Changeset.get_embed(block_changeset, :refs)

    new_refs =
      Enum.map(refs, fn ref ->
        if Changeset.get_field(ref, :name) == ref_name do
          new_ref_data_cs = Changeset.change(new_ref_data, %{uid: Brando.Utils.generate_uid()})

          ref
          |> Changeset.force_change(:data, new_ref_data_cs)
          |> Map.put(:action, nil)
          |> Changeset.apply_changes()
        else
          ref
        end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      else
        changeset = Changeset.put_embed(changeset, :refs, new_refs)
        render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> send_form_to_parent_stream()
    |> maybe_update_live_preview_block()
    |> then(&{:ok, &1})
  end

  def update(
        %{event: "update_ref_data", ref_name: ref_name, ref_data: ref_data},
        socket
      ) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?
    entry = socket.assigns.entry

    block_changeset = get_block_changeset(changeset, belongs_to)
    refs = Changeset.get_embed(block_changeset, :refs)

    new_refs =
      Enum.reduce(refs, [], fn
        %Changeset{action: :replace}, acc ->
          acc

        ref, acc ->
          if Changeset.get_field(ref, :name) == ref_name do
            block =
              ref
              |> Changeset.get_field(:data)
              |> Changeset.change()

            updated_block =
              Changeset.put_embed(block, :data, ref_data)

            acc ++ List.wrap(Changeset.force_change(ref, :data, updated_block))
          else
            acc ++ List.wrap(ref)
          end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      else
        changeset = Changeset.put_embed(changeset, :refs, new_refs)
        render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> maybe_update_live_preview_block()
    |> then(&{:ok, &1})
  end

  # update liquid splits for the block editor, and render the module for live preview
  def update(%{event: "update_entry_field", path: path, change: change}, socket) do
    liquid_splits = socket.assigns.liquid_splits
    entry = put_in(socket.assigns.entry, path, change)
    updated_liquid_splits = update_liquid_splits_entry_variables(liquid_splits, entry)

    socket
    |> assign(:entry, entry)
    |> assign(:liquid_splits, updated_liquid_splits)
    |> render_module()
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    socket
    |> assign(assigns)
    |> assign(:active, Changeset.get_field(changeset, :active))
    |> assign(:deleted, Changeset.get_field(changeset, :marked_as_deleted))
    |> assign(:form_has_changes, changeset.changes !== %{})
    |> assign(:form_is_new, !changeset.data.id)
    |> assign_new(:uid, fn -> Changeset.get_field(block_cs, :uid) end)
    |> assign_new(:path, fn %{uid: uid} -> assigns.parent_path ++ List.wrap(uid) end)
    |> assign_new(:type, fn -> Changeset.get_field(block_cs, :type) end)
    |> assign_new(:multi, fn -> Changeset.get_field(block_cs, :multi) end)
    |> assign_new(:has_vars?, fn -> Changeset.get_assoc(block_cs, :vars) !== [] end)
    |> assign_new(:has_table_rows?, fn -> Changeset.get_assoc(block_cs, :table_rows) !== [] end)
    |> assign_new(:parent_id, fn -> Changeset.get_field(block_cs, :parent_id) end)
    |> assign_new(:parent_module_id, fn -> nil end)
    |> assign_new(:containers, fn ->
      Brando.Content.list_containers!(%{order: "desc namespace, asc sequence"})
    end)
    |> assign_new(:fragments, fn ->
      Brando.Pages.list_fragments!(%{order: "asc language, asc title"})
    end)
    |> assign_new(:collapsed, fn -> Changeset.get_field(changeset, :collapsed) end)
    |> assign_new(:module_id, fn -> Changeset.get_field(block_cs, :module_id) end)
    |> assign_new(:container_id, fn -> Changeset.get_field(block_cs, :container_id) end)
    |> assign_new(:fragment_id, fn -> Changeset.get_field(block_cs, :fragment_id) end)
    |> assign_new(:has_children?, fn -> assigns.children !== [] end)
    |> assign_new(:available_identifiers, fn -> [] end)
    |> maybe_assign_children()
    |> maybe_assign_module()
    |> maybe_assign_container()
    |> maybe_assign_fragment()
    |> maybe_parse_module()
    |> maybe_render_module()
    |> maybe_get_live_preview_status()
    |> assign(:block_initialized, true)
    |> then(&{:ok, &1})
  end

  def update_changeset_data_block_var(socket, var_key, type, data) when type in [:file, :image] do
    assoc_data = Map.get(data, :type)

    uid = socket.assigns.uid
    changeset = socket.assigns.form.source
    belongs_to = socket.assigns.belongs_to
    load_path = (belongs_to == :root && [:data, :block, :vars]) || [:data, :vars]

    # is the block loaded?
    if Brando.Utils.try_path(changeset, load_path) do
      access_path =
        if belongs_to == :root do
          [
            Access.key(:data),
            Access.key(:block),
            Access.key(:vars),
            Access.filter(&(&1.key == var_key)),
            Access.key(type)
          ]
        else
          [
            Access.key(:data),
            Access.key(:vars),
            Access.filter(&(&1.key == var_key)),
            Access.key(type)
          ]
        end

      updated_changeset =
        put_in(
          changeset,
          access_path,
          assoc_data
        )

      updated_form =
        build_form_from_changeset(
          updated_changeset,
          uid,
          belongs_to
        )

      assign(socket, :form, updated_form)
    else
      socket
    end
  end

  def update_changeset_data_block_var(socket, var_key, :link, data) do
    identifier = Map.get(data, :identifier)
    uid = socket.assigns.uid
    changeset = socket.assigns.form.source
    belongs_to = socket.assigns.belongs_to
    load_path = (belongs_to == :root && [:data, :block, :vars]) || [:data, :vars]

    # is the block loaded?
    vars = Brando.Utils.try_path(changeset, load_path)
    loaded? = is_list(vars)

    if loaded? do
      access_path =
        if belongs_to == :root do
          [
            Access.key(:data),
            Access.key(:block),
            Access.key(:vars),
            Access.filter(&(&1.key == var_key)),
            Access.key(:identifier)
          ]
        else
          [
            Access.key(:data),
            Access.key(:vars),
            Access.filter(&(&1.key == var_key)),
            Access.key(:identifier)
          ]
        end

      updated_changeset = put_in(changeset, access_path, identifier)

      updated_form =
        build_form_from_changeset(
          updated_changeset,
          uid,
          belongs_to
        )

      assign(socket, :form, updated_form)
    else
      socket
    end
  end

  def update_changeset_data_block_var(socket, _, _, _), do: socket

  def maybe_get_live_preview_status(
        %{assigns: %{form_is_new: true, block_initialized: false}} = socket
      ) do
    form_cid = socket.assigns.form_cid
    cid = socket.assigns.myself
    send_update(form_cid, %{event: "get_live_preview_status", cid: cid})
    socket
  end

  def maybe_get_live_preview_status(socket) do
    socket
  end

  def render_module(%{assigns: %{belongs_to: belongs_to}} = socket) do
    changeset = socket.assigns.form.source
    entry = socket.assigns.entry
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    new_form =
      if belongs_to == :root do
        updated_changeset =
          render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)

        to_form(updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{socket.assigns.uid}"
        )
      else
        updated_changeset =
          render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)

        to_form(updated_changeset,
          as: "child_block",
          id: "child_block_form-#{socket.assigns.uid}"
        )
      end

    assign(socket, :form, new_form)
  end

  def maybe_render_module(%{assigns: %{belongs_to: :root, initial_render: false}} = socket) do
    changeset = socket.assigns.form.source
    entry = socket.assigns.entry
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    updated_changeset =
      render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)

    new_form =
      to_form(updated_changeset,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    assign(socket, :form, new_form)
  end

  def maybe_render_module(%{assigns: %{initial_render: false}} = socket) do
    changeset = socket.assigns.form.source
    entry = socket.assigns.entry
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    updated_changeset =
      render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)

    new_form =
      to_form(updated_changeset,
        as: "child_block",
        id: "child_block_form-#{uid}"
      )

    assign(socket, :form, new_form)
  end

  def maybe_render_module(socket) do
    socket
  end

  def register_block_wanting_entry(cid, form_cid) do
    send_update(form_cid, %{event: "register_block_wanting_entry", cid: cid})
  end

  def maybe_assign_container(%{assigns: %{container_id: nil}} = socket) do
    socket
    |> assign_new(:container, fn -> nil end)
    |> assign_new(:palette_options, fn ->
      Brando.Content.list_palettes!()
    end)
  end

  def maybe_assign_container(%{assigns: %{container_id: container_id}} = socket) do
    case get_container(container_id) do
      nil ->
        assign(socket, :container_not_found, true)

      container ->
        socket
        |> assign_new(:container, fn -> container end)
        |> assign_new(:palette_options, fn ->
          if container.allow_custom_palette do
            opts =
              if container.palette_namespace do
                %{filter: %{namespace: container.palette_namespace}}
              else
                %{}
              end

            Brando.Content.list_palettes!(opts)
          else
            []
          end
        end)
    end
  end

  def maybe_assign_fragment(%{assigns: %{fragment_id: nil}} = socket) do
    socket
    |> assign_new(:fragment, fn -> nil end)
  end

  def maybe_assign_fragment(%{assigns: %{fragment_id: fragment_id}} = socket) do
    case get_fragment(fragment_id) do
      nil -> assign(socket, :fragment_not_found, true)
      fragment -> assign_new(socket, :fragment, fn -> fragment end)
    end
  end

  def maybe_assign_module(%{assigns: %{module_id: nil}} = socket) do
    socket
    |> assign_new(:module_name, fn -> nil end)
    |> assign_new(:module_class, fn -> nil end)
    |> assign_new(:module_code, fn -> nil end)
    |> assign_new(:module_type, fn -> nil end)
    |> assign_new(:is_datasource?, fn -> false end)
    |> assign_new(:has_table_template?, fn -> false end)
    |> assign_new(:table_template, fn -> nil end)
    |> assign_new(:table_template_name, fn -> nil end)
    |> assign_new(:module_datasource_module, fn -> nil end)
    |> assign_new(:module_datasource_module_label, fn -> nil end)
    |> assign_new(:module_datasource_type, fn -> nil end)
    |> assign_new(:module_datasource_query, fn -> nil end)
    |> assign_new(:entry_template, fn -> nil end)
  end

  def maybe_assign_module(%{assigns: %{module_id: module_id}} = socket) do
    case get_module(module_id) do
      nil ->
        assign(socket, :module_not_found, true)

      module ->
        module_datasource_module =
          if module.datasource and module.datasource_module do
            module = Module.concat(List.wrap(module.datasource_module))
            domain = module.__naming__().domain
            schema = module.__naming__().schema

            gettext_module = module.__modules__().gettext
            gettext_domain = String.downcase("#{domain}_#{schema}_naming")
            msgid = Brando.Utils.humanize(module.__naming__().singular, :downcase)

            String.capitalize(Gettext.dgettext(gettext_module, gettext_domain, msgid))
          else
            ""
          end

        socket
        |> assign_new(:module_name, fn -> module.name end)
        |> assign_new(:module_class, fn -> module.class end)
        |> assign_new(:module_code, fn -> module.code end)
        |> assign_new(:module_type, fn -> module.type end)
        |> assign_new(:is_datasource?, fn -> module.datasource end)
        |> assign_new(:has_table_template?, fn -> (module.table_template_id && true) || false end)
        |> assign_new(:table_template, fn ->
          table_template_id = module.table_template_id

          if table_template_id do
            {:ok, table_template} =
              Brando.Content.get_table_template(%{
                matches: %{id: table_template_id},
                preload: [:vars]
              })

            table_template
          end
        end)
        |> assign_new(:table_template_name, fn %{table_template: table_template} ->
          if table_template do
            table_template.name
          end
        end)
        |> assign_new(:module_datasource_module, fn -> module.datasource_module end)
        |> assign_new(:module_datasource_module_label, fn -> module_datasource_module end)
        |> assign_new(:module_datasource_type, fn -> module.datasource_type end)
        |> assign_new(:module_datasource_query, fn -> module.datasource_query end)
        |> assign_new(:entry_template, fn -> module.entry_template end)
        |> maybe_register_block_wanting_entry()
    end
  end

  def maybe_register_block_wanting_entry(
        %{assigns: %{block_initialized: false, is_datasource?: true}} = socket
      ) do
    cid = socket.assigns.myself
    form_cid = socket.assigns.form_cid

    register_block_wanting_entry(cid, form_cid)
    socket
  end

  def maybe_register_block_wanting_entry(%{assigns: %{block_initialized: false}} = socket) do
    # check if the module code contains any entry variables. these can be in for loops, if/unless,
    # assign statements, or in the module code itself
    module_code = socket.assigns.module_code

    if Regex.run(~r/entry\.[a-zA-Z0-9_]+/, module_code) do
      cid = socket.assigns.myself
      form_cid = socket.assigns.form_cid

      register_block_wanting_entry(cid, form_cid)
    end

    socket
  end

  def maybe_register_block_wanting_entry(socket), do: socket

  @liquid_regex_strips ~r/(({% hide %}(?:.*?){% endhide %}))|((?:{%(?:-)? for (\w+) in [a-zA-Z0-9_.?|"-]+ (?:-)?%})(?:.*?)(?:{%(?:-)? endfor (?:-)?%}))|(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|({%(?:-)? assign .*? (?:-)?%})|(((?:{%(?:-)? if .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endif (?:-)?%})))|(((?:{%(?:-)? unless .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endunless (?:-)?%})))|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}|._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s
  @liquid_regex_splits ~r/{% (?:ref|headless_ref) refs.(\w+) %}|<.*?>|\{\{\s?(.*?)\s?\}\}|{% picture ([a-zA-Z0-9_.?|"-]+) {.*} %}/
  @liquid_regex_chunks ~r/^{% (?:ref|headless_ref) refs.(?<ref>\w+) %}$|^{{ (?<content>[\w\s.|\"\']+) }}$|^{% picture (?<picture>[a-zA-Z0-9_.?|"-]+) {.*} %}$/

  defp maybe_parse_module(%{assigns: %{module_not_found: true}} = socket), do: socket

  defp maybe_parse_module(
         %{assigns: %{module_code: module_code, module_type: :liquid} = assigns} = socket
       ) do
    block_initialized = assigns.block_initialized

    if not block_initialized do
      module_code =
        module_code
        |> liquid_strip_logic()
        |> emphasize_datasources(assigns)

      belongs_to = socket.assigns.belongs_to
      changeset = socket.assigns.form.source
      entry = socket.assigns.entry

      vars =
        if belongs_to == :root do
          changeset
          |> Changeset.get_field(:block)
          |> Changeset.change()
          |> Changeset.get_assoc(:vars)
        else
          Changeset.get_assoc(changeset, :vars)
        end

      splits =
        @liquid_regex_splits
        |> Regex.split(module_code, include_captures: true)
        |> Enum.map(fn chunk ->
          case Regex.run(@liquid_regex_chunks, chunk, capture: :all_names) do
            nil ->
              chunk

            ["content", "", ""] ->
              {:content, "content"}

            ["content | renderless", "", ""] ->
              {:content, "content"}

            ["entry." <> variable, "", ""] ->
              {:entry_variable, variable, liquid_render_entry_variable(variable, entry)}

            [module_variable, "", ""] ->
              {:module_variable, module_variable,
               liquid_render_module_variable(module_variable, vars)}

            ["", "entry." <> pic = pic_var, ""] ->
              {:entry_picture, pic_var, liquid_render_entry_picture_src(pic, socket.assigns)}

            ["", pic, ""] ->
              {:module_picture, pic, liquid_render_module_picture_src(pic, vars)}

            ["", "", ref] ->
              {:ref, ref}
          end
        end)

      socket
      |> assign(:liquid_splits, splits)
      |> assign(:vars, vars)
    else
      socket
    end
  end

  defp maybe_parse_module(socket) do
    assign(socket, liquid_splits: [], vars: [])
  end

  defp reset_position_response_tracker(socket) do
    block_list = socket.assigns.block_list
    assign(socket, :position_response_tracker, Enum.map(block_list, &{&1, false}))
  end

  # after we've sent messages to block asking for position updates, if we have deleted the
  # last child block, we refresh the live preview
  defp update_live_preview_on_empty_block_list(%{assigns: %{block_list: []}} = socket) do
    form_cid = socket.assigns.form_cid
    send_update(form_cid, %{event: "update_live_preview"})
    socket
  end

  defp update_live_preview_on_empty_block_list(socket) do
    socket
  end

  defp assign_available_identifiers(socket) do
    module = Module.concat([socket.assigns.module_datasource_module])
    query = socket.assigns.module_datasource_query
    entry = socket.assigns.entry

    {:ok, available_identifiers} =
      Brando.Datasource.list_selection(
        module,
        query,
        Map.get(entry, :language),
        socket.assigns.vars
      )

    assign(socket, :available_identifiers, available_identifiers)
  end

  # we don't touch the child form stream if the block is already initialized
  def maybe_assign_children(%{assigns: %{block_initialized: true}} = socket), do: socket

  def maybe_assign_children(%{assigns: %{children: []}} = socket) do
    socket
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> [] end)
    |> assign_new(:block_count, fn -> 0 end)
    |> stream(:children_forms, [])
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    current_user_id = socket.assigns.current_user_id

    children_forms =
      Enum.map(
        children,
        &to_change_form(&1, %{}, current_user_id)
      )

    socket
    |> stream(:children_forms, children_forms)
    |> assign_new(:block_count, fn -> Enum.count(children) end)
    |> assign_new(:changesets, fn -> Enum.map(children, &{&1.uid, nil}) end)
    |> assign_new(:block_list, fn -> Enum.map(children, & &1.uid) end)
  end

  def maybe_assign_children(
        %{assigns: %{type: :module, multi: true, children: children}} = socket
      ) do
    current_user_id = socket.assigns.current_user_id

    children_forms =
      Enum.map(
        children,
        &to_change_form(&1, %{}, current_user_id)
      )

    socket
    |> stream(:children_forms, children_forms)
    |> assign_new(:block_count, fn -> Enum.count(children) end)
    |> assign_new(:changesets, fn -> Enum.map(children, &{&1.uid, nil}) end)
    |> assign_new(:block_list, fn -> Enum.map(children, & &1.uid) end)
  end

  def maybe_assign_children(socket) do
    socket
    |> assign_new(:block_count, fn -> 0 end)
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> [] end)
  end

  def send_child_position_update(socket, block_list) do
    # send_update to all components in block_list
    parent_id = socket.assigns.id

    for {block_uid, idx} <- Enum.with_index(block_list) do
      id = "#{parent_id}-child-#{block_uid}"
      send_update(__MODULE__, id: id, event: "update_sequence", sequence: idx)
    end

    socket
  end

  def update_child_changeset(changesets, uid, new_changeset) do
    Enum.map(changesets, fn
      {^uid, _changeset} -> {uid, new_changeset}
      {uid, changeset} -> {uid, changeset}
    end)
  end

  def insert_child_changeset(changesets, uid, position) do
    List.insert_at(changesets, position, {uid, nil})
  end

  def delete_child_changeset(changesets, uid) do
    Enum.reject(changesets, fn
      {^uid, _} -> true
      _ -> false
    end)
  end

  def render(%{module_not_found: true} = assigns) do
    ~H"""
    <div class="alert danger text-mono">
      <div>
        Missing module — #<%= inspect(assigns.module_id) %>.<br /><br />
        If this is a mistake, you can hopefully undelete the module.<br /><br />
        If you're sure the module is gone, you can
        <button type="button" phx-click="delete_block" phx-target={@myself}>
          delete this block.
        </button>
      </div>
    </div>
    """
  end

  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div data-module-multi="true">
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        multi={true}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        module_class={@module_class}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        parent_uploads={@parent_uploads}
        target={@myself}
        insert_block={JS.push("insert_block", target: @myself)}
        insert_multi_block={JS.push("insert_block_entry", value: %{multi: true}, target: @myself)}
        insert_child_block={JS.push("insert_block", value: %{multi: true}, target: @myself)}
        has_children?={@has_children?}
        module_name={@module_name}
      >
        <div
          :if={@has_children?}
          id={"#{@id}-children"}
          class="block-children"
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
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            data-parent_uid={@uid}
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              dom_id={id}
              multi={child_block_form[:multi].value}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              live_preview_active?={@live_preview_active?}
              live_preview_cache_key={@live_preview_cache_key}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_path={@path}
              parent_uploads={@parent_uploads}
              parent_module_id={@module_id}
              form={child_block_form}
              form_cid={@form_cid}
              entry={@entry}
              current_user_id={@current_user_id}
              belongs_to={:multi}
              level={@level + 1}
            />
          </div>
        </div>
      </.module>
    </div>
    """
  end

  def render(%{type: :module} = assigns) do
    ~H"""
    <div>
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        parent_uploads={@parent_uploads}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        target={@myself}
        module_class={@module_class}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        insert_block={JS.push("insert_block", target: @myself)}
        has_children?={false}
        module_name={@module_name}
        module_datasource_module_label={@module_datasource_module_label}
        module_datasource_type={@module_datasource_type}
        module_datasource_query={@module_datasource_query}
        available_identifiers={@available_identifiers}
      />
    </div>
    """
  end

  def render(%{type: :module_entry} = assigns) do
    ~H"""
    <div>
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        parent_uploads={@parent_uploads}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        target={@myself}
        module_class={@module_class}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        insert_block={JS.push("insert_block_entry", target: @myself)}
        has_children?={false}
        module_name={@module_name}
      />
    </div>
    """
  end

  def render(%{type: :container} = assigns) do
    ~H"""
    <div>
      <.container
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        block_module={@block_module}
        deleted={@deleted}
        target={@myself}
        palette_options={@palette_options}
        container={@container}
        containers={@containers}
        insert_block={JS.push("insert_block", target: @myself)}
        insert_child_block={JS.push("insert_block", value: %{container: true}, target: @myself)}
        has_children?={@has_children?}
      >
        <div
          :if={@has_children?}
          id={"#{@id}-children"}
          class="block-children"
          phx-update="stream"
          phx-hook="Brando.SortableBlocks"
          data-sortable-id="sortable-blocks"
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <div
            :for={{id, child_block_form} <- @streams.children_forms}
            id={id}
            data-id={child_block_form[:id].value}
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            data-parent_uid={@uid}
            class="draggable"
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              dom_id={id}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              live_preview_active?={@live_preview_active?}
              live_preview_cache_key={@live_preview_cache_key}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_path={@path}
              parent_uploads={@parent_uploads}
              entry={@entry}
              form={child_block_form}
              form_cid={@form_cid}
              current_user_id={@current_user_id}
              belongs_to={:container}
              level={@level + 1}
            >
            </.live_component>
          </div>
        </div>
        <%!-- <.plus click={@insert_child_block} /> --%>
      </.container>
    </div>
    """
  end

  def render(%{type: :fragment} = assigns) do
    ~H"""
    <div>
      <.fragment_block
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        fragment={@fragment}
        fragments={@fragments}
        belongs_to={@belongs_to}
        insert_block={JS.push("insert_block", target: @myself)}
        deleted={@deleted}
        target={@myself}
        block_module={@block_module}
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="font-family: Mono; font-size: 11px;">
      <code>
        <pre>
      ERROR: Unknown block type

      Assign keys:

      <%= inspect Map.keys(assigns), pretty: true, width: 0 %>

      - type: <%= inspect @type %>
      - multi: <%= inspect @multi %>
      </pre>
      </code>
    </div>
    """
  end

  ##
  ## Function components

  attr :form, :any
  attr :dirty, :any
  attr :new, :any
  attr :level, :any
  attr :belongs_to, :any
  attr :deleted, :any
  attr :target, :any
  attr :block_module, :any
  attr :insert_block, :any
  attr :fragment, :any, default: nil
  attr :fragments, :list, default: []

  def fragment_block(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:fragment_id, Changeset.get_field(block_cs, :fragment_id))
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty"
      ]}
    >
      <.plus click={@insert_block} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-fragment-id={@fragment_id}
        class={["block"]}
        phx-hook="Brando.Block"
      >
        <.form
          for={@form}
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-target={@target}
        >
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields block_form={block_form} block_module={@block_module} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={false}
                config={true}
                block={block_form}
                target={@target}
                palette={nil}
                container={nil}
                is_ref?={false}
                is_datasource?={false}
                has_table_template?={false}
              >
                <:description>
                  <%= if @fragment do %>
                    [<%= @fragment.parent_key %>/<strong><%= @fragment.key %></strong>] <%= @fragment.title %> — <%= @fragment.language %>
                  <% end %>
                </:description>
              </.toolbar>
              <.fragment_config
                uid={@uid}
                block={block_form}
                target={@target}
                fragment={@fragment}
                fragments={@fragments}
              />
              <div class="block-content">
                <div class="block-fragment-wrapper">
                  <div
                    class="fragment-info"
                    phx-click="show_fragment_instructions"
                    phx-target={@target}
                  >
                    <div class="icon">
                      <span class="hero-puzzle-piece"></span>
                    </div>
                    <div class="info">
                      <span class="fragment-label">
                        <%= gettext("Embedded") %><br /> <%= gettext("fragment") %>
                      </span>
                    </div>
                  </div>

                  <div :if={!@fragment_id} class="block-instructions">
                    <p>
                      <%= gettext(
                        "This block embeds a fragment as a block, but no fragment is currently selected."
                      ) %>
                    </p>
                    <button
                      type="button"
                      class="tiny"
                      phx-click={show_modal("#block-#{@uid}_config")}
                      phx-target={@target}
                    >
                      <%= gettext("Add fragment") %>
                    </button>
                  </div>
                  <div :if={@fragment} class="fragment-info"></div>
                </div>
              </div>
            </.inputs_for>
          <% else %>
            <section class="alert danger">
              <%= gettext("This block is currently not allowed to be a child block :(") %>
            </section>
          <% end %>
        </.form>
      </div>
    </div>
    """
  end

  def container(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to

    block_cs = get_block_changeset(changeset, belongs_to)
    palette = Changeset.get_assoc(block_cs, :palette, :struct)
    bg_color = extract_block_bg_color(palette)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:container_id, Changeset.get_field(block_cs, :container_id))
      |> assign(:description, Changeset.get_field(block_cs, :description))
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))
      |> assign(:palette, palette)
      |> assign(:bg_color, bg_color)

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty"
      ]}
    >
      <.plus click={@insert_block} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-container-id={@container_id}
        class="block"
        phx-hook="Brando.Block"
        style={"background-color: #{@bg_color}"}
      >
        <.form
          for={@form}
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-target={@target}
        >
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields block_form={block_form} block_module={@block_module} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={false}
                config={true}
                block={block_form}
                target={@target}
                palette={@palette}
                container={@container}
                is_ref?={false}
                is_datasource?={false}
                has_table_template?={false}
                has_children?={@has_children?}
              />
              <.container_config
                uid={@uid}
                block={block_form}
                target={@target}
                palette={@palette}
                palette_options={@palette_options}
                container={@container}
                containers={@containers}
              />
            </.inputs_for>
          <% else %>
            <section class="alert danger">
              <%= gettext("This block is currently not allowed to be a child block :(") %>
            </section>
          <% end %>
        </.form>
        <%= if @has_children? do %>
          <%= render_slot(@inner_block) %>
          <.plus click={@insert_child_block} />
        <% else %>
          <div class="blocks-empty-instructions">
            <%= gettext("Click the plus to start adding content blocks") %>
          </div>
          <.plus click={@insert_child_block} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form
  attr :dirty, :boolean, default: false
  attr :new, :boolean, default: false
  attr :level, :integer
  attr :belongs_to, :atom
  attr :deleted, :boolean, default: false
  attr :is_datasource?, :boolean, default: false
  attr :has_table_template?, :boolean, default: false
  attr :table_template_name, :string
  attr :module_class, :string, default: nil
  attr :block_module, :atom
  attr :vars, :list, default: []
  attr :parent_uploads, :list, default: []
  attr :target, :any
  attr :has_children?, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :liquid_splits, :any, default: []
  attr :insert_block, :any, default: nil
  attr :insert_child_block, :any, default: nil
  attr :insert_multi_block, :any, default: nil
  attr :module_name, :string, default: nil
  attr :module_datasource_module_label, :string, default: ""
  attr :module_datasource_type, :string, default: ""
  attr :module_datasource_query, :string, default: ""
  attr :available_identifiers, :any, default: []
  slot :inner_block

  def module(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:module_id, Changeset.get_field(block_cs, :module_id))
      |> assign(:description, Changeset.get_field(block_cs, :description))
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty"
      ]}
    >
      <.plus click={@insert_block} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-module-id={@module_id}
        class="block"
        phx-hook="Brando.Block"
      >
        <.form
          for={@form}
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-target={@target}
        >
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields block_form={block_form} block_module={@block_module} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={@multi}
                config={true}
                block={block_form}
                target={@target}
                is_ref?={false}
                is_datasource?={@is_datasource?}
                has_children?={@has_children?}
              >
                <:description>
                  <%= @module_name %>
                </:description>
              </.toolbar>

              <.module_config uid={@uid} block_form={block_form} target={@target} />
              <.module_content
                uid={@uid}
                block_form={block_form}
                liquid_splits={@liquid_splits}
                module_class={@module_class}
                parent_uploads={@parent_uploads}
                has_table_template?={@has_table_template?}
                table_template_name={@table_template_name}
                target={@target}
                is_datasource?={@is_datasource?}
                module_datasource_module_label={@module_datasource_module_label}
                module_datasource_type={@module_datasource_type}
                module_datasource_query={@module_datasource_query}
                available_identifiers={@available_identifiers}
                block_identifiers={block_form[:block_identifiers]}
              />
            </.inputs_for>
          <% else %>
            <Input.hidden field={@form[:sequence]} />
            <input type="hidden" name={@form[:id].name} value={@form[:id].value} />
            <.hidden_block_fields block_form={@form} block_module={@block_module} />

            <.toolbar
              uid={@uid}
              collapsed={@collapsed}
              config={true}
              type={@type}
              block={@form}
              target={@target}
              is_ref?={false}
              is_datasource?={@is_datasource?}
              has_children?={@has_children?}
            >
              <:description>
                <%= @module_name %>
              </:description>
            </.toolbar>

            <.module_config uid={@uid} block_form={@form} target={@target} />
            <.module_content
              uid={@uid}
              block_form={@form}
              liquid_splits={@liquid_splits}
              module_class={@module_class}
              has_table_template?={@has_table_template?}
              table_template_name={@table_template_name}
              parent_uploads={@parent_uploads}
              target={@target}
              is_datasource?={@is_datasource?}
              module_datasource_module_label={@module_datasource_module_label}
              module_datasource_type={@module_datasource_type}
              module_datasource_query={@module_datasource_query}
              available_identifiers={@available_identifiers}
              block_identifiers={@form[:block_identifiers]}
            />
          <% end %>
        </.form>
        <%= if @has_children? do %>
          <%= render_slot(@inner_block) %>
          <.plus click={@insert_multi_block} />
        <% else %>
          <%= if @multi do %>
            <div class="blocks-empty-instructions">
              <%= gettext("Click the plus to start adding content blocks") %>
            </div>
            <.plus click={@insert_multi_block} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def module_content(assigns) do
    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars vars={@block_form[:vars]} uid={@uid} target={@target} />
        <.datasource
          :if={@is_datasource?}
          block_data={@block_form}
          uid={@uid}
          module_datasource_module_label={@module_datasource_module_label}
          module_datasource_type={@module_datasource_type}
          module_datasource_query={@module_datasource_query}
          available_identifiers={@available_identifiers}
          block_identifiers={@block_identifiers}
          target={@target}
        />
        <div :if={@has_table_template?} class="block-table" id={"block-#{@uid}-block-table"}>
          <.table
            block_data={@block_form}
            uid={@uid}
            target={@target}
            table_template_name={@table_template_name}
          />
        </div>
        <div class="block-splits">
          <%= for split <- @liquid_splits do %>
            <%= case split do %>
              <% {:ref, ref} -> %>
                <.ref
                  parent_uploads={@parent_uploads}
                  refs_field={@block_form[:refs]}
                  ref_name={ref}
                  target={@target}
                />
              <% {:content, _} -> %>
                <div class="split_content"></div>
              <% {:entry_variable, var_name, variable_value} -> %>
                <div
                  phx-no-format
                  class="rendered-variable"
                  data-popover={
                    gettext("Edit the entry directly to affect this variable [entry.%{var_name}]",
                      var_name: var_name
                    )
                  }
                ><%= variable_value %></div>
              <% {:module_variable, var_name, variable_value} -> %>
                <div
                  phx-no-format
                  class="rendered-variable"
                  data-popover={
                    gettext("Edit the module variable to affect this variable [%{var_name}]",
                      var_name: var_name
                    )
                  }
                ><%= variable_value %></div>
              <% {:entry_picture, _, img_src} -> %>
                <figure>
                  <img src={img_src} />
                </figure>
              <% {:module_picture, _, img_src} -> %>
                <figure>
                  <img src={img_src} />
                </figure>
              <% _ -> %>
                <%= raw(split) %>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def hidden_block_fields(assigns) do
    ~H"""
    <div class="hidden-block-fields">
      <Input.hidden field={@block_form[:uid]} />
      <Input.hidden field={@block_form[:type]} />
      <Input.hidden field={@block_form[:anchor]} />
      <Input.hidden field={@block_form[:multi]} />
      <Input.hidden field={@block_form[:module_id]} />
      <Input.hidden field={@block_form[:parent_id]} />
      <Input.hidden field={@block_form[:creator_id]} />
      <Input.hidden field={@block_form[:marked_as_deleted]} />
      <Input.input type={:hidden} field={@block_form[:source]} value={@block_module} />
    </div>
    """
  end

  attr :uid, :string, required: true
  attr :block_form, :any, required: true
  attr :target, :any, required: true

  def module_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <Input.text
            field={@block_form[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
          <Input.text
            field={@block_form[:anchor]}
            instructions={gettext("Anchor available to block.")}
          />
          <.vars vars={@block_form[:vars]} uid={@uid} important={false} target={@target} />
          <div>
            UID: <span class="text-mono"><%= @uid %></span>
          </div>
        </div>
        <div class="panel">
          <h2 class="titlecase">Vars</h2>
          <.inputs_for :let={var} field={@block_form[:vars]}>
            <div class="var">
              <div class="key"><%= var[:key].value %></div>
              <div class="buttons">
                <button
                  type="button"
                  class="tiny"
                  phx-click={JS.push("reset_var", target: @target)}
                  phx-value-id={var[:key].value}
                >
                  <%= gettext("Reset") %>
                </button>
                <button
                  type="button"
                  class="tiny"
                  phx-click={JS.push("delete_var", target: @target)}
                  phx-value-id={var[:key].value}
                >
                  <%= gettext("Delete") %>
                </button>
              </div>
            </div>
          </.inputs_for>

          <h2 class="titlecase">Refs</h2>
          <.inputs_for :let={ref} field={@block_form[:refs]}>
            <div class="ref">
              <div class="key"><%= ref[:name].value %></div>
              <button
                type="button"
                class="tiny"
                phx-click={JS.push("reset_ref", target: @target)}
                phx-value-id={ref[:name].value}
              >
                <%= gettext("Reset") %>
              </button>
            </div>
          </.inputs_for>
          <h2 class="titlecase"><%= gettext("Advanced") %></h2>
          <div class="button-group-vertical">
            <button
              type="button"
              class="secondary"
              phx-click={JS.push("fetch_missing_refs", target: @target)}
            >
              <%= gettext("Fetch missing refs") %>
            </button>
            <button type="button" class="secondary" phx-click={JS.push("reset_refs", target: @target)}>
              <%= gettext("Reset all block refs") %>
            </button>
            <button
              type="button"
              class="secondary"
              phx-click={JS.push("fetch_missing_vars", target: @target)}
            >
              <%= gettext("Fetch missing vars") %>
            </button>
            <button type="button" class="secondary" phx-click={JS.push("reset_vars", target: @target)}>
              <%= gettext("Reset all variables") %>
            </button>
          </div>
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          <%= gettext("Close") %>
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :uid, :string, required: true
  attr :block, :any, required: true
  attr :fragment, :any, default: nil
  attr :fragments, :list, default: []
  attr :target, :any, required: true

  def fragment_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <.live_component
            module={Input.Select}
            id={"#{@block.id}-fragment-select"}
            field={@block[:fragment_id]}
            label={gettext("Fragment")}
            opts={[options: @fragments]}
            publish
          />
          <Input.text field={@block[:anchor]} />
          <Input.text
            field={@block[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          <%= gettext("Close") %>
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :uid, :string, required: true
  attr :block, :any, required: true
  attr :palette, :any, required: true
  attr :container, :any, default: nil
  attr :containers, :list, default: []
  attr :palette_options, :any, default: []
  attr :target, :any, required: true

  def container_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <.live_component
            module={Input.Select}
            id={"#{@block.id}-container-select"}
            field={@block[:container_id]}
            label={gettext("Container template")}
            opts={[options: @containers, resetable: true]}
            publish
          />
          <%= if @palette_options do %>
            <.live_component
              module={Input.Select}
              id={"#{@block.id}-palette-select"}
              field={@block[:palette_id]}
              label={gettext("Palette")}
              opts={[options: @palette_options]}
              publish
            />
          <% else %>
            <Input.hidden field={@block[:palette_id]} />
          <% end %>
          <Input.text field={@block[:anchor]} />
          <Input.text
            field={@block[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          <%= gettext("Close") %>
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :ref_name, :string, required: true
  attr :refs_field, :any, required: true
  attr :parent_uploads, :any, required: true
  attr :target, :any, required: true

  def ref(assigns) do
    refs = Changeset.get_embed(assigns.refs_field.form.source, :refs, :struct)
    ref_names = Enum.map(refs, & &1.name)
    ref_found = Enum.member?(ref_names, assigns.ref_name)

    assigns =
      assigns
      |> assign(:ref_found, ref_found)
      |> assign(:ref_names, ref_names)

    ~H"""
    <%= if @ref_found do %>
      <.inputs_for :let={ref_form} field={@refs_field} skip_hidden>
        <%= if ref_form[:name].value == @ref_name do %>
          <section b-ref={ref_form[:name].value}>
            <.polymorphic_embed_inputs_for :let={block} field={ref_form[:data]}>
              <.dynamic_block
                id={block[:uid].value}
                block_id={block[:uid].value}
                is_ref?={true}
                ref_name={ref_form[:name].value}
                ref_description={ref_form[:description].value}
                block={block}
                parent_uploads={@parent_uploads}
                target={@target}
              />
            </.polymorphic_embed_inputs_for>
            <Input.input type={:hidden} field={ref_form[:description]} />
            <Input.input type={:hidden} field={ref_form[:name]} />
            <Input.input type={:hidden} field={ref_form[:id]} />
          </section>
        <% end %>
      </.inputs_for>
    <% else %>
      <section class="alert danger">
        Ref <code><%= @ref_name %></code>
        is missing!<br /><br />
        If the module has been changed, this block might be out of sync!<br /><br />
        Available refs are:<br /><br />
        <div :for={ref_name <- @ref_names}>
          &rarr; <%= ref_name %><br />
        </div>
      </section>
    <% end %>
    """
  end

  def handle(assigns) do
    ~H"""
    <div
      class="sort-handle block-action"
      data-sortable-group={1}
      data-popover={gettext("Reposition block (click&drag)")}
    >
      <.icon name="hero-arrows-up-down" />
    </div>
    """
  end

  def dynamic_block(assigns) do
    assigns =
      assigns
      |> assign_new(:insert_module, fn -> nil end)
      |> assign_new(:duplicate_block, fn -> nil end)
      |> assign_new(:belongs_to, fn -> nil end)
      |> assign_new(:is_ref?, fn -> false end)
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:ref_name, fn -> nil end)
      |> assign_new(:ref_description, fn -> nil end)
      |> assign_new(:block_id, fn -> assigns.block[:uid].value end)
      |> assign_new(:component_target, fn ->
        type_atom = assigns.block[:type].value |> String.to_existing_atom()

        block_type =
          (type_atom
           |> to_string
           |> Macro.camelize()) <> "Block"

        block_module = Module.concat([Blocks, block_type])

        case Code.ensure_compiled(block_module) do
          {:module, _} -> block_module
          _ -> Function.capture(__MODULE__, type_atom, 1)
        end
      end)

    assigns =
      if is_nil(assigns.block_id) do
        random_id = Brando.Utils.generate_uid()

        block =
          put_in(
            assigns.block,
            [Access.key(:source), Access.key(:data), Access.key(:uid)],
            random_id
          )

        assigns
        |> assign(:block_id, random_id)
        |> assign(:block, block)
      else
        assigns
      end

    ~H"""
    <%= if is_function(@component_target) do %>
      <%= component(
        @component_target,
        assigns,
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      ) %>
    <% else %>
      <.live_component
        module={@component_target}
        id={@block_id}
        block={@block}
        is_ref?={@is_ref?}
        opts={@opts}
        belongs_to={@belongs_to}
        ref_name={@ref_name}
        ref_description={@ref_description}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
        parent_uploads={@parent_uploads}
        target={@target}
      />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :block, :any, required: true
  attr :multi, :boolean, default: false
  attr :wide_config, :boolean, default: false
  attr :type, :any
  attr :block_type, :any
  attr :is_datasource?, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :datasource, :any
  attr :bg_color, :string, default: nil
  attr :uid, :any

  slot :inner_block
  slot :config
  slot :config_footer
  slot :description
  slot :instructions

  def block(assigns) do
    block_cs = assigns.block.source
    uid = Changeset.get_field(block_cs, :uid) || Brando.Utils.generate_uid()

    assigns =
      assigns
      |> assign_new(:block_type, fn ->
        Changeset.get_field(block_cs, :type) || (assigns.is_entry? && "entry")
      end)
      |> assign(:uid, uid)
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))
      |> assign(:marked_as_deleted, Changeset.get_field(block_cs, :marked_as_deleted))

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        "ref-block",
        @collapsed && "collapsed",
        !@active && "disabled"
      ]}
    >
      <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={@wide_config}>
        <%= if @config do %>
          <%= render_slot(@config) %>
        <% end %>
        <:footer>
          <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
            <%= gettext("Close") %>
          </button>
          <%= if @config_footer do %>
            <%= render_slot(@config_footer) %>
          <% end %>
        </:footer>
      </Content.modal>

      <Input.input type={:hidden} field={@block[:uid]} />
      <Input.input type={:hidden} field={@block[:type]} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@block_type}
        style={"background-color: #{@bg_color}"}
        class={["block", "ref_block"]}
        phx-hook="Brando.Block"
      >
        <.toolbar
          uid={@uid}
          collapsed={@collapsed}
          config={@config}
          type={@block_type}
          block={@block}
          target={@target}
          multi={@multi}
          is_ref?={@is_ref?}
          is_datasource?={false}
        >
          <:description>
            <%= render_slot(@description) %>
          </:description>
        </.toolbar>

        <div class="block-content" id={"block-#{@uid}-block-content"}>
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  ##
  ## Ref blocks

  def html(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="html-block">
            <Input.code field={block_data[:text]} label={gettext("Text")} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def markdown(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="markdown-block">
            <Input.code field={block_data[:text]} label={gettext("Text")} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def comment(assigns) do
    block_data_cs = get_block_data_changeset(assigns.block)

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text, Changeset.get_field(block_data_cs, :text))

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= gettext("Not shown...") %>
          </:description>
          <:config>
            <div id={"block-#{@uid}-conf-textarea"}>
              <Input.textarea field={block_data[:text]} />
            </div>
          </:config>
          <div id={"block-#{@uid}-comment"}>
            <%= if @text do %>
              <%= @text |> raw() %>
            <% end %>
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def input(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="alert">
            <Input.text
              field={block_data[:value]}
              label={block_data[:label].value}
              instructions={block_data[:help_text].value}
              placeholder={block_data[:placeholder].value}
            />
            <Input.hidden field={block_data[:placeholder]} />
            <Input.hidden field={block_data[:label]} />
            <Input.hidden field={block_data[:type]} />
            <Input.hidden field={block_data[:help_text]} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def header(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            (H<%= block_data[:level].value %>)<%= if @ref_description do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <:config>
            <Input.radios
              field={block_data[:level]}
              label="Level"
              uid={@uid}
              id_prefix="block_data"
              id={"block-#{@uid}-data-level"}
              opts={[
                options: [
                  %{label: "H1", value: 1},
                  %{label: "H2", value: 2},
                  %{label: "H3", value: 3},
                  %{label: "H4", value: 4},
                  %{label: "H5", value: 5},
                  %{label: "H6", value: 6}
                ]
              ]}
            />
            <Input.text field={block_data[:id]} label="ID" />
            <Input.text field={block_data[:link]} label="Link" />
          </:config>
          <div class="header-block">
            <Input.input
              type={:textarea}
              field={block_data[:text]}
              class={"h#{block_data[:level].value}"}
              phx-debounce={750}
              data-autosize={true}
              phx-update="ignore"
              rows={1}
            />
            <Input.input type={:hidden} field={block_data[:class]} />
            <Input.input type={:hidden} field={block_data[:placeholder]} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def text(assigns) do
    block_data_cs = get_block_data_changeset(assigns.block)

    extensions =
      case Changeset.get_field(block_data_cs, :extensions) do
        nil -> "all"
        extensions when is_list(extensions) -> Enum.join(extensions, "|")
        extensions -> extensions
      end

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text_type, Changeset.get_field(block_data_cs, :type))
      |> assign(:extensions, extensions)

    ~H"""
    <.inputs_for :let={text_block_data} field={@block[:data]}>
      <div id={"ref-#{@uid}-wrapper"} data-block-uid={@uid}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in [nil, ""] do %>
              <%= @ref_description %>
            <% else %>
              <%= @text_type %>
            <% end %>
          </:description>
          <:config>
            <Input.radios
              field={text_block_data[:type]}
              label="Type"
              opts={[
                options: [
                  %{label: "Paragraph", value: "paragraph"},
                  %{label: "Lede", value: "lede"}
                ]
              ]}
            />
            <%= if @extensions == "all" do %>
              <Input.hidden field={text_block_data[:extensions]} />
            <% else %>
              <Form.array_inputs
                :let={%{value: array_value, name: array_name}}
                field={text_block_data[:extensions]}
              >
                <input type="hidden" name={array_name} value={array_value} />
              </Form.array_inputs>
            <% end %>
          </:config>
          <div class={["text-block", @text_type]}>
            <div class="tiptap-wrapper" id={"block-#{@uid}-rich-text-wrapper"}>
              <div
                id={"block-#{@uid}-rich-text"}
                data-block-uid={@uid}
                data-tiptap-extensions={@extensions}
                phx-hook="Brando.TipTap"
                data-name="TipTap"
              >
                <div
                  id={"block-#{@uid}-rich-text-target-wrapper"}
                  class="tiptap-target-wrapper"
                  phx-update="ignore"
                >
                  <div id={"block-#{@uid}-rich-text-target"} class="tiptap-target"></div>
                </div>
                <Input.input
                  type={:hidden}
                  field={text_block_data[:text]}
                  class="tiptap-text"
                  phx-debounce={750}
                />
              </div>
            </div>
          </div>
        </.block>
      </div>
    </.inputs_for>
    """
  end

  attr :click, :any, required: true

  def plus(assigns) do
    ~H"""
    <button class="block-plus" type="button" phx-click={@click}>
      <.icon name="hero-plus" />
    </button>
    """
  end

  attr :uid, :string, required: true
  attr :vars, :any, required: true
  attr :important, :boolean, default: true
  attr :target, :any

  def vars(assigns) do
    changeset = assigns.vars.form.source

    vars_to_render =
      changeset
      |> Changeset.get_assoc(:vars)
      |> Enum.filter(&(Changeset.get_field(&1, :important) == assigns.important))

    assigns = assign(assigns, :vars_to_render, vars_to_render)

    ~H"""
    <div :if={@vars_to_render != []} class="block-vars-wrapper">
      <div class="vars-info" phx-click="show_vars_instructions" phx-target={@target}>
        <div class="icon">
          <span class="hero-variable-mini"></span>
        </div>
        <div class="info">
          <span class="vars-label">
            <%= gettext("Block") %><br /> <%= gettext("Variables") %>
          </span>
        </div>
      </div>
      <div class="block-vars">
        <.inputs_for :let={var} field={@vars}>
          <.live_component
            module={RenderVar}
            id={"block-#{@uid}-render-var-#{@important && "important" || "regular"}-#{var.id}"}
            var={var}
            render={(@important && :only_important) || :only_regular}
            on_change={fn params -> send_update(@target, params) end}
            publish
          />
        </.inputs_for>
      </div>
    </div>
    """
  end

  attr :uid, :string, required: true
  attr :collapsed, :boolean, default: false
  attr :type, :string
  attr :block, Phoenix.HTML.Form, required: true
  attr :target, :any, required: true
  attr :has_table_template?, :boolean, default: false
  attr :has_children?, :boolean, default: false
  attr :is_datasource?, :boolean, default: false
  attr :instructions, :string, default: nil
  attr :config, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :palette, :any, default: nil
  attr :container, :any, default: nil
  attr :module_datasource_module_label, :string, default: nil
  attr :module_datasource_type, :any, default: nil
  attr :module_datasource_query, :any, default: nil
  attr :available_identifiers, :list, default: []

  slot :inner_block
  slot :description, default: nil

  def toolbar(assigns) do
    ~H"""
    <div class="block-toolbar">
      <div class="block-description">
        <Form.label field={@block[:active]} class="switch small inverse">
          <Input.input type={:checkbox} field={@block[:active]} />
          <div class="slider round"></div>
        </Form.label>
        <span class="block-type">
          <span :if={@is_datasource?} class="datasource">
            <%= gettext("Datamodule") %> |
          </span>
          <span :if={@type == :module and not @is_datasource?} phx-no-format>
            <%= if @multi do %>Multi <% end %><%= gettext("Module") %> |
          </span>
          <span :if={@type == :module_entry}>
            <%= gettext("Entry") %> |
          </span>
          <span :if={@type == :container}>
            <%= gettext("Container") %> |
          </span>
          <span :if={@type == :fragment}>
            <%= gettext("Fragment") %> |
          </span>
        </span>
        <span :if={@description} class="block-name">
          <%= render_slot(@description) %>
        </span>
        <%= if @type == :container do %>
          <%= if @container do %>
            <%= @container.name %>
          <% else %>
            Standard
          <% end %>
          <%= if @palette do %>
            <div class="arrow">&rarr;</div>
            <button type="button" class="btn-palette" phx-click={show_modal("#block-#{@uid}_config")}>
              <%= @palette.name %>
            </button>
            <div class="circle-stack">
              <span
                :for={color <- Enum.reverse(@palette.colors)}
                class="circle tiny"
                style={"background-color:#{color.hex_value}"}
                data-popover={"#{color.name}"}
              >
              </span>
            </div>
            <div :if={@block[:anchor].value} class="container-target">
              &nbsp;|&nbsp;#<%= @block[:anchor].value %>
            </div>
          <% else %>
            <div class="arrow">&rarr;</div>
            <button type="button" class="btn-palette" phx-click={show_modal("#block-#{@uid}_config")}>
              <%= gettext("<No palette>") %>
            </button>
          <% end %>
          <span :if={@block[:description].value not in ["", nil]} class="description">
            <%= @block[:description].value %>
          </span>
        <% else %>
          <span :if={@block[:description].value not in ["", nil]} class="description">
            <%= @block[:description].value %>
          </span>
        <% end %>
      </div>
      <div class="block-content" id={"block-#{@uid}-block-content"}>
        <%= render_slot(@inner_block) %>
      </div>
      <div class="block-actions" id={"block-#{@uid}-block-actions"}>
        <.handle :if={!@is_ref?} />
        <div
          :if={@instructions}
          class="block-action help"
          phx-click={JS.push("toggle_help", target: @target)}
          data-popover={gettext("Show instructions")}
        >
          <.icon name="hero-question-mark-circle" />
        </div>
        <button
          :if={@is_ref? == false && @has_children? == false}
          type="button"
          phx-value-block_uid={@uid}
          class="block-action duplicate"
          phx-click="duplicate_block"
          phx-target={@target}
          data-popover={gettext("Duplicate block")}
        >
          <.icon name="hero-document-duplicate" />
        </button>
        <button
          :if={@config}
          type="button"
          class="block-action config"
          phx-click={show_modal("#block-#{@uid}_config")}
          data-popover={gettext("Configure block")}
        >
          <.icon name="hero-cog-8-tooth" />
        </button>
        <button
          :if={@is_ref? == false}
          type="button"
          class="block-action toggler"
          phx-click="delete_block"
          phx-target={@target}
          data-popover={gettext("Delete block")}
        >
          <.icon name="hero-trash" />
        </button>
        <Form.label
          field={@block[:collapsed]}
          class="block-action toggler"
          popover={gettext("Collapse (hide) block in block editor")}
        >
          <.icon :if={@collapsed} name="hero-eye-slash" />
          <.icon :if={!@collapsed} name="hero-eye" />
          <Input.input type={:checkbox} field={@block[:collapsed]} />
        </Form.label>

        <div
          :if={!@is_ref?}
          class="dirty block-action toggler"
          data-popover={gettext("Block has changes")}
          phx-click={JS.push("show_dirty", target: @target)}
        >
          ●
        </div>
      </div>
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :table_template_name, :string

  def table(assigns) do
    table_rows_value = assigns.block_data[:table_rows].value

    valid? =
      table_rows_value not in [[], "", nil] &&
        !is_struct(table_rows_value, Ecto.Association.NotLoaded)

    assigns = assign(assigns, :valid?, valid?)

    ~H"""
    <div class="table-block-wrapper">
      <div class="table-info" phx-click="show_table_instructions" phx-target={@target}>
        <div class="icon">
          <span class="hero-table-cells"></span>
        </div>
        <div class="info">
          <span class="table-label">
            <%= gettext("Tabular data") %><br /> [<%= @table_template_name %>]
          </span>
        </div>
      </div>
      <div class="table-block">
        <%= if !@valid? do %>
          <div class="block-instructions">
            <p>
              <%= gettext("This block implements tabular data, but the table is empty.") %><br />
              <%= gettext("Click the 'add row' button below to get started.") %>
            </p>
            <button type="button" class="tiny" phx-click="add_table_row" phx-target={@target}>
              <%= gettext("Add row") %>
            </button>
            <input type="hidden" name={@block_data[:table_rows].name} value={[]} />
          </div>
        <% else %>
          <div
            id={"sortable-#{@uid}-table-rows"}
            class="table-rows"
            phx-hook="Brando.SortableAssocs"
            data-target={@target}
            data-sortable-id={"sortable-#{@uid}-table-rows"}
            data-sortable-handle=".sort-handle"
            data-sortable-binary-keys="true"
            data-sortable-selector=".table-row"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={table_row} field={@block_data[:table_rows]} skip_hidden>
              <div class="table-row draggable" data-id={table_row.index}>
                <input type="hidden" name={table_row[:id].name} value={table_row[:id].value} />
                <input type="hidden" name={table_row[:_persistent_id].name} value={table_row.index} />
                <input
                  type="hidden"
                  name={"#{@block_data.name}[sort_table_row_ids][]"}
                  value={table_row.index}
                />
                <div class="subform-tools">
                  <button type="button" class="sort-handle">
                    <.icon name="hero-arrows-up-down" />
                  </button>
                  <button
                    type="button"
                    class="delete-image"
                    name={"#{@block_data.name}[drop_table_row_ids][]"}
                    value={table_row.index}
                    phx-click={JS.dispatch("change")}
                  >
                    <.icon name="hero-x-mark" />
                  </button>
                </div>

                <.inputs_for :let={var} field={table_row[:vars]}>
                  <.live_component
                    module={RenderVar}
                    id={"block-#{@uid}-table-row-#{var.id}"}
                    var={var}
                    render={:all}
                    publish
                  />
                </.inputs_for>
              </div>
              <div class="insert-row">
                <button type="button" class="tiny" phx-click="add_table_row" phx-target={@target}>
                  <%= gettext("Add row") %>
                </button>
              </div>
            </.inputs_for>
            <input type="hidden" name={"#{@block_data.name}[drop_table_row_ids][]"} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :module_datasource_module_label, :string, required: true
  attr :module_datasource_type, :string, required: true
  attr :module_datasource_query, :string, required: true
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :available_identifiers, :any, default: []
  attr :block_identifiers, :any, default: []

  def datasource(assigns) do
    ~H"""
    <div class="block-datasource">
      <div class="datasource-info" phx-click="show_datasource_instructions" phx-target={@target}>
        <div class="icon">
          <.icon name="hero-circle-stack" />
        </div>
        <div class="info">
          <span class="datasource-label">
            <%= gettext("Datasource") %> [<%= @module_datasource_type %>]<br />
            <%= @module_datasource_module_label %> &rarr; <%= @module_datasource_query %>
          </span>
        </div>
      </div>

      <%= if @module_datasource_type == :selection do %>
        <Content.modal
          title={gettext("Select entries")}
          id={"select-entries-#{@uid}"}
          remember_scroll_position
          narrow
        >
          <h2 class="titlecase"><%= gettext("Available entries") %></h2>
          <Entries.block_identifier
            :for={identifier <- @available_identifiers}
            identifier={identifier}
            select={JS.push("select_identifier", value: %{id: identifier.id}, target: @target)}
            available_identifiers={@available_identifiers}
            block_identifiers={@block_identifiers}
          />
        </Content.modal>

        <div class="module-datasource-selected">
          <div
            id={"sortable-#{@uid}-identifiers"}
            class="selected-entries"
            phx-hook="Brando.SortableAssocs"
            data-target={@target}
            data-sortable-id={"sortable-#{@uid}-identifiers"}
            data-sortable-handle=".identifier"
            data-sortable-selector=".identifier"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={block_identifier} field={@block_identifiers}>
              <Entries.block_identifier
                block_identifier={block_identifier}
                available_identifiers={@available_identifiers}
              >
                <input
                  type="hidden"
                  name={"#{@block_identifiers.form.name}[sort_block_identifier_ids][]"}
                  value={block_identifier.index}
                />
                <:delete>
                  <button
                    type="button"
                    name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"}
                    value={block_identifier.index}
                    phx-click={JS.dispatch("change")}
                  >
                    <.icon name="hero-x-circle" />
                  </button>
                </:delete>
              </Entries.block_identifier>
            </.inputs_for>
            <input
              type="hidden"
              name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"}
            />
          </div>

          <button
            class="tiny select-button"
            type="button"
            phx-click={
              "assign_available_identifiers"
              |> JS.push(target: @target)
              |> show_modal("#select-entries-#{@uid}")
            }
          >
            <%= gettext("Select entries") %>
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  ##
  ## Block events
  def handle_event("duplicate_block", _, socket) do
    changeset = socket.assigns.form.source
    has_children? = socket.assigns.has_children?
    uid = socket.assigns.uid

    if has_children? do
      # if the block has children we need to fetch their changesets
      # todo
    else
      # if not, we can just duplicate the block
      parent_cid = socket.assigns.parent_cid
      send_update(parent_cid, %{event: "duplicate_block", changeset: changeset, uid: uid})
    end

    {:noreply, socket}
  end

  def handle_event("show_datasource_instructions", _, socket) do
    message =
      gettext("""
      <p>
        This block has a datasource, meaning it can load and display data from the database. There are two types:
      </p>

      <ul>
        <li><strong>List Type</strong>: Automatically lists entries based on a preset filter.</li>
        <li><strong>Selection Type</strong>: Allows you to manually select specific entries to display.</li>
      </ul>

      <p>
        Use these options to dynamically show content or highlight particular items.
      </p>
      """)

    alert_params = %{
      title: gettext("Block datasource"),
      message: message,
      type: "info"
    }

    socket
    |> push_event("b:alert", alert_params)
    |> then(&{:noreply, &1})
  end

  def handle_event("show_vars_instructions", _, socket) do
    message =
      gettext("""
      <p>
        This block has variables, which can influence settings like size and colors,
        and allow you to add images, files, and text. Adjusting these variables
        lets you customize and manipulate the block's rendering.
      </p>
      """)

    alert_params = %{
      title: gettext("Block variables"),
      message: message,
      type: "info"
    }

    socket
    |> push_event("b:alert", alert_params)
    |> then(&{:noreply, &1})
  end

  def handle_event("show_table_instructions", _, socket) do
    message =
      gettext("""
      <p>
        This block allows you to input tabular data following a table row template.
        The data entered here will be uniformly structured and used by the block's
        template when rendering content.
      </p>
      """)

    alert_params = %{
      title: gettext("Tabular data"),
      message: message,
      type: "info"
    }

    socket
    |> push_event("b:alert", alert_params)
    |> then(&{:noreply, &1})
  end

  def handle_event("add_table_row", _, socket) do
    uid = socket.assigns.uid
    belongs_to = socket.assigns.belongs_to
    table_template = socket.assigns.table_template
    vars_without_pk = Brando.Villain.remove_pk_from_vars(table_template.vars)

    var_changesets =
      Enum.map(
        vars_without_pk,
        &(Changeset.change(&1, %{table_template_id: nil}) |> Map.put(:action, :insert))
      )

    new_row = %Brando.Content.TableRow{vars: var_changesets}
    changeset = socket.assigns.form.source

    block_changeset =
      if belongs_to == :root, do: Changeset.get_assoc(changeset, :block), else: changeset

    current_rows = Changeset.get_assoc(block_changeset, :table_rows) || []
    new_rows = current_rows ++ List.wrap(new_row)
    updated_block_changeset = Changeset.put_assoc(block_changeset, :table_rows, new_rows)

    updated_form =
      if belongs_to == :root do
        updated_changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)

        to_form(
          updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(
          updated_block_changeset,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    socket
    |> assign(:form, updated_form)
    |> assign(:has_table_rows?, true)
    |> then(&{:noreply, &1})
  end

  ## Identifier events
  def handle_event("assign_available_identifiers", _, socket) do
    {:noreply, assign_available_identifiers(socket)}
  end

  def handle_event("select_identifier", %{"id" => identifier_id}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid

    block_changeset = get_block_changeset(changeset, belongs_to)
    block_identifiers = Changeset.get_assoc(block_changeset, :block_identifiers)

    # check if the identifier is already assigned and if it is, remove it
    # also filter out any :replace actions
    # https://elixirforum.com/t/ecto-put-change-not-working-on-nested-changeset-when-updating/32681/2
    updated_block_identifiers =
      block_identifiers
      |> Enum.find(&(Changeset.get_field(&1, :identifier_id) == identifier_id))
      |> case do
        nil ->
          insert_identifier(block_identifiers, identifier_id)

        %{action: :replace} = replaced_changeset ->
          Enum.map(block_identifiers, fn block_identifier ->
            case Changeset.get_field(block_identifier, :identifier_id) == identifier_id do
              true ->
                action = (Changeset.get_field(block_identifier, :id) == nil && :insert) || nil
                Map.put(replaced_changeset, :action, action)

              false ->
                block_identifier
            end
          end)

        _ ->
          remove_identifier(block_identifiers, identifier_id)
      end
      |> Enum.filter(&(&1.action != :replace))

    updated_block_changeset =
      Changeset.put_assoc(
        block_changeset,
        :block_identifiers,
        updated_block_identifiers
      )

    updated_changeset =
      update_block_changeset(
        changeset,
        updated_block_changeset,
        belongs_to
      )

    new_form =
      if belongs_to == :root do
        to_form(updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(updated_changeset,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    socket
    |> assign(:form, new_form)
    |> send_form_to_parent_stream()
    |> render_module()
    |> maybe_update_live_preview_block()
    |> then(&{:noreply, &1})
  end

  ## Block events
  def handle_event("collapse_block", _, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  # fetch all module refs and add any that are missing to the block
  def handle_event("fetch_missing_refs", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = get_module(module_id)

    module_refs = module.refs
    module_ref_names = Enum.map(module_refs, & &1.name)

    current_refs =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_embed(:refs)
      else
        Changeset.get_embed(changeset, :refs)
      end

    current_ref_names = Enum.map(current_refs, &Changeset.get_field(&1, :name))
    missing_ref_names = module_ref_names -- current_ref_names

    missing_refs =
      module_refs
      |> Enum.filter(&(&1.name in missing_ref_names))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.add_uid_to_ref_changesets()

    new_refs = current_refs ++ missing_refs

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, new_refs)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  # reset a single ref
  def handle_event("reset_ref", %{"id" => ref_name}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = get_module(module_id)

    module_refs = module.refs

    prepared_ref =
      module_refs
      |> Enum.filter(&(&1.name == ref_name))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.add_uid_to_ref_changesets()
      |> List.first()

    current_refs =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_embed(:refs)
      else
        Changeset.get_embed(changeset, :refs)
      end

    prepared_refs =
      current_refs
      |> Enum.reject(&(&1.action == :replace))
      |> Enum.map(fn ref ->
        if Changeset.get_field(ref, :name) == ref_name do
          prepared_ref
        else
          ref
        end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, prepared_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, prepared_refs)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  def handle_event("reset_refs", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = get_module(module_id)

    module_refs = module.refs

    prepared_refs =
      module_refs
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.add_uid_to_ref_changesets()

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, prepared_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, prepared_refs)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  # fetch all module vars and add any that are missing to the block
  def handle_event("fetch_missing_vars", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = get_module(module_id)

    module_vars = module.vars
    module_var_names = Enum.map(module_vars, & &1.key)

    current_vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_assoc(:vars)
      else
        Changeset.get_assoc(changeset, :vars)
      end

    current_var_names = Enum.map(current_vars, &Changeset.get_field(&1, :key))
    missing_var_names = module_var_names -- current_var_names

    missing_vars =
      module_vars
      |> Enum.filter(&(&1.key in missing_var_names))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.remove_pk_from_vars()

    new_vars = current_vars ++ missing_vars

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, new_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, new_vars)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  # reset all vars to module defaults
  def handle_event("reset_vars", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = get_module(module_id)

    module_vars = module.vars

    original_vars =
      module_vars
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.remove_pk_from_vars()

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, original_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, original_vars)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  # reset single var to module defaults
  def handle_event("reset_var", %{"id" => var_key}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = get_module(module_id)

    module_vars = module.vars

    var_to_replace =
      module_vars
      |> Enum.filter(&(&1.key == var_key))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.remove_pk_from_vars()
      |> List.first()

    current_vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_assoc(:vars)
      else
        Changeset.get_assoc(changeset, :vars)
      end

    updated_vars =
      Enum.map(current_vars, fn var ->
        if Changeset.get_field(var, :key) == var_key do
          var_to_replace
        else
          var
        end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, updated_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, updated_vars)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  # delete single var from module
  def handle_event("delete_var", %{"id" => var_key}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = Changeset.get_field(changeset, :uid)

    current_vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_assoc(:vars)
      else
        Changeset.get_assoc(changeset, :vars)
      end

    updated_vars =
      current_vars
      |> Enum.reduce([], fn var, acc ->
        if Changeset.get_field(var, :key) == var_key do
          acc
        else
          [var | acc]
        end
      end)
      |> Enum.reverse()

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, updated_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, updated_vars)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  def handle_event("insert_block", value, socket) do
    # message block picker —— special case for empty container.
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    block_count = socket.assigns.block_count

    {parent_cid, sequence} =
      (Map.get(value, "container") && {socket.assigns.myself, block_count}) ||
        {socket.assigns.parent_cid, socket.assigns.form[:sequence].value}

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: nil},
      type: :module,
      sequence: sequence,
      parent_cid: parent_cid
    )

    {:noreply, socket}
  end

  def handle_event("insert_block_entry", value, socket) do
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    parent_cid = (Map.get(value, "multi") && socket.assigns.myself) || socket.assigns.parent_cid
    block_count = socket.assigns.block_count
    sequence = (Map.get(value, "multi") && block_count) || socket.assigns.form[:sequence].value

    module_id =
      if socket.assigns.parent_module_id do
        socket.assigns.parent_module_id
      else
        socket.assigns.module_id
      end

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: module_id},
      type: :module_entry,
      sequence: sequence,
      parent_cid: parent_cid
    )

    {:noreply, socket}
  end

  # reposition a main block
  def handle_event(
        "reposition",
        %{"id" => _id, "new" => new_idx, "old" => old_idx, "parent_uid" => _parent_uid},
        socket
      )
      when new_idx == old_idx do
    {:noreply, socket}
  end

  def handle_event(
        "reposition",
        %{"uid" => uid, "new" => new_idx, "old" => old_idx, "parent_uid" => _parent_uid},
        socket
      ) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, uid)

    # we must reposition the children changesets list according to the new block_list
    new_changesets =
      Enum.map(new_block_list, fn block_uid ->
        Enum.find(changesets, fn
          {^block_uid, _} -> true
          _ -> false
        end)
      end)

    socket
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, new_changesets)
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> then(&{:noreply, &1})
  end

  def handle_event("show_dirty", _params, socket) do
    require Logger

    Logger.error("""

    changeset.changes
    #{inspect(socket.assigns.form.source.changes)}

    """)

    {:noreply, socket}
  end

  def handle_event("delete_block", _params, socket) do
    uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    dom_id = socket.assigns.dom_id

    send_update(parent_cid, %{
      event: "delete_block",
      uid: uid,
      dom_id: dom_id
    })

    {:noreply, socket |> assign(:deleted, true)}
  end

  def handle_event(
        "validate_block",
        %{"_target" => params_target, "child_block" => params},
        socket
      ) do
    form = socket.assigns.form
    changeset = form.source
    uid = socket.assigns.uid
    current_user_id = socket.assigns.current_user_id
    entry = socket.assigns.entry
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    updated_changeset =
      changeset.data
      |> Brando.Content.Block.block_changeset(params, current_user_id)
      |> Map.put(:action, :validate)
      |> render_and_update_block_changeset(entry, has_vars?, has_table_rows?)

    updated_form =
      to_form(updated_changeset,
        as: "child_block",
        id: "child_block_form-#{uid}"
      )

    socket
    |> assign(:form, updated_form)
    |> assign(:form_has_changes, updated_form.source.changes !== %{})
    |> send_form_to_parent_stream()
    |> maybe_update_liquex_block_var(params_target, params)
    |> maybe_update_live_preview_block()
    |> then(&{:noreply, &1})
  end

  def handle_event(
        "validate_block",
        %{"_target" => params_target, "entry_block" => params},
        socket
      ) do
    form = socket.assigns.form
    changeset = form.source
    uid = socket.assigns.uid
    block_module = socket.assigns.block_module
    current_user_id = socket.assigns.current_user_id
    entry = socket.assigns.entry
    has_vars? = socket.assigns.has_vars?
    has_children? = socket.assigns.has_children?
    has_table_rows? = socket.assigns.has_table_rows?

    updated_changeset =
      changeset.data
      |> block_module.changeset(params, current_user_id)
      |> Map.put(:action, :validate)

    # if this is a container and it's flipped from active = false to true,
    # then we must force an update to the live preview to get the rendered children.
    force_render? = should_force_live_preview_update?(changeset, updated_changeset, :root)

    updated_changeset =
      updated_changeset
      |> render_and_update_entry_block_changeset(entry, has_vars?, has_table_rows?, force_render?)
      |> maybe_put_empty_children(has_children?)

    updated_form =
      to_form(updated_changeset,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    socket
    |> assign(:form, updated_form)
    |> assign(:form_has_changes, updated_form.source.changes !== %{})
    |> maybe_update_liquex_block_var(params_target, params)
    |> maybe_update_container(params_target)
    |> maybe_update_fragment(params_target)
    |> maybe_update_live_preview_block()
    |> send_form_to_parent_stream()
    |> then(&{:noreply, &1})
  end

  defp should_force_live_preview_update?(changeset, updated_changeset, :root) do
    block_changeset = Changeset.get_assoc(changeset, :block)
    updated_block_changeset = Changeset.get_assoc(updated_changeset, :block)

    Changeset.get_field(block_changeset, :type) == :container &&
      Changeset.get_field(block_changeset, :active) == false &&
      Changeset.get_field(updated_block_changeset, :active) == true
  end

  defp build_form_from_changeset(changeset, uid, belongs_to) do
    if belongs_to == :root do
      to_form(changeset,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )
    else
      to_form(changeset,
        as: "child_block",
        id: "child_block_form-#{uid}"
      )
    end
  end

  defp maybe_put_empty_children(changeset, false) do
    updated_block_cs =
      changeset
      |> Changeset.get_assoc(:block)
      |> Changeset.put_assoc(:children, [])

    Changeset.put_assoc(changeset, :block, updated_block_cs)
  end

  defp maybe_put_empty_children(changeset, true) do
    changeset
  end

  defp send_form_to_parent_stream(socket) do
    parent_cid = socket.assigns.parent_cid
    level = socket.assigns.level
    form = socket.assigns.form

    send_update(parent_cid, %{event: "update_block", level: level, form: form})
    socket
  end

  defp maybe_update_live_preview_block(%{assigns: %{live_preview_active?: true}} = socket) do
    %{
      form: %{source: changeset},
      belongs_to: belongs_to,
      has_children?: has_children?,
      form_cid: form_cid
    } = socket.assigns

    block_cs = get_block_changeset(changeset, belongs_to)
    rendered_html = Changeset.get_field(block_cs, :rendered_html)
    uid = Changeset.get_field(block_cs, :uid)

    send_update(form_cid, %{
      event: "update_live_preview_block",
      rendered_html: rendered_html,
      uid: uid,
      has_children?: has_children?
    })

    socket
  end

  defp maybe_update_live_preview_block(socket), do: socket

  defp get_fragment(nil), do: nil

  defp get_fragment(id) do
    Brando.Pages.get_fragment!(%{
      matches: %{id: id}
    })
  end

  defp get_container(id) do
    {:ok, containers} =
      Brando.Content.list_containers(%{
        preload: [:palette],
        cache: {:ttl, :infinite}
      })

    case Enum.find(containers, &(&1.id == id)) do
      nil -> nil
      container -> container
    end
  end

  defp get_module(id) do
    {:ok, modules} =
      Brando.Content.list_modules(%{
        preload: [{:vars, {Var, [asc: :sequence]}}],
        cache: {:ttl, :infinite}
      })

    case Enum.find(modules, &(&1.id == id)) do
      nil -> nil
      module -> module
    end
  end

  def render_and_update_entry_block_changeset(
        changeset,
        entry,
        has_vars?,
        has_table_rows?,
        force_render? \\ false
      ) do
    skip_children =
      case force_render? do
        true -> :force_render
        false -> true
      end

    rendered_html =
      changeset
      |> Brando.Utils.apply_changes_recursively()
      |> reset_empty_vars(has_vars?, true)
      |> reset_table_rows(has_table_rows?, true)
      |> Brando.Villain.render_block(entry,
        skip_children: skip_children,
        format_html: true,
        annotate_blocks: true
      )

    updated_block_changeset =
      changeset
      |> Changeset.get_assoc(:block)
      |> Changeset.put_change(:rendered_html, rendered_html)
      |> maybe_update_rendered_at()

    Changeset.put_assoc(changeset, :block, updated_block_changeset)
  end

  def render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?) do
    rendered_html =
      changeset
      |> Brando.Utils.apply_changes_recursively()
      |> reset_empty_vars(has_vars?, false)
      |> reset_table_rows(has_table_rows?, false)
      |> Brando.Villain.render_block(entry,
        skip_children: true,
        format_html: true,
        annotate_blocks: true
      )

    changeset
    |> Changeset.put_change(:rendered_html, rendered_html)
    |> maybe_update_rendered_at()
  end

  defp maybe_update_rendered_at(%Changeset{changes: %{rendered_html: _}} = changeset) do
    Changeset.put_change(changeset, :rendered_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp maybe_update_rendered_at(changeset) do
    changeset
  end

  defp reset_empty_vars(block, true, _), do: block

  # if we don't have vars, force them to an empty list, since they get set to NotLoaded.
  defp reset_empty_vars(block, false, true) do
    put_in(block, [Access.key(:block), Access.key(:vars)], [])
  end

  defp reset_empty_vars(block, false, false) do
    put_in(block, [Access.key(:vars)], [])
  end

  defp reset_table_rows(block, true, _), do: block

  # if we don't have vars, force them to an empty list, since they get set to NotLoaded.
  defp reset_table_rows(block, false, true) do
    put_in(block, [Access.key(:block), Access.key(:table_rows)], [])
  end

  defp reset_table_rows(block, false, false) do
    put_in(block, [Access.key(:table_rows)], [])
  end

  def update_liquid_splits_entry_variables(liquid_splits, entry) do
    liquid_splits
    |> Enum.reduce([], fn
      {:entry_variable, variable, _}, acc ->
        [{:entry_variable, variable, liquid_render_entry_variable(variable, entry)} | acc]

      item, acc ->
        [item | acc]
    end)
    |> Enum.reverse()
  end

  def maybe_update_container(socket, [_block_type, "block", "container_id"]) do
    changeset = socket.assigns.form.source
    block_cs = Changeset.get_assoc(changeset, :block)
    container_id = Changeset.get_field(block_cs, :container_id)
    assign(socket, :container, get_container(container_id))
  end

  def maybe_update_container(socket, _), do: socket

  def maybe_update_fragment(socket, [_block_type, "block", "fragment_id"]) do
    changeset = socket.assigns.form.source
    block_cs = Changeset.get_assoc(changeset, :block)
    fragment_id = Changeset.get_field(block_cs, :fragment_id)
    assign(socket, :fragment, get_fragment(fragment_id))
  end

  def maybe_update_fragment(socket, _), do: socket

  # if the target param updated is a var and it's not an image or file, we extract the value
  # and update the liquex block var
  def maybe_update_liquex_block_var(
        socket,
        [_block_type, "vars", _idx, "value"] = params_target,
        params
      ) do
    var_target =
      params_target
      |> List.delete_at(0)
      |> List.delete_at(-1)

    var_params = get_in(params, var_target)
    value = Map.get(var_params, "value")
    var_key = Map.get(var_params, "key")

    var_type =
      var_params
      |> Map.get("type")
      |> String.to_existing_atom()

    update_liquex_block_var(socket, var_key, var_type, %{value: value})
  end

  def maybe_update_liquex_block_var(socket, _, _), do: socket

  def update_liquex_block_var(socket, var_key, :image, data) do
    liquid_splits = socket.assigns.liquid_splits

    updated_liquid_splits =
      liquid_splits
      |> Enum.reduce([], fn
        {type, ^var_key, _prev_var_value}, acc ->
          path = get_in(data, [:image, Access.key(:path)])
          media_path = Brando.Utils.media_url(path)

          require Logger

          Logger.error("""
          => update_liquex_block_var #{var_key} => #{media_path}
          """)

          [{type, var_key, media_path} | acc]

        item, acc ->
          [item | acc]
      end)
      |> Enum.reverse()

    assign(socket, :liquid_splits, updated_liquid_splits)
  end

  def update_liquex_block_var(socket, var_key, _var_type, data) do
    liquid_splits = socket.assigns.liquid_splits

    updated_liquid_splits =
      liquid_splits
      |> Enum.reduce([], fn
        {type, ^var_key, _prev_var_value}, acc ->
          [{type, var_key, Map.get(data, :value)} | acc]

        item, acc ->
          [item | acc]
      end)
      |> Enum.reverse()

    assign(socket, :liquid_splits, updated_liquid_splits)
  end

  defp to_change_form(child_block_or_cs, params, user, action \\ nil) do
    changeset =
      child_block_or_cs
      |> Brando.Content.Block.block_changeset(params, user)
      |> Map.put(:action, action)

    uid = Changeset.get_field(changeset, :uid)

    to_form(changeset,
      as: "child_block",
      id: "child_block_form-#{uid}"
    )
  end

  defp emphasize_datasources(code, assigns) do
    Regex.replace(
      ~r/(({% datasource %}(?:.*?){% enddatasource %}))/s,
      code,
      """
      <div class="brando-datasource-placeholder">
         <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg>
         <div class="text-mono">#{assigns.module_datasource_module_label} | #{assigns.module_datasource_type} | #{assigns.module_datasource_query}</div>
         #{gettext("Content from datasource will be inserted here")}
      </div>
      """
    )
  end

  defp liquid_strip_logic(module_code),
    do: Regex.replace(@liquid_regex_strips, module_code, "")

  defp liquid_render_entry_picture_src("entry." <> var_path_string, assigns) do
    entry = assigns.entry

    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    if path = Brando.Utils.try_path(entry, var_path ++ [:path]) do
      Brando.Utils.media_url(path)
    else
      ""
    end
  end

  defp liquid_render_module_picture_src(var_name, vars) do
    # TODO: Give this another shake now that we have assocs
    # FIXME
    #
    # This is suboptimal at best. We preload all our image vars in the form, but when running
    # the polymorphic changesets, it clobbers the image's `value` - resetting it.
    #
    # Everything here will hopefully improve when we can update poly changesets instead
    # of replacing/inserting new every time.

    require Logger

    Logger.error("""
    => liquid_render_module_picture_src #{inspect(var_name, pretty: true)}

    #{inspect(vars, pretty: true)}
    """)

    if var_cs = Enum.find(vars, &(Changeset.get_field(&1, :key) == var_name)) do
      image_id = Changeset.get_field(var_cs, :image_id)
      image = Changeset.get_field(var_cs, :image)

      cond do
        image_id == nil ->
          ""

        image == %Ecto.Association.NotLoaded{} ->
          image_id = Changeset.get_field(var_cs, :image_id)

          case Brando.Cache.get("var_image_#{image_id}") do
            nil ->
              image = Brando.Images.get_image!(image_id)
              media_path = Brando.Utils.media_url(image.path)
              Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
              media_path

            media_path ->
              media_path
          end

        %Brando.Images.Image{path: path} = image ->
          media_path = Brando.Utils.media_url(path)
          Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
          media_path

        true ->
          require Logger

          Logger.error("""

          other:
          #{inspect(image_id, pretty: true)}
          #{inspect(image, pretty: true)}

          """)

          ""
      end
    else
      ""
    end
  end

  defp liquid_render_entry_variable(var_path_string, entry) do
    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    Brando.Utils.try_path(entry, var_path) |> raw()
  rescue
    ArgumentError ->
      "{{ entry.#{var_path_string} }}"
  end

  defp liquid_render_module_variable(var, vars) do
    case Enum.find(vars, &(Changeset.get_field(&1, :key) == var)) do
      nil -> var
      var_cs -> Changeset.get_field(var_cs, :value)
    end
  end

  defp add_uid_to_refs(changeset) do
    refs = Changeset.get_embed(changeset, :refs)

    updated_refs = Brando.Villain.add_uid_to_ref_changesets(refs)
    Changeset.put_embed(changeset, :refs, updated_refs)
  end

  defp filter_replace_refs(changeset) do
    refs = Changeset.get_embed(changeset, :refs)
    updated_refs = Enum.reject(refs, &(&1.action == :replace))
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

  defp insert_identifier(block_identifiers, identifier_id) do
    new_block_identifier =
      %BlockIdentifier{}
      |> Changeset.change()
      |> Changeset.put_change(:identifier_id, identifier_id)
      |> Map.put(:action, :insert)

    block_identifiers ++ [new_block_identifier]
  end

  defp remove_identifier(block_identifiers, identifier_id) do
    Enum.reject(
      block_identifiers,
      &(Changeset.get_field(&1, :identifier_id) == identifier_id)
    )
  end

  def update_block_changeset(changeset, block_changeset, :root) do
    Changeset.put_assoc(changeset, :block, block_changeset)
  end

  def update_block_changeset(_changeset, block_changeset, _) do
    block_changeset
  end

  def get_block_data_changeset(block) do
    Changeset.get_embed(block[:data].form.source, :data)
  end

  def get_block_changeset(changeset, :root), do: Changeset.get_assoc(changeset, :block)
  def get_block_changeset(changeset, _), do: changeset

  defp extract_block_bg_color(%{colors: []}) do
    "transparent"
  end

  defp extract_block_bg_color(%{colors: colors}) do
    colors
    |> List.first()
    |> Map.get(:hex_value)
    |> Kernel.<>("14")
  end

  defp extract_block_bg_color(_) do
    "transparent"
  end
end
