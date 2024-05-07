defmodule BrandoAdmin.Components.Form.Block do
  alias Brando.Content.BlockIdentifier
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
  alias Brando.Content.Var
  import Brando.Gettext
  import Phoenix.LiveView.TagEngine
  import PolymorphicEmbed.HTML.Component

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

    empty_block_cs = BlockField.build_block(module_id, user_id, parent_id)
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
    updated_changesets = Map.put(changesets, uid, nil)

    selector = "[data-block-uid=\"#{uid}\"]"

    socket
    |> stream_insert(:children_forms, block_form, at: sequence)
    |> assign(:has_children?, true)
    |> assign(:block_list, updated_block_list)
    |> assign(:changesets, updated_changesets)
    |> send_child_sequence_update(updated_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
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
    parent_id = socket.assigns.parent_id
    id = socket.assigns.id

    block_changeset = get_block_changeset(changeset, belongs_to)
    refs = Changeset.get_embed(block_changeset, :refs)

    new_refs =
      Enum.map(refs, fn ref ->
        if Changeset.get_field(ref, :name) == ref_name do
          block =
            ref
            |> Changeset.get_field(:data)
            |> Changeset.change()

          updated_block = Changeset.put_embed(block, :data, ref_data)
          Changeset.put_change(ref, :data, updated_block)
        else
          ref
        end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, new_refs)
      end

    new_form =
      if belongs_to == :root do
        to_form(updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(updated_changeset,
          as: "child_block",
          id: "child_block_form-#{parent_id}-#{id}"
        )
      end

    socket
    |> assign(:form, new_form)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to

    block_cs = get_block_changeset(changeset, belongs_to)

    socket
    |> assign(assigns)
    |> assign(:active, Changeset.get_field(changeset, :active))
    |> assign(:form_has_changes, changeset.changes !== %{})
    |> assign(:form_is_new, !changeset.data.id)
    |> assign_new(:uid, fn -> Changeset.get_field(block_cs, :uid) end)
    |> assign_new(:type, fn -> Changeset.get_field(block_cs, :type) end)
    |> assign_new(:multi, fn -> Changeset.get_field(block_cs, :multi) end)
    |> assign_new(:parent_id, fn -> Changeset.get_field(block_cs, :parent_id) end)
    |> assign_new(:rendered_block, fn -> "" end)
    |> assign_new(:deleted, fn -> false end)
    |> assign_new(:collapsed, fn -> Changeset.get_field(changeset, :collapsed) end)
    |> assign_new(:module_id, fn ->
      block_cs = get_block_changeset(changeset, belongs_to)
      Changeset.get_field(block_cs, :module_id)
    end)
    |> assign_new(:has_children?, fn -> assigns.children !== [] end)
    |> assign_new(:available_identifiers, fn -> [] end)
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
    # require Logger

    # Logger.error("""

    # -> maybe_parse_module
    # -> module_code: #{inspect(module_code, pretty: true)}

    # """)

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
            {:variable, variable, liquid_render_entry_variable(variable, entry)}

          [block_variable, "", ""] ->
            {:variable, block_variable, liquid_render_block_variable(block_variable, vars)}

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

  defp assign_available_identifiers(socket) do
    module = Module.concat([socket.assigns.module_datasource_module])
    query = socket.assigns.module_datasource_query
    # TODO: get entry here
    entry = %{language: :en}

    {:ok, available_identifiers} =
      Brando.Datasource.list_selection(
        module,
        query,
        Map.get(entry, :language),
        socket.assigns.vars
      )

    assign(socket, :available_identifiers, available_identifiers)
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
        module_class={@module_class}
        vars={@vars}
        liquid_splits={@liquid_splits}
        parent_uploads={@parent_uploads}
        rendered_block={@rendered_block}
        target={@myself}
        insert_block={JS.push("insert_block", target: @myself)}
        insert_multi_block={JS.push("insert_block_entry", target: @myself)}
        insert_child_block={JS.push("insert_block", value: %{container: true}, target: @myself)}
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
            data-uid={child_block_form.data.uid}
            data-parent_id={child_block_form.data.parent_id}
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form.data.uid}"}
              multi={child_block_form.data.multi}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form.data.children}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_uploads={@parent_uploads}
              form={child_block_form}
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
        target={@myself}
        module_class={@module_class}
        vars={@vars}
        liquid_splits={@liquid_splits}
        rendered_block={@rendered_block}
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
        target={@myself}
        module_class={@module_class}
        vars={@vars}
        liquid_splits={@liquid_splits}
        rendered_block={@rendered_block}
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
        deleted={@deleted}
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
            data-id={child_block_form[:id].value}
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            class="draggable"
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_uploads={@parent_uploads}
              entry={@entry}
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
      |> assign(:module_id, Changeset.get_field(block_cs, :module_id))
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
        data-module-id={@module_id}
        class={["block"]}
        phx-hook="Brando.Block"
        style={"background-color: #{@bg_color}"}
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
              <.hidden_block_fields block_form={block_form} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={false}
                config={true}
                block={block_form}
                target={@target}
                palette={@palette}
                is_ref?={false}
                is_datasource?={false}
              />
              <.container_config uid={@uid} block={block_form} target={@target} palette={@palette} />
            </.inputs_for>
          <% else %>
            <div>IS THIS IT? IS IT SOMETHING ELSE? <%= inspect(@belongs_to, pretty: true) %></div>
          <% end %>
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
  attr :rendered_block, :string, default: ""
  attr :insert_block, :any, default: nil
  attr :insert_child_block, :any, default: nil
  attr :insert_multi_block, :any, default: nil
  attr :module_name, :string, default: nil
  attr :module_datasource_module_label, :string, default: ""
  attr :module_datasource_type, :string, default: ""
  attr :module_datasource_query, :string, default: ""
  attr :available_identifiers, :any, default: []

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
              <.hidden_block_fields block_form={block_form} />
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
                module_datasource_module_label={@module_datasource_module_label}
                module_datasource_type={@module_datasource_type}
                module_datasource_query={@module_datasource_query}
                available_identifiers={@available_identifiers}
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
                target={@target}
              />
            </.inputs_for>
          <% else %>
            <Input.hidden field={@form[:sequence]} />
            <.hidden_block_fields block_form={@form} />

            <.toolbar
              uid={@uid}
              collapsed={@collapsed}
              config={true}
              type={@type}
              block={@form}
              target={@target}
              is_ref?={false}
              is_datasource?={@is_datasource?}
              module_datasource_module_label={@module_datasource_module_label}
              module_datasource_type={@module_datasource_type}
              module_datasource_query={@module_datasource_query}
              available_identifiers={@available_identifiers}
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
              parent_uploads={@parent_uploads}
              target={@target}
            />
          <% end %>
        </.form>
        <%= if @has_children? do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <%= if @multi do %>
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
        <.vars vars={@block_form[:vars]} uid={@uid} />

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
      <Input.hidden field={@block_form[:palette_id]} />
      <Input.hidden field={@block_form[:creator_id]} />
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
          <.vars vars={@block_form[:vars]} uid={@uid} important={false} />
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
  attr :palette, :any, required: true
  attr :palette_options, :any, default: []
  attr :target, :any, required: true

  def container_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <%= if @palette_options do %>
            <div class="instructions mb-1"><%= gettext("Select a new palette") %>:</div>
            <.live_component
              module={Input.Select}
              id={"#{@block.id}-palette-select"}
              field={@block[:palette_id]}
              label={gettext("Palette")}
              opts={[options: @palette_options]}
              in_block
            />
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
    # find the ref in the refs
    ref_forms = Brando.Utils.forms_from_field(assigns.refs_field)

    ref_form =
      Enum.find(ref_forms, fn %{source: changeset} ->
        Changeset.get_field(changeset, :name) == assigns.ref_name
      end)

    assigns =
      assigns
      |> assign(:ref_form, ref_form)
      |> assign(:ref_forms, ref_forms)

    ~H"""
    <%= if @ref_form do %>
      <section b-ref={@ref_form[:name].value}>
        <.polymorphic_embed_inputs_for :let={block} field={@ref_form[:data]}>
          <.dynamic_block
            id={block[:uid].value}
            block_id={block[:uid].value}
            is_ref?={true}
            ref_name={@ref_form[:name].value}
            ref_description={@ref_form[:description].value}
            block={block}
            parent_uploads={@parent_uploads}
            target={@target}
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
          description={@description}
          is_ref?={@is_ref?}
          is_datasource?={false}
        >
          <:description>
            <%= @block_type %>
            <span :if={@block_type == "text"}>
              <%= gettext("Text") %> (<%= @block.source.data.data.type %>)
            </span>
            <span :if={@block_type == "heading"}>
              <%= gettext("Heading") %> (H<%= @block.source.data.data.level %>)
              <%= if @block.source.data.data.link do %>
                L
              <% end %>
              <%= if @block.source.data.data.id do %>
                #<%= @block.source.data.data.id %>
              <% end %>
            </span>
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
            <%= if @ref_description do %>
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
            <%= if @ref_description do %>
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
            <%= if @ref_description do %>
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
  attr :important, :boolean, default: true

  def vars(assigns) do
    changeset = assigns.vars.form.source

    vars_to_render =
      changeset
      |> Changeset.get_assoc(:vars)
      |> Enum.filter(&(Changeset.get_field(&1, :important) == assigns.important))

    assigns = assign(assigns, :vars_to_render, vars_to_render)

    ~H"""
    <div :if={@vars_to_render !== []} class="block-vars">
      <.inputs_for :let={var} field={@vars}>
        <.live_component
          module={RenderVar}
          id={"block-#{@uid}-render-var-#{@important && "important" || "regular"}-#{var.id}"}
          var={var}
          render={(@important && :only_important) || :only_regular}
          in_block
        />
      </.inputs_for>
    </div>
    """
  end

  attr :instructions, :string, default: nil
  attr :config, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :palette, :any, default: nil
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
          <span :if={@type == :module}>
            <%= gettext("Module") %> |
          </span>
          <span :if={@type == :module_entry}>
            <%= gettext("Entry") %> |
          </span>
          <span :if={@type == :container}>
            <%= gettext("Container") %> |
          </span>
          <span :if={@multi}>[multi] | </span>
        </span>
        <span :if={@description} class="block-name">
          <%= render_slot(@description) %>
        </span>
        <%= if @type == :container do %>
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
          <% end %>
          <span :if={@block[:description].value} class="description">
            &nbsp;<span class="arrow">&rarr;</span>&nbsp;<%= @block[:description].value %>
          </span>
        <% else %>
          <span :if={@block[:description].value} class="description">
            &nbsp;<span class="arrow">&rarr;</span>&nbsp;<%= @block[:description].value %>
          </span>
        <% end %>
      </div>
      <div :if={@is_datasource?} class="block-datasource" id={"block-#{@uid}-block-datasource"}>
        <.datasource
          block_data={@block}
          uid={@uid}
          module_datasource_module_label={@module_datasource_module_label}
          module_datasource_type={@module_datasource_type}
          module_datasource_query={@module_datasource_query}
          available_identifiers={@available_identifiers}
          block_identifiers={@block[:block_identifiers]}
          target={@target}
        />
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
        >
          <.icon name="hero-question-mark-circle" />
        </div>
        <button
          :if={@is_ref? == false}
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
          :if={@is_ref? == false}
          type="button"
          class="block-action toggler"
          phx-click="delete_block"
          phx-target={@target}
        >
          <.icon name="hero-trash" />
        </button>
        <Form.label field={@block[:collapsed]} class="block-action toggler">
          <.icon :if={@collapsed} name="hero-eye-slash" />
          <.icon :if={!@collapsed} name="hero-eye" />
          <Input.input type={:checkbox} field={@block[:collapsed]} />
        </Form.label>

        <div :if={!@is_ref?} class="dirty block-action toggler">●</div>
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
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
      <path fill="none" d="M0 0h24v24H0z" /><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z" />
    </svg>
    <%= @module_datasource_module_label %> [<%= @module_datasource_type %>] &raquo; <%= @module_datasource_query %>
    <%= if @module_datasource_type == :selection do %>
      <Content.modal
        title={gettext("Select entries")}
        id={"select-entries-#{@uid}"}
        remember_scroll_position
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
          phx-hook="Brando.SortableInputsFor"
          data-target={@target}
          data-sortable-id={"sortable-#{@uid}-identifiers"}
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".identifier"
        >
          <.inputs_for :let={block_identifier} field={@block_identifiers}>
            <Entries.block_identifier
              block_identifier={block_identifier}
              available_identifiers={@available_identifiers}
              sortable
            >
              <input
                type="hidden"
                name={"#{@block_identifiers.form.name}[sort_block_identifier_ids][]"}
                value={block_identifier.index}
              />
              <:delete>
                <label>
                  <input
                    type="checkbox"
                    name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"}
                    value={block_identifier.index}
                    class="hidden"
                  />
                  <.icon name="hero-x-mark" />
                </label>
              </:delete>
            </Entries.block_identifier>
          </.inputs_for>
          <input type="hidden" name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"} />
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
    """
  end

  ## Identifier events
  def handle_event("assign_available_identifiers", _, socket) do
    {:noreply, assign_available_identifiers(socket)}
  end

  def insert_identifier(available_identifiers, block_identifiers, identifier_id) do
    identifier = Enum.find(available_identifiers, &(&1.id == identifier_id))

    new_block_identifier =
      Changeset.change(%BlockIdentifier{
        identifier_id: identifier_id,
        identifier: identifier
      })

    block_identifiers ++ [new_block_identifier]
  end

  def remove_identifier(block_identifiers, identifier_id) do
    Enum.reject(
      block_identifiers,
      &(Changeset.get_field(&1, :identifier_id) == identifier_id)
    )
  end

  def handle_event("select_identifier", %{"id" => identifier_id}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid
    parent_id = socket.assigns.parent_id
    id = socket.assigns.id
    available_identifiers = socket.assigns.available_identifiers

    block_changeset = get_block_changeset(changeset, belongs_to)
    block_identifiers = Changeset.get_assoc(block_changeset, :block_identifiers)

    # does it have the identifier already?
    updated_block_identifiers =
      case Enum.find(
             block_identifiers,
             &(Changeset.get_field(&1, :identifier_id) == identifier_id)
           ) do
        nil ->
          # add it
          insert_identifier(available_identifiers, block_identifiers, identifier_id)

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

    # filter out any :replace actions
    # https://elixirforum.com/t/ecto-put-change-not-working-on-nested-changeset-when-updating/32681/2
    updated_block_identifiers = Enum.filter(updated_block_identifiers, &(&1.action != :replace))

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
          id: "child_block_form-#{parent_id}-#{id}"
        )
      end

    # # send form to parent
    # send_update(socket.assigns.parent_cid, %{event: "update_block", form: new_form, level: level})

    # {:noreply, socket}

    socket
    |> assign(:form, new_form)
    |> then(&{:noreply, &1})
  end

  def update_block_changeset(changeset, block_changeset, :root) do
    Changeset.put_assoc(changeset, :block, block_changeset)
  end

  def update_block_changeset(_changeset, block_changeset, _) do
    block_changeset
  end

  ## Block events
  def handle_event("collapse_block", _, socket) do
    {:noreply, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  # def handle_event("toggle_active", _, socket) do
  #   changeset = socket.assigns.form.source

  #   updated_changeset =
  #     EctoNestedChangeset.update_at(changeset, [:block, :active], &(!&1))

  #   updated_form =
  #     to_base_change_form(
  #       socket.assigns.block_module,
  #       updated_changeset,
  #       %{},
  #       socket.assigns.current_user_id
  #     )

  #   socket
  #   |> assign(:form, updated_form)
  #   |> assign(:active, !socket.assigns.active)
  #   |> then(&{:noreply, &1})
  # end

  def handle_event("fetch_missing_refs", _, socket) do
    user_id = socket.assigns.current_user_id
    form = socket.assigns.form
    changeset = form.source
    block_module = socket.assigns.block_module
    belongs_to = socket.assigns.belongs_to
    level = socket.assigns.level
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    parent_id = Changeset.get_field(changeset, :parent_id)
    id = Changeset.get_field(changeset, :id)
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
      if belongs_to == :root do
        to_form(updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(updated_changeset,
          as: "child_block",
          id: "child_block_form-#{parent_id}-#{id}"
        )
      end

    # send form to parent
    # send_update(socket.assigns.parent_cid, %{event: "update_block", form: new_form, level: level})

    # {:noreply, socket}

    {:noreply,
     socket
     |> assign(:form, new_form)}
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

  def handle_event("insert_block_entry", _, socket) do
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

    updated_form =
      if action == :insert and Changeset.changed?(updated_changeset, :block) do
        entry_block = Changeset.apply_changes(updated_changeset)
        to_base_change_form(block_module, entry_block, %{}, user_id, :insert)
      else
        updated_form
      end

    updated_changeset = updated_form.source

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

    form = socket.assigns.form
    changeset = form.source
    level = socket.assigns.level
    uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    parent_uid = socket.assigns.parent_uid
    block_module = socket.assigns.block_module
    entry = socket.assigns.entry

    block_cs = Changeset.get_assoc(changeset, :block)

    updated_form =
      to_base_change_form(
        block_module,
        changeset.data,
        params,
        socket.assigns.current_user_id,
        :validate
      )

    updated_changeset = updated_form.source
    updated_block_cs = Changeset.get_assoc(updated_changeset, :block)
    block = Changeset.apply_changes(updated_changeset)
    rendered_block = Brando.Villain.render_block(block, entry)

    # if we have var changes we must redo the liquid splits vars
    liquid_splits = socket.assigns.liquid_splits

    updated_liquid_splits =
      case Changeset.get_change(updated_block_cs, :vars) do
        nil -> liquid_splits
        vars -> update_liquid_splits_block_vars(liquid_splits, vars)
      end

    socket
    |> assign(:rendered_block, rendered_block)
    |> assign(:form, updated_form)
    |> assign(:form_has_changes, updated_form.source.changes !== %{})
    |> assign(:liquid_splits, updated_liquid_splits)
    |> then(&{:noreply, &1})
  end

  def update_liquid_splits_block_vars(liquid_splits, vars) do
    liquid_splits
    |> Enum.reduce([], fn
      {:variable, "entry." <> _, _} = entry_var, acc ->
        [entry_var | acc]

      {:variable, var_key, _prev_var_value}, acc ->
        [{:variable, var_key, liquid_render_block_variable(var_key, vars)} | acc]

      item, acc ->
        [item | acc]
    end)
    |> Enum.reverse()
  end

  # for forms that are on the base level, meaning
  # they are a join schema between an entry and a block
  defp to_base_change_form(block_module, entry_block_or_cs, params, user, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> block_module.changeset(params, user)
      |> Map.put(:action, action)

    block_cs = Changeset.get_assoc(changeset, :block)
    uid = Changeset.get_field(block_cs, :uid)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{uid}"
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
    # TODO: Give this another shake now that we have assocs
    # FIXME
    #
    # This is suboptimal at best. We preload all our image vars in the form, but when running
    # the polymorphic changesets, it clobbers the image's `value` - resetting it.
    #
    # Everything here will hopefully improve when we can update poly changesets instead
    # of replacing/inserting new every time.

    case Enum.find(vars, &(&1.key == var_name)) do
      %Brando.Content.Var{type: :image, image_id: nil} ->
        ""

      %Brando.Content.Var{type: :image, image: %Ecto.Association.NotLoaded{}, image_id: image_id} ->
        case Brando.Cache.get("var_image_#{image_id}") do
          nil ->
            image = Brando.Images.get_image!(image_id)
            media_path = Brando.Utils.media_url(image.path)
            Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
            media_path

          media_path ->
            media_path
        end

      %Brando.Content.Var{image: image, image_id: image_id} ->
        media_path = Brando.Utils.media_url(image.path)
        Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
        media_path

      %Brando.Images.Image{path: path} ->
        Brando.Utils.media_url(path)

      _ ->
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

  defp liquid_render_block_variable(var, vars) do
    case Enum.find(vars, &(Changeset.get_field(&1, :key) == var)) do
      nil -> var
      var_cs -> Changeset.get_field(var_cs, :value)
    end
  end

  def get_block_data_changeset(block) do
    Changeset.get_embed(block[:data].form.source, :data)
  end

  def get_block_changeset(changeset, :root), do: Changeset.get_assoc(changeset, :block)
  def get_block_changeset(changeset, _), do: changeset

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
