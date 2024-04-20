# TODO: Deprecate?
defmodule BrandoAdmin.Components.Form.Input.Blocks do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

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
  # prop parent_uploads, :map

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
    <div id={"#{@field.id}-blocks-world"}>
      <Form.field_base field={@field} label={@label} instructions={@instructions}>
        <.live_component
          module={Blocks.BlockRenderer}
          id={"#{@field.id}-blocks"}
          base_form={@field.form}
          blocks={@blocks}
          block_forms={@block_forms}
          parent_uploads={@parent_uploads}
          templates={@templates}
          data_field={@data_field}
          insert_index={@insert_index}
          opts={@opts}
          insert_module={
            JS.push("insert_module", target: @myself)
            |> hide_modal("##{@field.id}-blocks-module-picker")
          }
          insert_section={
            JS.push("insert_section", target: @myself)
            |> hide_modal("##{@field.id}-blocks-module-picker")
          }
          insert_fragment={
            JS.push("insert_fragment", target: @myself)
            |> hide_modal("##{@field.id}-blocks-module-picker")
          }
          show_module_picker={
            JS.push("show_module_picker", target: @myself)
            |> show_modal("##{@field.id}-blocks-module-picker")
          }
          duplicate_block={JS.push("duplicate_block", target: @myself)}
        />
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
        parent_uploads={@parent_uploads}
      />
    <% end %>
    """
  end

  def comment(assigns) do
    assigns =
      assign(
        assigns,
        :block_data,
        assigns.block[:data]
        |> Brando.Utils.forms_from_field()
        |> List.first()
      )

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
      data-block-uid={@uid}
    >
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
      >
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

  def html(assigns) do
    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-index={@index} data-block-uid={@block[:uid].value}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Blocks.block
          id={"block-#{@uid}-base"}
          index={@index}
          is_ref?={@is_ref?}
          block_count={@block_count}
          base_form={@base_form}
          block={@block}
          belongs_to={@belongs_to}
          insert_module={@insert_module}
          duplicate_block={@duplicate_block}
        >
          <:description>
            <%= if @ref_description do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="html-block">
            <Input.code
              field={block_data[:text]}
              uid={@uid}
              id_prefix="block_data"
              label={gettext("Text")}
            />
          </div>
        </Blocks.block>
      </.inputs_for>
    </div>
    """
  end

  def markdown(assigns) do
    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-index={@index} data-block-uid={@block[:uid].value}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Blocks.block
          id={"block-#{@uid}-base"}
          index={@index}
          is_ref?={@is_ref?}
          block_count={@block_count}
          base_form={@base_form}
          block={@block}
          belongs_to={@belongs_to}
          insert_module={@insert_module}
          duplicate_block={@duplicate_block}
        >
          <:description>
            <%= if @ref_description do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="markdown-block">
            <Input.code
              field={block_data[:text]}
              uid={@uid}
              id_prefix="block_data"
              label={gettext("Text")}
            />
          </div>
        </Blocks.block>
      </.inputs_for>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div
      id={"block-#{@block[:uid].value}-wrapper"}
      data-block-index={@index}
      data-block-uid={@block[:uid].value}
    >
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Blocks.block
          id={"block-#{@block[:uid].value}-base"}
          index={@index}
          is_ref?={@is_ref?}
          block_count={@block_count}
          base_form={@base_form}
          block={@block}
          belongs_to={@belongs_to}
          insert_module={@insert_module}
          duplicate_block={@duplicate_block}
        >
          <:description>
            <%= if @ref_description do %>
              <%= @ref_description %>
            <% end %>
          </:description>
          <div class="alert">
            <Input.text
              field={block_data[:value]}
              uid={@block[:uid].value}
              id_prefix="block_data"
              label={block_data[:label].value}
              instructions={block_data[:help_text].value}
              placeholder={block_data[:placeholder].value}
            />
            <Input.hidden field={block_data[:placeholder]} />
            <Input.hidden field={block_data[:label]} />
            <Input.hidden field={block_data[:type]} />
            <Input.hidden field={block_data[:help_text]} />
          </div>
        </Blocks.block>
      </.inputs_for>
    </div>
    """
  end

  defp last_block?(%{index: index, block_count: block_count}) when index + 1 == block_count do
    true
  end

  defp last_block?(_), do: false
end
