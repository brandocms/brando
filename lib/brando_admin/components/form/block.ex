defmodule BrandoAdmin.Components.Form.Block do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Input
  import Brando.Gettext

  #
  # When saving the complete form, we first message all blocks who BELONGS_TO something besides root.
  # Worst case this is `CONTAINER -> MULTI -> ENTRY` which is 3 levels deep.
  # Can we include a LEVEL property in each block to know how deep we are? Then begin messaging from the deepest level?
  # The message contains the new changeset for the block which will get replaced in the parent stream.
  # Then we message root blocks to update themselves in the main block stream?
  # We only need to message blocks who are DIRTY or NEW.
  # Mark updated containers and updated MULTI blocks as DIRTY! If they're not DIRTY or NEW, they don't need to be saved!
  # ^- should we still update them in the stream?
  #
  # - We must somehow hold a state of when all child blocks have been updated before we can update the root blocks?

  def update(%{event: "update_sequence", sequence: idx}, socket) do
    require Logger

    Logger.error("""

    UPDATE_SEQUENCE: #{socket.assigns.id} -- #{inspect(idx)}
    LEVEL: #{inspect(socket.assigns.level)}

    """)

    form = socket.assigns.form
    level = socket.assigns.level

    if level == 0 do
      send_update(socket.assigns.parent_cid, %{
        event: "update_root_sequence",
        level: 0,
        form: form,
        sequence: idx
      })
    end

    {:ok, socket}

    # cs = socket.assigns.form.source

    # new_form =
    #   to_change_form(cs, %{sequence: idx}, socket.assigns.current_user_id)

    # {:ok,
    #  socket
    #  |> assign(:form_has_changes, new_form.source.changes !== %{})
    #  |> assign(:form, new_form)}
  end

  def update(%{event: "insert_block"} = assigns, socket) do
    level = assigns.level
    before_id = assigns.before_id
    parent_id = assigns.parent_id
    user_id = socket.assigns.current_user_id
    require Logger

    Logger.error("""

    == insert block to parent_cid: #{inspect(socket.assigns.myself)} -- before id: #{inspect(before_id)} -- parent_id: #{inspect(parent_id)}

    """)

    empty_block = BrandoAdmin.Components.Form.BlockField.build_block(2, user_id, parent_id)

    # empty_block_cs = Brando.Content.Block.changeset(empty_block, %{}, socket.assigns.current_user)

    block_form =
      to_change_form(
        empty_block,
        %{sequence: 0, description: "Wow!"},
        user_id
      )

    socket
    |> stream_insert(:children_forms, block_form, at: 0)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    changeset = assigns.form.source

    socket
    |> assign(assigns)
    |> assign(:form_has_changes, changeset.changes !== %{})
    |> assign(:form_is_new, !changeset.data.id)
    |> assign_new(:deleted, fn -> false end)
    |> maybe_assign_children()
    |> then(&{:ok, &1})
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    stream(socket, :children_forms, children_forms)
  end

  def maybe_assign_children(
        %{assigns: %{type: :module, multi: true, children: children}} = socket
      ) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    stream(socket, :children_forms, children_forms)
  end

  def maybe_assign_children(socket) do
    socket
  end

  # <input type="hidden" name="list[notifications_order][]" value={f_nested.index} />
  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div>
      <h2>MODULE MULTI — Level <%= @level %></h2>
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
              <button>Save</button>
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
            parent_cid={@myself}
            form={child_block_form}
            current_user_id={@current_user_id}
            belongs_to={:multi}
            level={@level + 1}
          />
        </div>
      </div>
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
        target={@myself}
        insert_block={
          JS.push("insert_block",
            value: %{level: @level, belongs_to: @belongs_to, position: @form[:sequence].value},
            target: @myself
          )
        }
      >
        <%= render_slot(@inner_block) %>
      </.module>
    </div>
    """
  end

  def render(%{type: :container} = assigns) do
    ~H"""
    <div>
      <h2>CONTAINER - <%= @level %></h2>
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
          <button>Save</button>
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
            parent_cid={@myself}
            form={child_block_form}
            current_user_id={@current_user_id}
            belongs_to={:container}
            level={@level + 1}
          >
          </.live_component>
        </div>
      </div>
    </div>
    """
  end

  def module(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block = (belongs_to == :root && changeset.data.block) || changeset.data
    assigns = assign(assigns, :uid, block.uid)

    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="module-block"
      style={"background-color: #{if @dirty or @new, do: "pink", else: "ghostwhite"}; padding: 1rem; margin: 1rem 0; border: 1px solid #ccc; border-radius: 4px;"}
      data-block-uid={@uid}
    >
      <button type="button" phx-click={@insert_block}>
        Insert block -- level <%= @level %>
      </button>
      <.form
        for={@form}
        class="mt-1"
        phx-value-id={@form.data.id}
        phx-change="validate_block"
        phx-submit="save_block"
        phx-target={@target}
      >
        <.toolbar myself={@target} />
        <%= if @belongs_to == :root do %>
          <%!-- <Input.text field={@form[:entry_id]} label="ENTRY ID" /> --%>
          <Input.hidden field={@form[:sequence]} />
          <.inputs_for :let={block_form} field={@form[:block]}>
            <.inputs_for :let={var} field={block_form[:vars]}>
              <.var var={var} />
            </.inputs_for>
            <button>Save</button>
            —— sequence: <%= @form[:sequence].value %><br />
            <div class="brando-input">
              <Input.text field={block_form[:uid]} label="UID" />
              <Input.text field={block_form[:description]} label="Description" />
            </div>
          </.inputs_for>
        <% else %>
          <Input.hidden field={@form[:sequence]} />
          <.inputs_for :let={var} field={@form[:vars]}>
            <.var var={var} />
          </.inputs_for>
          <div class="brando-input">
            <Input.text field={@form[:uid]} label="UID" />
            <Input.text field={@form[:description]} label="Description" />
          </div>
        <% end %>
      </.form>
    </div>
    """
  end

  # <Blocks.block
  #     id={"block-#{@uid}-base"}
  #     index={@index}
  #     block_count={@block_count}
  #     base_form={@base_form}
  #     block={@block}
  #     belongs_to={@belongs_to}
  #     insert_module={@insert_module}
  #     duplicate_block={@duplicate_block}
  #     is_datasource?={@module_datasource}
  #   >
  #     <:type>
  #       <%= if @module_datasource do %>
  #         <%= gettext("DATAMODULE") %>
  #       <% else %>
  #         <%= gettext("MODULE") %>
  #       <% end %>
  #     </:type>
  #     <:datasource>
  #       <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  #         <path fill="none" d="M0 0h24v24H0z" /><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z" />
  #       </svg>
  #       <%= @module_datasource_module_label %> | <%= @module_datasource_type %> | <%= @module_datasource_query %>
  #       <%= if @module_datasource_type == :selection do %>
  #         <Content.modal
  #           title={gettext("Select entries")}
  #           id={"select-entries-#{@uid}"}
  #           remember_scroll_position
  #         >
  #           <h2 class="titlecase"><%= gettext("Available entries") %></h2>
  #           <Entries.identifier
  #             :for={identifier <- @available_identifiers}
  #             identifier_id={identifier.id}
  #             select={JS.push("select_identifier", value: %{id: identifier.id}, target: @myself)}
  #             available_identifiers={@available_identifiers}
  #             selected_identifiers={@selected_identifiers}
  #           />
  #         </Content.modal>

  #         <div class="module-datasource-selected">
  #           <Form.array_inputs
  #             :let={%{value: array_value, name: array_name}}
  #             field={@block_data[:datasource_selected_ids]}
  #           >
  #             <input type="hidden" name={array_name} value={array_value} />
  #           </Form.array_inputs>

  #           <div
  #             id={"sortable-#{@uid}-identifiers"}
  #             class="selected-entries"
  #             phx-hook="Brando.Sortable"
  #             data-target={@myself}
  #             data-sortable-id={"sortable-#{@uid}-identifiers"}
  #             data-sortable-handle=".sort-handle"
  #             data-sortable-selector=".identifier"
  #           >
  #             <Entries.identifier
  #               :for={identifier <- @selected_identifiers}
  #               identifier_id={identifier.id}
  #               available_identifiers={@selected_identifiers}
  #               sortable
  #             >
  #               <:delete>
  #                 <button
  #                   type="button"
  #                   phx-page-loading
  #                   phx-click={
  #                     JS.push("remove_identifier", value: %{id: identifier.id}, target: @myself)
  #                   }
  #                 >
  #                   <.icon name="hero-x-mark" />
  #                 </button>
  #               </:delete>
  #             </Entries.identifier>
  #           </div>

  #           <button
  #             class="tiny select-button"
  #             type="button"
  #             phx-click={
  #               JS.push("select_entries", target: @myself) |> show_modal("#select-entries-#{@uid}")
  #             }
  #           >
  #             <%= gettext("Select entries") %>
  #           </button>
  #         </div>
  #       <% end %>
  #     </:datasource>
  #     <:description>
  #       <%= if @description do %>
  #         <strong><%= @description %></strong>&nbsp;|
  #       <% end %>
  #       <%= @module_name %>
  #     </:description>
  #     <:config>
  #       <div class="panels">
  #         <div class="panel">
  #           <Input.text
  #             field={@block[:description]}
  #             label={gettext("Block description")}
  #             instructions={gettext("Helpful for collapsed blocks")}
  #           />
  #           <%= for {var, index} <- @indexed_vars do %>
  #             <.live_component
  #               module={RenderVar}
  #               id={"block-#{@uid}-render-var-#{index}"}
  #               var={var}
  #               render={:only_regular}
  #               in_block
  #             />
  #           <% end %>
  #         </div>
  #         <div class="panel">
  #           <h2 class="titlecase">Vars</h2>
  #           <%= for var <- @vars do %>
  #             <div class="var">
  #               <div class="key"><%= var.key %></div>
  #               <div class="buttons">
  #                 <button
  #                   type="button"
  #                   class="tiny"
  #                   phx-click={JS.push("reset_var", target: @myself)}
  #                   phx-value-id={var.key}
  #                 >
  #                   <%= gettext("Reset") %>
  #                 </button>
  #                 <button
  #                   type="button"
  #                   class="tiny"
  #                   phx-click={JS.push("delete_var", target: @myself)}
  #                   phx-value-id={var.key}
  #                 >
  #                   <%= gettext("Delete") %>
  #                 </button>
  #               </div>
  #             </div>
  #           <% end %>

  #           <h2 class="titlecase">Refs</h2>
  #           <%= for ref <- @refs do %>
  #             <div class="ref">
  #               <div class="key"><%= ref.name %></div>
  #               <button
  #                 type="button"
  #                 class="tiny"
  #                 phx-click={JS.push("reset_ref", target: @myself)}
  #                 phx-value-id={ref.name}
  #               >
  #                 <%= gettext("Reset") %>
  #               </button>
  #             </div>
  #           <% end %>
  #           <h2 class="titlecase"><%= gettext("Advanced") %></h2>
  #           <div class="button-group-vertical">
  #             <button
  #               type="button"
  #               class="secondary"
  #               phx-click={JS.push("fetch_missing_refs", target: @myself)}
  #             >
  #               <%= gettext("Fetch missing refs") %>
  #             </button>
  #             <button
  #               type="button"
  #               class="secondary"
  #               phx-click={JS.push("reset_refs", target: @myself)}
  #             >
  #               <%= gettext("Reset all block refs") %>
  #             </button>
  #             <button
  #               type="button"
  #               class="secondary"
  #               phx-click={JS.push("fetch_missing_vars", target: @myself)}
  #             >
  #               <%= gettext("Fetch missing vars") %>
  #             </button>
  #             <button
  #               type="button"
  #               class="secondary"
  #               phx-click={JS.push("reset_vars", target: @myself)}
  #             >
  #               <%= gettext("Reset all variables") %>
  #             </button>
  #           </div>
  #         </div>
  #       </div>
  #     </:config>

  #     <div b-editor-tpl={@module_class}>
  #       <%= unless Enum.empty?(@important_vars) do %>
  #         <div class="important-vars">
  #           <%= for {var, index} <- @indexed_vars do %>
  #             <.live_component
  #               module={RenderVar}
  #               id={"block-#{@uid}-render-var-blk-#{index}"}
  #               var={var}
  #               render={:only_important}
  #               in_block
  #             />
  #           <% end %>
  #         </div>
  #       <% end %>
  #       <%= for split <- @splits do %>
  #         <%= case split do %>
  #           <% {:ref, ref} -> %>
  #             <Blocks.Module.Ref.render
  #               data_field={@data_field}
  #               parent_uploads={@parent_uploads}
  #               module_refs={@refs_forms}
  #               module_ref_name={ref}
  #               base_form={@base_form}
  #             />
  #           <% {:content, _} -> %>
  #             <%= if @module_multi do %>
  #               <.live_component
  #                 module={Blocks.Module.Entries}
  #                 id={"block-#{@uid}-entries"}
  #                 uid={@uid}
  #                 entry_template={@entry_template}
  #                 block_data={@block_data}
  #                 data_field={@data_field}
  #                 base_form={@base_form}
  #                 module_id={@module_id}
  #               />
  #             <% else %>
  #               <%= "{{ content }}" %>
  #             <% end %>
  #           <% {:variable, var_name, variable_value} -> %>
  #             <div
  #               class="rendered-variable"
  #               data-popover={
  #                 gettext("Edit the entry directly to affect this variable [%{var_name}]",
  #                   var_name: var_name
  #                 )
  #               }
  #             >
  #               <%= variable_value %>
  #             </div>
  #           <% {:picture, _, img_src} -> %>
  #             <figure>
  #               <img src={img_src} />
  #             </figure>
  #           <% _ -> %>
  #             <%= raw(split) %>
  #         <% end %>
  #       <% end %>
  #       <Input.input
  #         type={:hidden}
  #         field={@block_data[:module_id]}
  #         uid={@uid}
  #         id_prefix="module_data"
  #       />
  #       <Input.input
  #         type={:hidden}
  #         field={@block_data[:sequence]}
  #         uid={@uid}
  #         id_prefix="module_data"
  #       />
  #       <Input.input type={:hidden} field={@block_data[:multi]} uid={@uid} id_prefix="module_data" />
  #     </div>
  #   </Blocks.block>

  def var(assigns) do
    ~H"""
    <div class="block-var">
      <div style="font-family: monospace; font-size: 9px;">
        <%= @var[:key].value %> - <%= @var[:type].value %>
      </div>
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

  def handle_event("insert_block", %{"level" => level}, socket) do
    parent_cid = socket.assigns.parent_cid
    require Logger

    Logger.error("""

    == insert block to parent_cid: #{inspect(parent_cid)} -- before id: #{inspect(socket.assigns.uid)}

    """)

    send_update(parent_cid, %{
      event: "insert_block",
      level: level,
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
    level = socket.assigns.level
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

    # save changeset
    case Brando.repo().insert_or_update(updated_changeset) do
      {:ok, entry} ->
        preloaded_entry = Brando.repo().preload(entry, Brando.Content.Block.preloads())
        updated_form = to_base_change_form(preloaded_entry, %{}, user_id, :validate)
        send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})

      {:error, changeset} ->
        updated_form = to_base_change_form(changeset, %{}, user_id, :validate)
        send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})
    end

    {:noreply, socket}
  end

  def handle_event("validate_block", %{"child_block" => _params}, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_block", %{"entry_block" => params}, socket) do
    parent_cid = socket.assigns.parent_cid
    form = socket.assigns.form
    level = socket.assigns.level

    updated_form =
      to_base_change_form(
        form.source,
        params,
        socket.assigns.current_user_id,
        :validate
      )

    send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})

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
