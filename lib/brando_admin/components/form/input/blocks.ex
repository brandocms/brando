defmodule BrandoAdmin.Components.Form.Input.Blocks do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import BrandoAdmin.Components.Form.Input.Blocks.Utils
  import Brando.Gettext
  import Ecto.Changeset
  import Phoenix.LiveView.TagEngine

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data blocks, :list
  # data block_forms, :list
  # data insert_index, :integer
  # data data_field, :atom
  # data templates, :any

  def mount(socket) do
    {:ok, assign(socket, insert_index: 0)}
  end

  def update(%{image_drawer_target: target}, socket) do
    {:ok, assign(socket, :image_drawer_target, target)}
  end

  def update(assigns, socket) do
    blocks = assigns.field.value || []
    block_forms = inputs_for_blocks(assigns.field) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:image_drawer_target, fn -> socket.assigns.myself end)
     |> assign_new(:templates, fn ->
       if template_namespace = assigns.opts[:template_namespace] do
         {:ok, templates} =
           Brando.Content.list_templates(%{filter: %{namespace: template_namespace}})

         templates
       else
         nil
       end
     end)
     |> assign(:blocks, blocks)
     |> assign(:block_forms, block_forms)
     |> assign(:data_field, assigns.field)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base
        field={@field}
        label={@label}
        instructions={@instructions}>

        <.live_component module={Blocks.BlockRenderer}
          id={"#{@field.id}-blocks"}
          base_form={@field.form}
          blocks={@blocks}
          block_forms={@block_forms}
          uploads={@uploads}
          templates={@templates}
          data_field={@data_field}
          insert_index={@insert_index}
          opts={@opts}
          insert_module={JS.push("insert_module", target: @myself) |> hide_modal("##{@field.id}-blocks-module-picker")}
          insert_section={JS.push("insert_section", target: @myself) |> hide_modal("##{@field.id}-blocks-module-picker")}
          insert_fragment={JS.push("insert_fragment", target: @myself) |> hide_modal("##{@field.id}-blocks-module-picker")}
          show_module_picker={JS.push("show_module_picker", target: @myself) |> show_modal("##{@field.id}-blocks-module-picker")}
          duplicate_block={JS.push("duplicate_block", target: @myself)} />
      </Form.field_base>
    </div>
    """
  end

  def handle_event(
        "show_module_picker",
        %{"index" => index_binary},
        socket
      ) do
    {:noreply, assign(socket, insert_index: index_binary)}
  end

  def handle_event("insert_section", %{"index" => index_binary}, socket) do
    field = socket.assigns.field
    changeset = field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    new_block = %Brando.Villain.Blocks.ContainerBlock{
      type: "container",
      data: %Brando.Villain.Blocks.ContainerBlock.Data{
        palette_id: nil,
        blocks: []
      },
      uid: Brando.Utils.generate_uid()
    }

    {index, ""} = Integer.parse(index_binary)

    new_data =
      changeset
      |> get_blocks_data()
      |> List.insert_at(index, new_block)

    updated_changeset = put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event("insert_fragment", %{"index" => index_binary}, socket) do
    field = socket.assigns.field
    changeset = field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    new_block = %Brando.Villain.Blocks.FragmentBlock{
      type: "fragment",
      data: %Brando.Villain.Blocks.FragmentBlock.Data{
        fragment_id: nil
      },
      uid: Brando.Utils.generate_uid()
    }

    {index, ""} = Integer.parse(index_binary)

    new_data =
      changeset
      |> get_blocks_data()
      |> List.insert_at(index, new_block)

    updated_changeset = put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "insert_module",
        %{"index" => index_binary, "module-id" => module_id_binary},
        socket
      ) do
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"
    module_id = String.to_integer(module_id_binary)

    {:ok, modules} = Brando.Content.list_modules(%{cache: {:ttl, :infinite}})
    module = Enum.find(modules, &(&1.id == module_id))

    generated_uid = Brando.Utils.generate_uid()

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)

    # if module.wrapper is true, this is a multi block!
    new_block = %Brando.Villain.Blocks.ModuleBlock{
      type: "module",
      data: %Brando.Villain.Blocks.ModuleBlock.Data{
        module_id: module_id,
        multi: module.wrapper,
        vars: module.vars,
        refs: refs_with_generated_uids
      },
      uid: generated_uid
    }

    {index, ""} = Integer.parse(index_binary)

    new_data =
      changeset
      |> get_blocks_data()
      |> List.insert_at(index, new_block)

    updated_changeset = put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event("duplicate_block", %{"block_uid" => block_uid}, socket) do
    field = socket.assigns.field
    field_name = field.field
    changeset = field.form.source
    data = get_field(changeset, field_name)
    source_position = Enum.find_index(data, &(&1.uid == block_uid))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    duplicated_block =
      data
      |> Enum.at(source_position)
      |> replace_uids()

    new_data = List.insert_at(data, source_position + 1, duplicated_block)

    updated_changeset = put_change(changeset, field_name, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  defp get_blocks_data(changeset) do
    get_field(changeset, :data) || []
  end

  defp replace_uids(
         %Brando.Villain.Blocks.ModuleBlock{data: %{multi: true, entries: entries, refs: refs}} =
           block
       ) do
    updated_refs = Brando.Villain.add_uid_to_refs(refs)
    updated_entries = Enum.map(entries, &replace_uids/1)

    block
    |> put_in([Access.key(:uid)], Brando.Utils.generate_uid())
    |> put_in([Access.key(:data), Access.key(:refs)], updated_refs)
    |> put_in([Access.key(:data), Access.key(:entries)], updated_entries)
  end

  defp replace_uids(%Brando.Content.Module.Entry{} = block) do
    put_in(block, [Access.key(:uid)], Brando.Utils.generate_uid())
  end

  defp replace_uids(%Brando.Villain.Blocks.ModuleBlock{data: %{refs: refs}} = block) do
    updated_refs = Brando.Villain.add_uid_to_refs(refs)

    block
    |> put_in([Access.key(:uid)], Brando.Utils.generate_uid())
    |> put_in([Access.key(:data), Access.key(:refs)], updated_refs)
  end

  defp replace_uids(%Brando.Villain.Blocks.ContainerBlock{data: %{blocks: blocks}} = block) do
    updated_blocks = Enum.map(blocks, &replace_uids/1)

    block
    |> put_in([Access.key(:uid)], Brando.Utils.generate_uid())
    |> put_in([Access.key(:data), Access.key(:blocks)], updated_blocks)
  end

  ## Function components
  def block(assigns) do
    uid = assigns.block[:uid].value || Brando.Utils.generate_uid()

    assigns =
      assigns
      |> assign_new(:is_ref?, fn -> false end)
      |> assign_new(:is_entry?, fn -> false end)
      |> assign_new(:wide_config, fn -> false end)
      |> assign_new(:config, fn -> nil end)
      |> assign_new(:config_footer, fn -> nil end)
      |> assign_new(:description, fn -> nil end)
      |> assign_new(:type, fn -> nil end)
      |> assign_new(:is_datasource?, fn -> false end)
      |> assign_new(:datasource, fn -> nil end)
      |> assign_new(:block_type, fn ->
        assigns.block[:type].value || (assigns.is_entry? && "entry")
      end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:render, fn -> nil end)
      |> assign_new(:initial_classes, fn ->
        %{
          collapsed: assigns.block[:collapsed].value,
          disabled: assigns.block[:hidden].value
        }
      end)
      |> assign(:bg_color, assigns[:bg_color])
      |> assign(:last_block?, last_block?(assigns))
      |> assign(:uid, uid)
      |> assign(:hidden, assigns.block[:hidden].value)
      |> assign(:collapsed, assigns.block[:collapsed].value)
      |> assign(:marked_as_deleted, assigns.block[:marked_as_deleted].value)

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={render_classes([
        "base-block",
        collapsed: @initial_classes.collapsed,
        disabled: @initial_classes.disabled
      ])}>
      <Blocks.Plus.render
        :if={!@is_ref? and !@is_entry?}
        index={@index}
        click={@insert_module} />

      <Content.modal title={gettext "Configure"} id={"block-#{@uid}_config"} wide={@wide_config}>
        <%= if @config do %>
          <%= render_slot @config %>
        <% end %>
        <:footer>
          <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
            <%= gettext "Close" %>
          </button>
          <%= if @config_footer do %>
            <%= render_slot @config_footer %>
          <% end %>
        </:footer>
      </Content.modal>

      <Input.input type={:hidden} field={@block[:uid]} uid={@uid} id_prefix="base_block" />
      <Input.input type={:hidden} field={@block[:type]} uid={@uid} id_prefix="base_block" />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@block_type}
        style={"background-color: #{@bg_color}"}
        class={render_classes(["block", ref_block: @is_ref?])}
        phx-hook="Brando.Block">

        <div class="block-description" id={"block-#{@uid}-block-description"}>
          <Form.label
            field={@block[:hidden]}
            class="switch small inverse"
            uid={@uid}
            id_prefix="base_block"
            click={toggle_block(@hidden, @uid)}>
            <Input.input type={:checkbox} field={@block[:hidden]} uid={@uid} id_prefix="base_block" />
            <div class="slider round"></div>
          </Form.label>
          <span class="block-type">
            <%= if @type do %><%= render_slot @type %><% else %><%= @block_type %><% end %>
          </span> <span class="arrow">&rarr;</span> <%= render_slot @description %>
        </div>
        <div :if={@is_datasource?} class="block-datasource" id={"block-#{@uid}-block-datasource"}>
          <%= render_slot(@datasource) %>
        </div>
        <div class="block-content" id={"block-#{@uid}-block-content"}>
          <%= render_slot @inner_block %>
        </div>
        <div :if={@render} class="block-render">
          <div class="block-render-preview">Preview &darr;</div>
          <%= render_slot @render %>
        </div>
        <div class="block-actions" id={"block-#{@uid}-block-actions"}>
          <div
            :if={!@is_ref?}
            class="block-action move"
            data-sortable-group={@belongs_to}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M11 11V5.828L9.172 7.657 7.757 6.243 12 2l4.243 4.243-1.415 1.414L13 5.828V11h5.172l-1.829-1.828 1.414-1.415L22 12l-4.243 4.243-1.414-1.415L18.172 13H13v5.172l1.828-1.829 1.415 1.414L12 22l-4.243-4.243 1.415-1.414L11 18.172V13H5.828l1.829 1.828-1.414 1.415L2 12l4.243-4.243 1.414 1.415L5.828 11z"/></svg>
          </div>
          <div
            :if={@instructions}
            class="block-action help"
            phx-click={JS.push("toggle_help", target: @myself)}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16zm-1-5h2v2h-2v-2zm2-1.645V14h-2v-1.5a1 1 0 0 1 1-1 1.5 1.5 0 1 0-1.471-1.794l-1.962-.393A3.501 3.501 0 1 1 13 13.355z"/></svg>
          </div>
          <button
            if={!@is_ref?}
            type="button"
            phx-value-block_uid={@uid}
            class="block-action duplicate"
            phx-click={@duplicate_block}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M7 6V3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-3v3c0 .552-.45 1-1.007 1H4.007A1.001 1.001 0 0 1 3 21l.003-14c0-.552.45-1 1.007-1H7zM5.003 8L5 20h10V8H5.003zM9 6h8v10h2V4H9v2z"/></svg>
          </button>
          <button
            :if={@config}
            type="button"
            class="block-action config"
            phx-click={show_modal("#block-#{@uid}_config")}>
            <%= if @block_type == "module" do %>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M8.595 12.812a3.51 3.51 0 0 1 0-1.623l-.992-.573 1-1.732.992.573A3.496 3.496 0 0 1 11 8.645V7.5h2v1.145c.532.158 1.012.44 1.405.812l.992-.573 1 1.732-.992.573a3.51 3.51 0 0 1 0 1.622l.992.573-1 1.732-.992-.573a3.496 3.496 0 0 1-1.405.812V16.5h-2v-1.145a3.496 3.496 0 0 1-1.405-.812l-.992.573-1-1.732.992-.572zM12 13.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM15 4H5v16h14V8h-4V4zM3 2.992C3 2.444 3.447 2 3.999 2H16l5 5v13.993A1 1 0 0 1 20.007 22H3.993A1 1 0 0 1 3 21.008V2.992z"/></svg>
            <% else %>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M8.686 4l2.607-2.607a1 1 0 0 1 1.414 0L15.314 4H19a1 1 0 0 1 1 1v3.686l2.607 2.607a1 1 0 0 1 0 1.414L20 15.314V19a1 1 0 0 1-1 1h-3.686l-2.607 2.607a1 1 0 0 1-1.414 0L8.686 20H5a1 1 0 0 1-1-1v-3.686l-2.607-2.607a1 1 0 0 1 0-1.414L4 8.686V5a1 1 0 0 1 1-1h3.686zM6 6v3.515L3.515 12 6 14.485V18h3.515L12 20.485 14.485 18H18v-3.515L20.485 12 18 9.515V6h-3.515L12 3.515 9.515 6H6zm6 10a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm0-2a2 2 0 1 0 0-4 2 2 0 0 0 0 4z"/></svg>
            <% end %>
          </button>
          <Form.label
            :if={!@is_ref?}
            field={@block[:marked_as_deleted]}
            class="block-action toggler"
            uid={@uid}
            id_prefix="base_block"
            click={toggle_deleted(@marked_as_deleted, @uid)}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z"/></svg>
            <Input.input type={:checkbox} field={@block[:marked_as_deleted]} uid={@uid} id_prefix="base_block" />
          </Form.label>
          <Form.label
            field={@block[:collapsed]}
            class="block-action toggler"
            click={toggle_collapsed(@collapsed, @uid)}
            uid={@uid}
            id_prefix="base_block">
            <%= if @collapsed do %>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M9.342 18.782l-1.931-.518.787-2.939a10.988 10.988 0 0 1-3.237-1.872l-2.153 2.154-1.415-1.415 2.154-2.153a10.957 10.957 0 0 1-2.371-5.07l1.968-.359C3.903 10.812 7.579 14 12 14c4.42 0 8.097-3.188 8.856-7.39l1.968.358a10.957 10.957 0 0 1-2.37 5.071l2.153 2.153-1.415 1.415-2.153-2.154a10.988 10.988 0 0 1-3.237 1.872l.787 2.94-1.931.517-.788-2.94a11.072 11.072 0 0 1-3.74 0l-.788 2.94z"/></svg>
            <% else %>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 3c5.392 0 9.878 3.88 10.819 9-.94 5.12-5.427 9-10.819 9-5.392 0-9.878-3.88-10.819-9C2.121 6.88 6.608 3 12 3zm0 16a9.005 9.005 0 0 0 8.777-7 9.005 9.005 0 0 0-17.554 0A9.005 9.005 0 0 0 12 19zm0-2.5a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9zm0-2a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/></svg>
            <% end %>
            <Input.input type={:checkbox} field={@block[:collapsed]} uid={@uid} id_prefix="base_block" />
          </Form.label>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_block(hidden, uid) do
    (hidden && JS.remove_class("disabled", to: "#base-block-#{uid}")) ||
      JS.add_class("disabled", to: "#base-block-#{uid}")
  end

  defp toggle_deleted(marked_as_deleted, uid) do
    (marked_as_deleted && JS.remove_class("deleted", to: "#base-block-#{uid}")) ||
      JS.add_class("deleted", to: "#base-block-#{uid}")
  end

  defp toggle_collapsed(collapsed, uid) do
    (collapsed && JS.remove_class("collapsed", to: "#base-block-#{uid}")) ||
      JS.add_class("collapsed", to: "#base-block-#{uid}")
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
           |> Recase.to_pascal()) <> "Block"

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
      <%= component(@component_target, assigns, {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}) %>
    <% else %>
      <.live_component module={@component_target}
        id={@block_id}
        block={@block}
        is_ref?={@is_ref?}
        base_form={@base_form}
        data_field={@data_field}
        index={@index}
        opts={@opts}
        belongs_to={@belongs_to}
        ref_name={@ref_name}
        ref_description={@ref_description}
        block_count={@block_count}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
        uploads={@uploads} />
    <% end %>
    """
  end

  def text(assigns) do
    extensions =
      case assigns.block[:data].value.extensions do
        nil -> "all"
        extensions when is_list(extensions) -> Enum.join(extensions, "|")
        extensions -> extensions
      end

    assigns =
      assigns
      |> assign(:text_block_data, List.first(inputs_for(assigns.block, :data)))
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text_type, assigns.block[:data].value.type)
      |> assign(:extensions, extensions)

    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= if @ref_description do %>
            <%= @ref_description %>
          <% else %>
            <%= @text_type %>
          <% end %>
        </:description>
        <:config>
          <Input.radios
            field={@text_block_data[:type]}
            label="Type"
            uid={@uid}
            id_prefix="block_data"
            opts={[options: [
              %{label: "Paragraph", value: "paragraph"},
              %{label: "Lede", value: "lede"},
            ]]} />

          <Form.array_inputs
            :let={%{value: array_value, name: array_name}}
            field={@text_block_data[:extensions]}>
            <input type="hidden" name={array_name} value={array_value} />
          </Form.array_inputs>
        </:config>
        <div class={render_classes(["text-block", @text_type])}>
          <div class="tiptap-wrapper" id={"block-#{@uid}-rich-text-wrapper"}>
            <div
              id={"block-#{@uid}-rich-text"}
              data-block-uid={@uid}
              data-tiptap-extensions={@extensions}
              phx-hook="Brando.TipTap"
              data-name="TipTap">
              <div
                id={"block-#{@uid}-rich-text-target-wrapper"}
                class="tiptap-target-wrapper"
                phx-update="ignore">
                <div
                  id={"block-#{@uid}-rich-text-target"}
                  class="tiptap-target">
                </div>
              </div>
              <Input.input
                type={:hidden}
                field={@text_block_data[:text]}
                uid={@uid}
                id_prefix="block_data"
                class="tiptap-text"
                phx_debounce={750} />
            </div>
          </div>
        </div>
      </Blocks.block>
    </div>
    """
  end

  def comment(assigns) do
    assigns = assign(assigns, :block_data, List.first(inputs_for(assigns.block, :data)))

    text =
      case assigns.block_data[:text].value do
        nil -> nil
        text -> text |> Brando.HTML.nl2br() |> raw
      end

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text, text)

    ~H"""
    <div
      class="comment-block"
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= gettext("Not shown...") %>
        </:description>
        <:config>
          <div id={"block-#{@uid}-conf-textarea"}>
            <Input.textarea field={@block_data[:text]} uid={@uid} id_prefix="block_data" />
          </div>
        </:config>
        <div id={"block-#{@uid}-comment"}>
          <%= if @text do %>
            <%= @text %>
          <% end %>
        </div>
      </Blocks.block>
    </div>
    """
  end

  def header(assigns) do
    block_data = List.first(inputs_for(assigns.block, :data))

    assigns =
      assigns
      |> assign(:level, block_data[:level].value)
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:block_data, block_data)

    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>(H<%= @level %>)</:description>
        <:config>
          <Input.radios
            field={@block_data[:level]}
            label="Level"
            uid={@uid}
            id_prefix="block_data"
            id={"block-#{@uid}-data-level"}
            opts={[options: [
              %{label: "H1", value: 1},
              %{label: "H2", value: 2},
              %{label: "H3", value: 3},
              %{label: "H4", value: 4},
              %{label: "H5", value: 5},
              %{label: "H6", value: 6},
            ]]} />

          <Input.text
            field={@block_data[:id]}
            uid={@uid}
            id_prefix="block_data"
            label="ID" />

          <Input.text
            field={@block_data[:link]}
            uid={@uid}
            id_prefix="block_data"
            label="Link" />
        </:config>
        <div class="header-block">
          <Input.input
            type={:textarea}
            field={@block_data[:text]}
            uid={@uid}
            id_prefix="block_data"
            class={"h#{@level}"}
            phx_update="ignore"
            phx_debounce={750}
            data_autosize={true}
            rows={1} />
          <Input.input type={:hidden} field={@block_data[:class]} uid={@uid} id_prefix="block_data" />
          <Input.input type={:hidden} field={@block_data[:placeholder]} uid={@uid} id_prefix="block_data" />
        </div>
      </Blocks.block>
    </div>
    """
  end

  def html(assigns) do
    block_data = List.first(inputs_for(assigns.block, :data))

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:block_data, block_data)

    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= if @ref_description do %>
            <%= @ref_description %>
          <% end %>
        </:description>
        <div class="html-block">
          <Input.code
            field={@block_data[:text]}
            uid={@uid}
            id_prefix="block_data"
            label={gettext "Text"}
          />
        </div>
      </Blocks.block>
    </div>
    """
  end

  def markdown(assigns) do
    block_data = List.first(inputs_for(assigns.block, :data))

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:block_data, block_data)

    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= if @ref_description do %>
            <%= @ref_description %>
          <% end %>
        </:description>
        <div class="markdown-block">
          <Input.code
            field={@block_data[:text]}
            uid={@uid}
            id_prefix="block_data"
            label={gettext "Text"}
          />
        </div>
      </Blocks.block>
    </div>
    """
  end

  def input(assigns) do
    block_data = List.first(inputs_for(assigns.block, :data))

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:label, block_data[:label].value)
      |> assign(:placeholder, block_data[:placeholder].value)
      |> assign(:help_text, block_data[:help_text].value)
      |> assign(:block_data, block_data)

    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
        <:description>
          <%= if @ref_description do %>
            <%= @ref_description %>
          <% end %>
        </:description>
        <div class="alert">
          <Input.text
            field={@block_data[:value]}
            uid={@uid}
            id_prefix="block_data"
            label={@label}
            instructions={@help_text}
            placeholder={@placeholder} />
            <Input.hidden field={@block_data[:placeholder]} />
            <Input.hidden field={@block_data[:label]} />
            <Input.hidden field={@block_data[:type]} />
            <Input.hidden field={@block_data[:help_text]} />
        </div>
      </Blocks.block>
    </div>

    """
  end

  defp last_block?(%{index: index, block_count: block_count}) when index + 1 == block_count do
    true
  end

  defp last_block?(_), do: false
end
