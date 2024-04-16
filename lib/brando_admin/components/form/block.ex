defmodule BrandoAdmin.Components.Form.Block do
  use BrandoAdmin, :live_component
  alias Ecto.Changeset
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.BlockField
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

  def mount(socket) do
    {:ok, assign(socket, module_not_found: false, entry_template: nil)}
  end

  def update(%{event: "update_sequence", sequence: idx}, socket) do
    block_module = socket.assigns.block_module
    form = socket.assigns.form
    level = socket.assigns.level
    user_id = socket.assigns.current_user_id
    cs = socket.assigns.form.source

    new_form =
      if level == 0 do
        to_base_change_form(block_module, cs, %{"sequence" => idx}, user_id)
      else
        to_change_form(cs, %{"sequence" => idx}, user_id)
      end

    {:ok,
     socket
     |> assign(:form_has_changes, new_form.source.changes !== %{})
     |> assign(:form, new_form)}
  end

  def update(%{event: "fetch_root_block"}, socket) do
    # a message we will receive from the block field
    require Logger
    Logger.error("--> fetch_root_block [block] {uid:#{socket.assigns.uid}}")
    id = socket.assigns.id
    parent_cid = socket.assigns.parent_cid
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets

    # if the block has children we message them to gather their changesets
    if has_children? do
      Logger.error(
        "----> fetch_root_block [block] HAS CHILDREN --> MSG THEM {uid:#{uid}/#{changeset.data.__struct__}}"
      )

      for {block_uid, _} <- changesets do
        Logger.error("------> msg child block {uid:#{block_uid}}")
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "fetch_child_block",
          uid: block_uid
        )
      end
    else
      # if the block has no children we send the current changeset back to the parent
      Logger.error(
        "----> fetch_root_block [block] NO CHILDREN --> PROVIDE ROOT BLOCK {uid:#{uid}/#{changeset.data.__struct__}}"
      )

      send_update(parent_cid, %{
        event: "provide_root_block",
        changeset: changeset,
        uid: uid
      })
    end

    {:ok, socket}
  end

  def update(%{event: "fetch_child_block"}, socket) do
    # a message we will receive from parent block
    require Logger
    id = socket.assigns.id
    parent_cid = socket.assigns.parent_cid
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets
    Logger.error("--> fetch_child_block [block] {uid:#{uid}/#{changeset.data.__struct__}}")

    # if the block has children we message them to gather their changesets
    if has_children? do
      Logger.error(
        "----> fetch_child_block [block] HAS CHILDREN --> MSG THEM {uid:#{uid}/#{changeset.data.__struct__}}"
      )

      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"
        Logger.error("------> msg child block {uid:#{block_uid}}")

        send_update(__MODULE__,
          id: id,
          event: "fetch_child_block",
          uid: block_uid
        )
      end
    else
      # if the block has no children we send the current changeset back to the parent
      Logger.error(
        "----> fetch_child_block [block] NO CHILDREN --> PROVIDE CHILD BLOCK {uid:#{uid}/#{changeset.data.__struct__}}"
      )

      send_update(parent_cid, %{
        event: "provide_child_block",
        changeset: changeset,
        uid: uid
      })
    end

    {:ok, socket}
  end

  def update(
        %{
          event: "provide_child_block",
          changeset: child_changeset,
          uid: uid
        },
        socket
      ) do
    require Logger
    parent_uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    level = socket.assigns.level
    changeset = socket.assigns.form.source

    Logger.error(
      "--> provide_child_block [block:level{#{level}}] {uid:#{uid}} -> {parent_uid:#{parent_uid}} -> {#{child_changeset.data.__struct__}}"
    )

    changesets = socket.assigns.changesets
    updated_changesets = Map.put(changesets, uid, child_changeset)

    unless Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      # all changesets are present, ship 'em down
      require Logger

      updated_changesets_list = Map.values(updated_changesets)

      updated_changeset =
        if Enum.any?(updated_changesets_list, &(&1.changes !== %{})) do
          # if the changeset struct is a block we put it directly,
          # but if it's an entry block we need to put it under the block association
          if changeset.data.__struct__ == Brando.Content.Block do
            Logger.error("==> changing changeset's children association")

            Changeset.put_assoc(
              changeset,
              :children,
              Enum.map(updated_changesets_list, &Map.put(&1, :action, nil))
            )
          else
            # EctoNestedChangeset.update_at(changeset, [:block, :children], fn _ ->
            #   updated_changesets_list
            # end)
            Logger.error("==> changing changeset's block association")

            Logger.error("""

            updated_changesets_list: #{inspect(updated_changesets_list, pretty: true)}

            """)

            updated_block_changeset =
              changeset
              |> Changeset.get_field(:block)
              |> Changeset.change()
              |> Changeset.put_assoc(
                :children,
                Enum.map(updated_changesets_list, &Map.put(&1, :action, nil))
              )

            Changeset.put_assoc(changeset, :block, updated_block_changeset)
          end
        else
          changeset
        end

      if level == 0 do
        send_update(parent_cid, %{
          event: "provide_root_block",
          changeset: updated_changeset,
          uid: parent_uid
        })
      else
        send_update(parent_cid, %{
          event: "provide_child_block",
          changeset: updated_changeset,
          uid: parent_uid
        })
      end
    end

    {:ok, assign(socket, :changesets, updated_changesets)}
  end

  def update(%{event: "update_block", level: level, form: form}, socket) do
    # socket = stream_insert(socket, :children_forms, form)
    require Logger

    Logger.error("""

    update_block in block.ex -- level: #{level} -- uid: #{inspect(socket.assigns.uid)}

    """)

    {:ok, stream_insert(socket, :children_forms, form)}
  end

  def update(%{event: "insert_block", sequence: sequence} = assigns, socket) do
    level = assigns.level
    before_id = assigns.before_id
    parent_id = assigns.parent_id
    user_id = socket.assigns.current_user_id
    require Logger

    Logger.error("""

    == insert block to parent_cid: #{inspect(socket.assigns.myself)} -- before id: #{inspect(before_id)} -- parent_id: #{inspect(parent_id)}

    """)

    empty_block = BrandoAdmin.Components.Form.BlockField.build_block(2, user_id, parent_id)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, empty_block.uid)

    block_form =
      to_change_form(
        empty_block,
        %{sequence: sequence, description: "Wow!"},
        user_id
      )

    socket
    |> stream_insert(:children_forms, block_form, at: sequence)
    |> assign(:block_list, new_block_list)
    |> send_child_sequence_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    changeset = assigns.form.source

    socket
    |> assign(assigns)
    |> assign(:form_has_changes, changeset.changes !== %{})
    |> assign(:form_is_new, !changeset.data.id)
    |> assign_new(:rendered_block, fn -> "" end)
    |> assign_new(:deleted, fn -> false end)
    |> assign_new(:parent_uid, fn -> nil end)
    |> assign_new(:has_children?, fn -> assigns.children !== [] end)
    |> maybe_assign_children()
    |> then(&{:ok, &1})
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    socket
    |> stream(:children_forms, children_forms)
    |> assign_new(:changesets, fn ->
      children
      |> Enum.map(&{&1.uid, nil})
      |> Enum.into(%{})
    end)
    |> assign_new(:block_list, fn ->
      Enum.map(children, & &1.uid)
    end)
  end

  def maybe_assign_children(
        %{assigns: %{type: :module, multi: true, children: children}} = socket
      ) do
    children_forms =
      Enum.map(children, &to_change_form(&1, %{}, socket.assigns.current_user_id))

    socket
    |> stream(:children_forms, children_forms)
    |> assign_new(:changesets, fn ->
      children
      |> Enum.map(&{&1.uid, nil})
      |> Enum.into(%{})
    end)
    |> assign_new(:block_list, fn ->
      Enum.map(children, & &1.uid)
    end)
  end

  def maybe_assign_children(socket) do
    socket
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> %{} end)
  end

  def send_child_sequence_update(socket, block_list) do
    # send_update to all components in block_list
    parent_id = socket.assigns.id

    for {block_uid, idx} <- Enum.with_index(block_list) do
      id = "#{parent_id}-child-#{block_uid}"
      send_update(__MODULE__, id: id, event: "update_sequence", sequence: idx)
    end

    socket
  end

  # <input type="hidden" name="list[notifications_order][]" value={f_nested.index} />
  def render(%{type: :module, multi: true} = assigns) do
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
            value: %{level: @level, belongs_to: @belongs_to, sequence: @form[:sequence].value},
            target: @myself
          )
        }
      >
        <div>MULTI — parent is <%= inspect(@uid) %></div>
        <code><pre><%= inspect(@block_list, pretty: true, width: 0) %></pre></code>

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
              id={"#{@id}-child-#{child_block_form.data.uid}"}
              uid={child_block_form.data.uid}
              type={child_block_form.data.type}
              multi={child_block_form.data.multi}
              block_module={@block_module}
              children={child_block_form.data.children}
              parent_id={child_block_form.data.parent_id}
              parent_cid={@myself}
              parent_uid={@uid}
              form={child_block_form}
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
      <details>
        <summary>HTML</summary>
        <%= raw(@rendered_block) %>
      </details>
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
            value: %{level: @level, belongs_to: @belongs_to, sequence: @form[:sequence].value},
            target: @myself
          )
        }
      >
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
            id={"#{@id}-child-#{child_block_form.data.uid}"}
            uid={child_block_form.data.uid}
            type={child_block_form.data.type}
            multi={child_block_form.data.multi}
            block_module={@block_module}
            children={child_block_form.data.children}
            parent_id={child_block_form.data.parent_id}
            parent_cid={@myself}
            parent_uid={@uid}
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
            —— uid: <%= block_form[:uid].value %><br />
            —— description: <%= block_form[:description].value %><br />
          </.inputs_for>
        <% else %>
          <Input.hidden field={@form[:sequence]} />
          <.inputs_for :let={var} field={@form[:vars]}>
            <.var var={var} />
          </.inputs_for>
          <button>Save</button>
          —— sequence: <%= @form[:sequence].value %><br />
          <div class="brando-input">
            <Input.text field={@form[:uid]} label="UID" />
            <Input.text field={@form[:description]} label="Description" />
          </div>
        <% end %>
      </.form>

      <%= render_slot(@inner_block) %>
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
      <Input.hidden field={@var[:id]} />
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

  defp get_module(id) do
    {:ok, modules} = Brando.Content.list_modules(%{cache: {:ttl, :infinite}})

    case Enum.find(modules, &(&1.id == id)) do
      nil -> nil
      module -> module
    end
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
      sequence: socket.assigns.form[:sequence].value,
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
    block_module = socket.assigns.block_module
    parent_cid = socket.assigns.parent_cid
    form = socket.assigns.form
    level = socket.assigns.level
    action = (form[:id].value && :update) || :insert
    user_id = socket.assigns.current_user_id
    changeset = form.source

    updated_form = to_base_change_form(block_module, changeset, params, user_id)
    updated_changeset = updated_form.source

    require Logger

    Logger.error("""

    changeset.changes = #{inspect(changeset.changes)}
    updated_changeset.changes = #{inspect(updated_changeset.changes)}

    """)

    updated_form =
      if action == :insert and Changeset.changed?(updated_changeset, :block) do
        entry_block = Changeset.apply_changes(updated_changeset)
        to_base_change_form(block_module, entry_block, %{}, user_id, :insert)
      else
        updated_form
      end

    updated_changeset = updated_form.source

    Logger.error("""
    updated updated_changeset.changes = #{inspect(updated_changeset.changes)}
    """)

    # save changeset
    case Brando.repo().insert_or_update(updated_changeset) do
      {:ok, entry} ->
        preloaded_entry = Brando.repo().preload(entry, Brando.Content.Block.preloads())
        updated_form = to_base_change_form(block_module, preloaded_entry, %{}, user_id, :validate)
        send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})

      {:error, changeset} ->
        updated_form = to_base_change_form(block_module, changeset, %{}, user_id, :validate)
        send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})
    end

    {:noreply, socket}
  end

  def handle_event("validate_block", %{"child_block" => params}, socket) do
    require Logger

    Logger.error("""
    validate_block >> child_block
    """)

    parent_cid = socket.assigns.parent_cid
    form = socket.assigns.form
    level = socket.assigns.level

    updated_form =
      to_change_form(
        form.source.data,
        params,
        socket.assigns.current_user_id,
        :validate
      )

    send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})
    # {:noreply, stream_insert(socket, :children_forms, form)}
    {:noreply, socket}
  end

  def handle_event("validate_block", %{"entry_block" => params}, socket) do
    require Logger

    Logger.error("""
    validate_block >> entry_block
    """)

    block_module = socket.assigns.block_module
    uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    parent_uid = socket.assigns.parent_uid
    form = socket.assigns.form
    level = socket.assigns.level

    updated_form =
      to_base_change_form(
        block_module,
        form.source.data,
        params,
        socket.assigns.current_user_id,
        :validate
      )

    updated_changeset = updated_form.source
    send_update(parent_cid, %{event: "update_block", level: level, form: updated_form})

    require Logger

    Logger.error("""

    validate_block

    #{inspect(updated_changeset, pretty: true)}

    """)

    block = Changeset.apply_changes(updated_changeset)
    rendered_block = Brando.Villain.render_block(block, %{title: "HEI HEI!"})

    {:noreply, assign(socket, :rendered_block, rendered_block)}
  end

  # for forms that are on the base level, meaning
  # they are a join schema between an entry and a block
  defp to_base_change_form(block_module, entry_block_or_cs, params, user, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> block_module.changeset(params, user)
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
