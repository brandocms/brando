defmodule BrandoAdmin.Components.Form.Block do
  use BrandoAdmin, :live_component
  alias Ecto.Changeset
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias Brando.Content.Var
  import Brando.Gettext
  import Phoenix.LiveView.TagEngine
  import PolymorphicEmbed.HTML.Component

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
  #
  # TODO:
  # - Do we need LEVEL? If we just use parent_cid and message it?
  # - We do not need both belongs_to and level? Either belongs_to :root or level 0?

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
          uid: block_uid
        )
      end
    else
      # if the block has no children we send the current changeset back to the parent
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
          uid: block_uid
        )
      end
    else
      # if the block has no children we send the current changeset back to the parent
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

    changesets = socket.assigns.changesets
    updated_changesets = Map.put(changesets, uid, child_changeset)

    unless Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      # all changesets are present, ship 'em down

      updated_changesets_list = Map.values(updated_changesets)

      updated_changeset =
        if Enum.any?(updated_changesets_list, &(&1.changes !== %{})) do
          # if the changeset struct is a block we put it directly,
          # but if it's an entry block we need to put it under the block association
          if changeset.data.__struct__ == Brando.Content.Block do
            Changeset.put_assoc(
              changeset,
              :children,
              Enum.map(updated_changesets_list, &Map.put(&1, :action, nil))
            )
          else
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
    {:ok, stream_insert(socket, :children_forms, form)}
  end

  def update(%{event: "insert_block", sequence: sequence, module_id: module_id} = assigns, socket) do
    module_id = String.to_integer(module_id)
    user_id = socket.assigns.current_user_id
    parent_id = nil
    sequence = (is_binary(sequence) && String.to_integer(sequence)) || sequence

    empty_block = BlockField.build_block(module_id, user_id, parent_id)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    updated_block_list = List.insert_at(block_list, sequence, empty_block.uid)

    block_form =
      to_change_form(
        empty_block,
        %{sequence: sequence},
        user_id
      )

    changesets = socket.assigns.changesets
    updated_changesets = Map.put(changesets, empty_block.uid, nil)

    socket
    |> stream_insert(:children_forms, block_form, at: sequence)
    |> assign(:has_children?, true)
    |> assign(:block_list, updated_block_list)
    |> assign(:changesets, updated_changesets)
    |> send_child_sequence_update(updated_block_list)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to

    socket
    |> assign(assigns)
    |> assign(:form_has_changes, changeset.changes !== %{})
    |> assign(:form_is_new, !changeset.data.id)
    |> assign_new(:rendered_block, fn -> "" end)
    |> assign_new(:deleted, fn -> false end)
    |> assign_new(:active, fn -> Changeset.get_field(changeset, :active, true) end)
    |> assign_new(:collapsed, fn -> Changeset.get_field(changeset, :collapsed, false) end)
    |> assign_new(:module_id, fn ->
      block = (belongs_to == :root && changeset.data.block) || changeset.data
      block.module_id
    end)
    |> assign_new(:parent_uid, fn -> nil end)
    |> assign_new(:is_datasource?, fn -> Changeset.get_field(changeset, :datasource, false) end)
    |> assign_new(:has_children?, fn -> assigns.children !== [] end)
    |> maybe_assign_children()
    |> maybe_assign_module()
    |> maybe_parse_module()
    |> then(&{:ok, &1})
  end

  def maybe_assign_module(%{assigns: %{module_id: nil}} = socket) do
    socket
    |> assign_new(:module_name, fn -> nil end)
    |> assign_new(:module_class, fn -> nil end)
    |> assign_new(:module_code, fn -> nil end)
    |> assign_new(:module_type, fn -> nil end)
    |> assign_new(:is_datasource?, fn -> false end)
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
        |> assign_new(:module_datasource_module, fn -> module.datasource_module end)
        |> assign_new(:module_datasource_module_label, fn -> module_datasource_module end)
        |> assign_new(:module_datasource_type, fn -> module.datasource_type end)
        |> assign_new(:module_datasource_query, fn -> module.datasource_query end)
        |> assign_new(:entry_template, fn -> module.entry_template end)
    end
  end

  @liquid_regex_strips ~r/(({% hide %}(?:.*?){% endhide %}))|((?:{%(?:-)? for (\w+) in [a-zA-Z0-9_.?|"-]+ (?:-)?%})(?:.*?)(?:{%(?:-)? endfor (?:-)?%}))|(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|({%(?:-)? assign .*? (?:-)?%})|(((?:{%(?:-)? if .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endif (?:-)?%})))|(((?:{%(?:-)? unless .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endunless (?:-)?%})))|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}|._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s
  @liquid_regex_splits ~r/{% (?:ref|headless_ref) refs.(\w+) %}|<.*?>|\{\{\s?(.*?)\s?\}\}|{% picture ([a-zA-Z0-9_.?|"-]+) {.*} %}/
  @liquid_regex_chunks ~r/^{% (?:ref|headless_ref) refs.(?<ref>\w+) %}$|^{{ (?<content>[\w\s.|\"\']+) }}$|^{% picture (?<picture>[a-zA-Z0-9_.?|"-]+) {.*} %}$/

  defp maybe_parse_module(%{assigns: %{module_not_found: true}} = socket), do: socket

  defp maybe_parse_module(
         %{assigns: %{module_code: module_code, module_type: :liquid} = assigns} = socket
       ) do
    module_code =
      module_code
      |> liquid_strip_logic()
      |> emphasize_datasources(assigns)

    belongs_to = socket.assigns.belongs_to
    changeset = socket.assigns.form.source

    vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_field(:block)
        |> Changeset.change()
        |> Changeset.get_field(:vars)
      else
        Changeset.get_field(changeset, :vars)
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

          [variable, "", ""] ->
            {:variable, variable, liquid_render_variable(variable, vars)}

          ["", pic, ""] ->
            {:picture, pic, liquid_render_picture_src(pic, socket.assigns)}

          ["", "", ref] ->
            {:ref, ref}
        end
      end)

    socket
    |> assign(:liquid_splits, splits)
    |> assign(:vars, vars)
  end

  defp maybe_parse_module(socket) do
    assign(socket, liquid_splits: [], vars: [])
  end

  def maybe_assign_children(%{assigns: %{children: []}} = socket) do
    socket
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> %{} end)
    |> stream(:children_forms, [])
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
        active={@active}
        collapsed={@collapsed}
        deleted={@deleted}
        multi={true}
        is_datasource?={@is_datasource?}
        module_class={@module_class}
        vars={@vars}
        liquid_splits={@liquid_splits}
        parent_uploads={@parent_uploads}
        target={@myself}
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
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form.data.uid}"}
              uid={child_block_form.data.uid}
              type={child_block_form.data.type}
              multi={child_block_form.data.multi}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form.data.children}
              parent_id={child_block_form.data.parent_id}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_uploads={@parent_uploads}
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
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        active={@active}
        collapsed={@collapsed}
        deleted={@deleted}
        parent_uploads={@parent_uploads}
        is_datasource?={@is_datasource?}
        target={@myself}
        module_class={@module_class}
        vars={@vars}
        liquid_splits={@liquid_splits}
        insert_block={JS.push("insert_block", target: @myself)}
        has_children?={false}
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
        active={@active}
        deleted={@deleted}
        collapsed={@collapsed}
        target={@myself}
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
            data-id={child_block_form.data.id}
            data-uid={child_block_form.data.uid}
            data-parent_id={child_block_form.data.parent_id}
            class="draggable"
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form.data.uid}"}
              uid={child_block_form.data.uid}
              type={child_block_form.data.type}
              multi={child_block_form.data.multi}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form.data.children}
              parent_id={child_block_form.data.parent_id}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_uploads={@parent_uploads}
              form={child_block_form}
              current_user_id={@current_user_id}
              belongs_to={:container}
              level={@level + 1}
            >
            </.live_component>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  def container(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block = (belongs_to == :root && changeset.data.block) || changeset.data

    assigns =
      assigns
      |> assign(:uid, block.uid)
      |> assign(:type, block.type)
      |> assign(:module_id, block.module_id)

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
        class={["block"]}
        phx-hook="Brando.Block"
      >
        <.form
          for={@form}
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-submit="save_block"
          phx-target={@target}
        >
          <.toolbar
            uid={@uid}
            collapsed={@collapsed}
            active={@active}
            type={@type}
            block={@form}
            target={@target}
            is_ref?={false}
            is_datasource?={false}
          />
        </.form>
        <%= if @has_children? do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <.plus click={@insert_child_block} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :multi, :boolean, default: false
  attr :liquid_splits, :any, default: []
  attr :insert_block, :any, default: nil
  attr :insert_child_block, :any, default: nil

  def module(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block = (belongs_to == :root && changeset.data.block) || changeset.data

    assigns =
      assigns
      |> assign(:uid, block.uid)
      |> assign(:type, block.type)
      |> assign(:module_id, block.module_id)
      |> assign(:description, block.description)

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
        class={["block"]}
        phx-hook="Brando.Block"
      >
        <.form
          for={@form}
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-submit="save_block"
          phx-target={@target}
        >
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                active={@active}
                type={@type}
                multi={@multi}
                block={block_form}
                target={@target}
                is_ref?={false}
                is_datasource?={@is_datasource?}
              />
              <!-- module contents -->
              <div b-editor-tpl={@module_class}>
                <.vars vars={block_form[:vars]} uid={@uid} />

                <%= for split <- @liquid_splits do %>
                  <%= case split do %>
                    <% {:ref, ref} -> %>
                      <.ref
                        parent_uploads={@parent_uploads}
                        refs_field={block_form[:refs]}
                        ref_name={ref}
                      />
                    <% {:content, _} -> %>
                      <div>:content</div>
                      <%!-- <%= if @module_multi do %>
                        <.live_component
                          module={Blocks.Module.Entries}
                          id={"block-#{@uid}-entries"}
                          uid={@uid}
                          entry_template={@entry_template}
                          block_data={@block_data}
                          data_field={@data_field}
                          base_form={@base_form}
                          module_id={@module_id}
                        />
                      <% else %>
                        <%= "{{ content }}" %>
                      <% end %> --%>
                    <% {:variable, var_name, variable_value} -> %>
                      <div
                        class="rendered-variable"
                        data-popover={
                          gettext("Edit the entry directly to affect this variable [%{var_name}]",
                            var_name: var_name
                          )
                        }
                      >
                        <%= variable_value %>
                      </div>
                    <% {:picture, _, img_src} -> %>
                      <figure>
                        <img src={img_src} />
                      </figure>
                    <% _ -> %>
                      <%= raw(split) %>
                  <% end %>
                <% end %>
              </div>
              <!-- module contents end -->
            </.inputs_for>
          <% else %>
            <Input.hidden field={@form[:sequence]} />

            <.toolbar
              uid={@uid}
              collapsed={@collapsed}
              active={@active}
              type={@type}
              block={@form}
              target={@target}
              is_ref?={false}
              is_datasource?={@is_datasource?}
            />

            <.inputs_for :let={var} field={@form[:vars]}>
              <.var var={var} />
            </.inputs_for>
          <% end %>
        </.form>
        <%= if @has_children? do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <%= if @multi do %>
            <.plus click={@insert_child_block} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :ref_name, :string, required: true
  attr :refs_field, :any, required: true
  attr :refs, :any, required: true
  attr :parent_uploads, :any, required: true

  def ref(assigns) do
    # find the ref in the refs
    ref_forms = Brando.Utils.forms_from_field(assigns.refs_field)

    require Logger

    Logger.error("""

    ref_forms:
    #{inspect(ref_forms, pretty: true)}

    """)

    ref_form = Enum.find(ref_forms, fn %{data: %{name: name}} -> name == assigns.ref_name end)

    assigns =
      assigns
      |> assign(:ref_form, ref_form)
      |> assign(:ref_forms, ref_forms)

    ~H"""
    <%= if @ref_form do %>
      <section b-ref={@ref_form[:name].value}>
        <.polymorphic_embed_inputs_for :let={block} field={@ref_form[:data]}>
          <.dynamic_block
            id={@ref_form[:uid].value}
            block_id={@ref_form[:uid].value}
            is_ref?={true}
            ref_name={@ref_form[:name].value}
            ref_description={@ref_form[:description].value}
            block={block}
            parent_uploads={@parent_uploads}
          />
        </.polymorphic_embed_inputs_for>
        <Input.input type={:hidden} field={@ref_form[:description]} />
        <Input.input type={:hidden} field={@ref_form[:name]} />
        <Input.input type={:hidden} field={@ref_form[:id]} />
      </section>
    <% else %>
      <section class="alert danger">
        Ref <code><%= @ref_name %></code>
        is missing!<br /><br />
        If the module has been changed, this block might be out of sync!<br /><br />
        Available refs are:<br /><br />
        <%= for {%{data: %{name: ref_name}}, _} <- @ref_forms do %>
          &rarr; <%= ref_name %><br />
        <% end %>
      </section>
    <% end %>
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

  def block(assigns) do
    uid = assigns.block[:uid].value || Brando.Utils.generate_uid()

    assigns =
      assigns
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
      |> assign_new(:initial_classes, fn ->
        %{
          collapsed: assigns.block[:collapsed].value,
          disabled: assigns.block[:hidden].value
        }
      end)
      |> assign(:bg_color, assigns[:bg_color])
      |> assign(:uid, uid)
      |> assign(:hidden, assigns.block[:hidden].value)
      |> assign(:collapsed, assigns.block[:collapsed].value)
      |> assign(:marked_as_deleted, assigns.block[:marked_as_deleted].value)

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @initial_classes.collapsed && "collapsed",
        @initial_classes.disabled && "disabled"
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

      <Input.input type={:hidden} field={@block[:uid]} uid={@uid} id_prefix="base_block" />
      <Input.input type={:hidden} field={@block[:type]} uid={@uid} id_prefix="base_block" />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@block_type}
        style={"background-color: #{@bg_color}"}
        class={["block", "ref_block"]}
        phx-hook="Brando.Block"
      >
        <div>
          Toolbar :)
        </div>

        <div class="block-content" id={"block-#{@uid}-block-content"}>
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  def header(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block}>
          <:description>(H<%= block_data[:level].value %>)</:description>
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
              rows={1}
            />
            <Input.input type={:hidden} field={block_data[:class]} uid={@uid} />
            <Input.input type={:hidden} field={block_data[:placeholder]} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def text(assigns) do
    extensions = "all"
    # case assigns.block[:data].value.extensions do
    #   nil -> "all"
    #   extensions when is_list(extensions) -> Enum.join(extensions, "|")
    #   extensions -> extensions
    # end

    require Logger

    Logger.error("""

    extensions: #{inspect(extensions, pretty: true)}

    """)

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text_type, assigns.block[:data].value.type)
      |> assign(:extensions, extensions)

    ~H"""
    <.inputs_for :let={text_block_data} field={@block[:data]}>
      <div id={"ref-#{@uid}-wrapper"} data-block-uid={@uid}>
        <.block id={"block-#{@uid}-base"} block={@block}>
          <:description>
            <%= if @ref_description do %>
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
            <div>inspect me</div>
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
      <.icon name="hero-plus-circle-mini" />
    </button>
    """
  end

  attr :uid, :string, required: true
  attr :vars, :any, required: true

  def vars(assigns) do
    ~H"""
    <div class="block-vars">
      <.inputs_for :let={var} field={@vars}>
        <.live_component
          module={RenderVar}
          id={"block-#{@uid}-render-var-#{var.id}"}
          var={var}
          render={:only_important}
          in_block
        />
      </.inputs_for>
    </div>
    """
  end

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

  attr :instructions, :string, default: nil
  attr :config, :boolean, default: false
  attr :multi, :boolean, default: false
  slot :datasource
  slot :inner_block

  # TODO: CAN WE DROP THE block ASSIGN HERE?? just pass description field?
  def toolbar(assigns) do
    ~H"""
    <div class="block-toolbar">
      <div class="block-description">
        <button
          type="button"
          class={"switch small show-disabled #{@active && "toggled"}"}
          phx-click="toggle_active"
          phx-target={@target}
        >
          <div class="slider round"></div>
        </button>
        <span class="block-type">
          <%= @type %><span :if={@multi}>[multi]</span>
        </span>
        <span class="arrow">&rarr;</span> <%= @block[:description].value %> — <%= @block[:uid].value %>
      </div>
      <div :if={@is_datasource?} class="block-datasource" id={"block-#{@uid}-block-datasource"}>
        <%= render_slot(@datasource) %>
      </div>
      <div class="block-content" id={"block-#{@uid}-block-content"}>
        <%= render_slot(@inner_block) %>
      </div>
      <div class="block-actions" id={"block-#{@uid}-block-actions"}>
        <.handle />
        <div
          :if={@instructions}
          class="block-action help"
          phx-click={JS.push("toggle_help", target: @target)}
        >
          <.icon name="hero-question-mark-circle" />
        </div>
        <button
          if={!@is_ref?}
          type="button"
          phx-value-block_uid={@uid}
          class="block-action duplicate"
          phx-click="duplicate_block"
          phx-target={@target}
        >
          <.icon name="hero-document-duplicate" />
        </button>
        <button
          :if={@config}
          type="button"
          class="block-action config"
          phx-click={show_modal("#block-#{@uid}_config")}
        >
          <.icon name="hero-cog-8-tooth" />
        </button>
        <button
          :if={!@is_ref?}
          type="button"
          class="block-action toggler"
          phx-click="delete_block"
          phx-target={@target}
        >
          <.icon name="hero-trash" />
        </button>
        <button
          type="button"
          class="block-action toggler"
          phx-click="collapse_block"
          phx-target={@target}
        >
          <.icon :if={@collapsed} name="hero-eye-slash" />
          <.icon :if={!@collapsed} name="hero-eye" />
        </button>
      </div>
    </div>
    """
  end

  def handle_event("collapse_block", _, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  def handle_event("toggle_active", _, socket) do
    changeset = socket.assigns.form.source

    updated_changeset =
      EctoNestedChangeset.update_at(changeset, [:block, :active], &(!&1))

    updated_form =
      to_base_change_form(
        socket.assigns.block_module,
        updated_changeset,
        %{},
        socket.assigns.current_user_id
      )

    socket
    |> assign(:form, updated_form)
    |> assign(:active, !socket.assigns.active)
    |> then(&{:noreply, &1})
  end

  def handle(assigns) do
    ~H"""
    <div class="sort-handle block-action" data-sortable-group={1}>
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

  def handle_event("insert_block", %{"container" => _}, socket) do
    require Logger

    Logger.error("""



    SPECIAL CASE CONTAINER!!

    myself: #{inspect(socket.assigns.myself)}
    parent_cid: #{inspect(socket.assigns.parent_cid)}


    """)

    # message block picker —— special case for empty container.
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"

    send_update(BrandoAdmin.Components.Form.BlockField.ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      sequence: socket.assigns.form[:sequence].value,
      parent_cid: socket.assigns.myself
    )

    {:noreply, socket}
  end

  def handle_event("insert_block", _, socket) do
    require Logger

    Logger.error("""

    WHAT ON EARTH.
    parent_cid: #{inspect(socket.assigns.parent_cid)}

    """)

    # message block picker
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"

    send_update(BrandoAdmin.Components.Form.BlockField.ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      sequence: socket.assigns.form[:sequence].value,
      parent_cid: socket.assigns.parent_cid
    )

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
    {:noreply, socket}
  end

  def handle_event("validate_block", %{"entry_block" => params}, socket) do
    require Logger

    Logger.error("""
    validate_block >> entry_block
    """)

    require Logger

    Logger.error("""

    params:
    #{inspect(params, pretty: true)}

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

  defp liquid_render_picture_src("entry." <> var_path_string, assigns) do
    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    entry = Ecto.Changeset.apply_changes(assigns.base_form.source)

    if path = Brando.Utils.try_path(entry, var_path ++ [:path]) do
      Brando.Utils.media_url(path)
    else
      ""
    end
  end

  defp liquid_render_picture_src(var_name, %{vars: vars}) do
    # FIXME
    #
    # This is suboptimal at best. We preload all our image vars in the form, but when running
    # the polymorphic changesets, it clobbers the image's `value` - resetting it.
    #
    # Everything here will hopefully improve when we can update poly changesets instead
    # of replacing/inserting new every time.

    case Enum.find(vars, &(&1.key == var_name)) do
      %Brando.Content.OldVar.Image{value_id: nil} ->
        ""

      %Brando.Content.OldVar.Image{value: %Ecto.Association.NotLoaded{}, value_id: image_id} ->
        case Brando.Cache.get("var_image_#{image_id}") do
          nil ->
            image = Brando.Images.get_image!(image_id)
            media_path = Brando.Utils.media_url(image.path)
            Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
            media_path

          media_path ->
            media_path
        end

      %Brando.Content.OldVar.Image{value: image, value_id: image_id} ->
        media_path = Brando.Utils.media_url(image.path)
        Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
        media_path

      %Brando.Images.Image{path: path} ->
        Brando.Utils.media_url(path)

      _ ->
        ""
    end
  end

  defp liquid_render_variable("entry." <> var_path_string, assigns) do
    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    entry = Ecto.Changeset.apply_changes(assigns.base_form.source)
    Brando.Utils.try_path(entry, var_path) |> raw()
  rescue
    ArgumentError ->
      "entry.#{var_path_string}"
  end

  defp liquid_render_variable(var, vars) do
    case Enum.find(vars, &(&1.key == var)) do
      %{value: value} -> value
      nil -> var
    end
  end
end
