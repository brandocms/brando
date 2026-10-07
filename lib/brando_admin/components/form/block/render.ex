defmodule BrandoAdmin.Components.Form.Block.Render do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext
  import Phoenix.HTML
  import Phoenix.Component
  import Phoenix.LiveView, only: [send_update: 2]
  import Phoenix.LiveView.TagEngine
  import PolymorphicEmbed.HTML.Component

  alias Brando.AI
  alias Brando.Content.Var.Layout
  alias Brando.Content.VarAttrs
  alias Brando.Villain.Parser
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Entries
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Primitives
  alias Ecto.Changeset
  alias Phoenix.LiveView.JS

  def render(%{module_not_found: true} = assigns) do
    ~H"""
    <div>
      <.missing_target target={@myself}>
        {gettext("This block uses module #%{id}, which no longer exists.", id: @module_id)}
      </.missing_target>
    </div>
    """
  end

  # Without these two, a block referencing a deleted container/fragment falls
  # through to `render(%{type: :container})` / `render(%{type: :fragment})`,
  # which read `@container` / `@palette_options` / `@fragment`. Those are now
  # always assigned (see `Block.maybe_assign_container/1`), but rendering the
  # normal chrome for a target that no longer exists is still wrong — say so,
  # and offer the same escape hatch as `module_not_found`.
  def render(%{container_not_found: true} = assigns) do
    ~H"""
    <div>
      <.missing_target target={@myself}>
        {gettext("This block uses container #%{id}, which no longer exists.", id: @container_id)}
      </.missing_target>
    </div>
    """
  end

  def render(%{fragment_not_found: true} = assigns) do
    ~H"""
    <div>
      <.missing_target target={@myself}>
        {gettext("This block uses fragment #%{id}, which no longer exists.", id: @fragment_id)}
      </.missing_target>
    </div>
    """
  end

  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div data-module-multi="true">
      <.module
        form={@form}
        focus_role={@focus_role}
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
        module_color={@module_color}
        module_name={@module_name}
        module_type={@module_type}
        heex_compiled_module={@heex_compiled_module}
        block_module={@block_module}
        liquid_splits={@liquid_splits}
        target={@myself}
        target_ref={{Block, @id}}
        form_id={@form_id}
        entry={@entry}
        entry_language={@entry_language}
        insert_block={JS.push("insert_block", target: @myself)}
        insert_multi_block={JS.push("insert_block_entry", value: %{multi: true}, target: @myself)}
        insert_child_block={JS.push("insert_block", value: %{multi: true}, target: @myself)}
        module_picker_id={@module_picker_id}
        config_open={@config_open}
        has_children?={@has_children?}
        paste_multi_module_id={@paste_multi_module_id}
        hidden_block_fields={@hidden_block_fields}
      >
        <div
          :if={@has_children?}
          id={"#{@id}-children"}
          class="block-children"
          phx-hook="Brando.SortableBlocks"
          data-sortable-id={"sortable-blocks-multi-#{@uid}"}
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <div
            :for={
              {child_uid, child_block_form, list_index} <-
                Block.child_shells(@block_list, @children_forms) |> Block.focus_shells(@focus, @focus_role)
            }
            :key={child_uid}
            id={"child-#{child_block_form[:uid].value}"}
            data-id={child_block_form.data.id}
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            data-parent_uid={@uid}
          >
            <.live_component
              module={Block}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              dom_id={"child-#{child_block_form[:uid].value}"}
              list_index={list_index}
              multi={child_block_form[:multi].value}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              live_preview_active?={@live_preview_active?}
              live_preview_cache_key={@live_preview_cache_key}
              parent_ref={{Block, @id}}
              parent_uid={@uid}
              parent_path={@path}
              parent_module_id={@module_id}
              parent_module_origin={@module_origin}
              module_set={@module_set}
              form={child_block_form}
              form_id={@form_id}
              entry={@entry}
              current_user_id={@current_user_id}
              belongs_to={:multi}
              paste_multi_module_id={@paste_multi_module_id}
              level={@level + 1}
              focus={Block.child_focus(@focus, @focus_role)}
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
        focus_role={@focus_role}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        target={@myself}
        target_ref={{Block, @id}}
        form_id={@form_id}
        module_class={@module_class}
        module_type={@module_type}
        heex_compiled_module={@heex_compiled_module}
        block_module={@block_module}
        liquid_splits={@liquid_splits}
        entry={@entry}
        entry_language={@entry_language}
        insert_block={JS.push("insert_block", target: @myself)}
        module_picker_id={@module_picker_id}
        config_open={@config_open}
        has_children?={false}
        module_name={@module_name}
        module_color={@module_color}
        module_datasource_module_label={@module_datasource_module_label}
        module_datasource_type={@module_datasource_type}
        module_datasource_query={@module_datasource_query}
        datasource_meta={@datasource_meta}
        available_identifiers={@available_identifiers}
        datasource_preview={@datasource_preview}
        paste_multi_module_id={@paste_multi_module_id}
        hidden_block_fields={@hidden_block_fields}
        paste_context={
          case @belongs_to do
            :container -> :container
            :slot -> nil
            _ -> :root
          end
        }
      />
      <.unused_collections
        id={"unused-collections-#{@uid}"}
        items={@unused_collections}
        target={@myself}
        remap_uid={@remap_slot_uid}
        remap_targets={@remap_targets}
        remap_error={@remap_error}
      />
      {collection_children(assigns)}
    </div>
    """
  end

  def render(%{type: :module_entry} = assigns) do
    ~H"""
    <div>
      <.module
        form={@form}
        focus_role={@focus_role}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        target={@myself}
        target_ref={{Block, @id}}
        form_id={@form_id}
        module_class={@module_class}
        module_type={@module_type}
        heex_compiled_module={@heex_compiled_module}
        block_module={@block_module}
        liquid_splits={@liquid_splits}
        entry={@entry}
        entry_language={@entry_language}
        insert_block={JS.push("insert_block_entry", target: @myself)}
        module_picker_id={@module_picker_id}
        config_open={@config_open}
        has_children?={false}
        module_name={@module_name}
        module_color={@module_color}
        paste_multi_module_id={@paste_multi_module_id}
        hidden_block_fields={@hidden_block_fields}
        paste_context={multi_paste_context(@paste_multi_module_id, @parent_module_id)}
      />
    </div>
    """
  end

  def render(%{type: :container} = assigns) do
    ~H"""
    <div>
      <.container
        form={@form}
        focus_role={@focus_role}
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
        module_picker_id={@module_picker_id}
        config_open={@config_open}
        has_children?={@has_children?}
        paste_multi_module_id={@paste_multi_module_id}
        hidden_block_fields={@hidden_block_fields}
      >
        <div
          :if={@has_children?}
          id={"#{@id}-children"}
          class="block-children"
          phx-hook="Brando.SortableBlocks"
          data-sortable-id="sortable-blocks"
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <div
            :for={
              {child_uid, child_block_form, list_index} <-
                Block.child_shells(@block_list, @children_forms) |> Block.focus_shells(@focus, @focus_role)
            }
            :key={child_uid}
            id={"child-#{child_block_form[:uid].value}"}
            data-id={child_block_form[:id].value}
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            data-parent_uid={@uid}
            class="draggable"
          >
            <.live_component
              module={Block}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              dom_id={"child-#{child_block_form[:uid].value}"}
              list_index={list_index}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              live_preview_active?={@live_preview_active?}
              live_preview_cache_key={@live_preview_cache_key}
              parent_ref={{Block, @id}}
              parent_uid={@uid}
              parent_path={@path}
              module_set={@module_set}
              entry={@entry}
              form={child_block_form}
              form_id={@form_id}
              current_user_id={@current_user_id}
              belongs_to={:container}
              paste_multi_module_id={@paste_multi_module_id}
              level={@level + 1}
              focus={Block.child_focus(@focus, @focus_role)}
            >
            </.live_component>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  def render(%{type: :slot} = assigns) do
    ~H"""
    <div id={"slot-#{@uid}"} data-block-slot={@uid} data-slot-kind={@slot_kind}>
      <%!-- Every block keeps its own form. Closed drawers stay mounted so
            LiveView recovery and the owner op store retain their drafts. --%>
      <.form for={@form} phx-change="validate_block" phx-target={@myself} hidden>
        <Input.hidden field={@form[:id]} />
        <Input.hidden :if={@belongs_to == :root} field={@form[:sequence]} />
        <Input.hidden :if={@belongs_to == :root} field={@form[:marked_as_deleted]} />
        <.hidden_block_fields fields={@hidden_block_fields} />
      </.form>
      <section
        id={"block-slot-drawer-#{@uid}"}
        class={["block-slot-drawer", @slot_open && "visible"]}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"block-slot-title-#{@uid}"}
        phx-hook="Brando.BlockSlot"
        phx-target={@myself}
      >
        <button
          class="block-slot-backdrop"
          type="button"
          tabindex="-1"
          phx-click="close_block_slot"
          phx-target={@myself}
          aria-label={gettext("Close collection")}
        />
        <div class="block-slot-panel">
          <header class="block-slot-header">
            <div>
              <p class="block-slot-breadcrumb">
                {if @slot_kind == :footnote, do: gettext("Text / Footnotes"), else: gettext("Content / Block region")}
              </p>
              <h2 id={"block-slot-title-#{@uid}"}>{@slot_title || @slot_name}</h2>
            </div>
            <button type="button" class="block-slot-done" phx-click="close_block_slot" phx-target={@myself}>{gettext("Done")}</button>
          </header>
          <div class="block-slot-meta">
            <span>{ngettext("%{count} block", "%{count} blocks", length(@block_list))}</span>
            <span class="block-slot-set">{@slot_module_set}</span>
          </div>
          <div class="block-slot-content">
            <div :if={@block_list == []} class="block-slot-empty">
              <.icon name="layout-grid" />
              <h3>{gettext("Make room for more")}</h3>
              <p>{gettext("Add text, a source or supporting media from this collection’s module set.")}</p>
            </div>
            <div
              id={"#{@id}-children"}
              phx-hook="Brando.SortableBlocks"
              data-sortable-id={"sortable-slot-#{@uid}"}
              data-sortable-handle=".sort-handle"
              data-sortable-selector=".block"
              class="block-slot-blocks"
            >
              {collection_children(assigns)}
            </div>
            <.plus click={JS.push("insert_slot_block", target: @myself)} modal={@module_picker_id} />
          </div>
          <footer class="block-slot-footer">
            <.icon name="file-check" /><span>{gettext("Changes are saved with this entry.")}</span>
          </footer>
        </div>
      </section>
    </div>
    """
  end

  def render(%{type: :fragment} = assigns) do
    ~H"""
    <div>
      <.fragment_block
        form={@form}
        focus_role={@focus_role}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        fragment={@fragment}
        fragments={@fragments}
        belongs_to={@belongs_to}
        insert_block={JS.push("insert_block", target: @myself)}
        module_picker_id={@module_picker_id}
        config_open={@config_open}
        deleted={@deleted}
        target={@myself}
        block_module={@block_module}
        paste_multi_module_id={@paste_multi_module_id}
        hidden_block_fields={@hidden_block_fields}
      />
    </div>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :assign_keys, Map.keys(assigns))

    ~H"""
    <div class="block-unknown-type">
      <code>
        <pre>
      ERROR: Unknown block type

      Assign keys:

      <%= inspect @assign_keys, pretty: true, width: 0 %>

      - type: <%= inspect @type %>
      - multi: <%= inspect @multi %>
      </pre>
      </code>
    </div>
    """
  end

  ##
  ## Function components

  def collection_children(assigns) do
    ~H"""
    <div
      :for={
        {child_uid, child_form, list_index} <-
          Block.child_shells(@block_list, @children_forms) |> Block.focus_shells(@focus, @focus_role)
      }
      :key={child_uid}
      id={"child-#{child_uid}"}
      data-uid={child_uid}
      data-parent_uid={@uid}
      data-parent_id={child_form[:parent_id].value}
      data-id={child_form[:id].value}
    >
      <.live_component
        module={Block}
        id={"#{@id}-child-#{child_uid}"}
        dom_id={"child-#{child_uid}"}
        list_index={list_index}
        block_module={@block_module}
        block_field={@block_field}
        children={child_form[:children].value}
        live_preview_active?={@live_preview_active?}
        live_preview_cache_key={@live_preview_cache_key}
        parent_ref={{Block, @id}}
        parent_uid={@uid}
        parent_path={@path}
        module_set={if @type == :slot, do: @slot_module_set, else: @module_set}
        form={child_form}
        form_id={@form_id}
        entry={@entry}
        current_user_id={@current_user_id}
        belongs_to={:slot}
        slot_open={@open_slot_uid == child_uid}
        slot_title={@slot_title}
        paste_multi_module_id={@paste_multi_module_id}
        level={@level + 1}
        focus={Block.child_focus(@focus, @focus_role)}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :items, :list, required: true
  attr :target, :any, required: true
  attr :remap_uid, :string, default: nil
  attr :remap_targets, :list, default: []
  attr :remap_error, :string, default: nil

  def unused_collections(assigns) do
    ~H"""
    <section :if={@items != []} id={@id} class="unused-collections" aria-labelledby={"#{@id}-title"}>
      <h3 id={"#{@id}-title"}>{gettext("Unused content")} <span>{length(@items)}</span></h3>
      <p>{gettext("This content is kept here, but no longer has a region or a reference in the text.")}</p>
      <ul>
        <li :for={item <- @items} data-unused-uid={item.uid}>
          <span class="unused-collection-label">
            <strong>{item.label}</strong>
            <span>{if item.kind == :region, do: gettext("Unmatched region"), else: gettext("Unreferenced footnote")}</span>
          </span>
          <div class="unused-collection-actions">
            <button type="button" phx-click="open_unused_collection" phx-value-uid={item.uid} phx-target={@target}>{gettext(
              "Open"
            )}</button>
            <button
              :if={item.kind == :region}
              type="button"
              phx-click="choose_region_remap"
              phx-value-uid={item.uid}
              phx-target={@target}
            >{gettext("Remap")}</button>
            <button
              :if={item.restore?}
              type="button"
              phx-click="restore_note_reference"
              phx-value-uid={item.uid}
              phx-target={@target}
            >{gettext("Restore reference")}</button>
            <button type="button" phx-click="delete_unused_collection" phx-value-uid={item.uid} phx-target={@target}>{gettext(
              "Delete"
            )}</button>
          </div>
        </li>
      </ul>
      <.form
        :if={@remap_uid}
        for={%{}}
        id={"#{@id}-remap"}
        phx-submit="remap_region"
        phx-target={@target}
        class="region-remap-form"
      >
        <input type="hidden" name="uid" value={@remap_uid} />
        <label for={"#{@id}-destination"}>{gettext("Move this content to an empty region")}</label>
        <select :if={@remap_targets != []} id={"#{@id}-destination"} name="name" required>
          <option :for={{label, name} <- @remap_targets} value={name}>{label} ({name})</option>
        </select>
        <p :if={@remap_targets == []}>{gettext("There are no empty compatible regions on this block.")}</p>
        <p :if={@remap_error} role="alert">{@remap_error}</p>
        <button :if={@remap_targets != []} type="submit">{gettext("Remap region")}</button>
        <button type="button" phx-click="cancel_region_remap" phx-target={@target}>{gettext("Cancel")}</button>
      </.form>
    </section>
    """
  end

  attr :form, :any
  attr :dirty, :any
  attr :new, :any
  attr :level, :any
  attr :belongs_to, :any
  attr :deleted, :any
  attr :target, :any
  attr :block_module, :any
  attr :insert_block, :any
  attr :module_picker_id, :string, default: nil
  attr :config_open, :string, default: nil
  attr :fragment, :any, default: nil
  attr :fragments, :list, default: []
  attr :paste_multi_module_id, :any, default: nil
  attr :hidden_block_fields, :list, default: []
  attr :focus_role, :atom, default: nil

  def fragment_block(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = Block.get_block_changeset(changeset, belongs_to)
    fragment_id = Changeset.get_field(block_cs, :fragment_id)

    assigns =
      assign_derived(assigns, [:form, :belongs_to],
        uid: Changeset.get_field(block_cs, :uid),
        type: Changeset.get_field(block_cs, :type),
        fragment_id: fragment_id,
        active: Changeset.get_field(block_cs, :active),
        collapsed: Changeset.get_field(block_cs, :collapsed),
        update_url: fragment_id && Brando.Pages.Fragment.__admin_route__(:update, [fragment_id])
      )

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && @focus_role != :target && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty",
        @focus_role && "focus-#{@focus_role}"
      ]}
    >
      <.plus
        click={@insert_block}
        modal={@module_picker_id}
        paste_context={:root}
        paste_event="paste_block"
        paste_target={@target}
      />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-fragment-id={@fragment_id}
        class={["block"]}
        phx-hook="Brando.Block"
      >
        <.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields fields={@hidden_block_fields} />
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
                    [{@fragment.parent_key}/<strong><%= @fragment.key %></strong>] {@fragment.title} — {@fragment.language}
                  <% end %>
                </:description>
              </.toolbar>
              <.fragment_config
                uid={@uid}
                block={block_form}
                target={@target}
                fragment={@fragment}
                fragments={@fragments}
                open={@config_open == @uid}
              />
              <div class="block-content">
                <div class="block-fragment-wrapper">
                  <div class="fragment-info" phx-click="show_fragment_instructions" phx-target={@target}>
                    <div class="icon">
                      <.icon name="puzzle" />
                    </div>
                    <div class="info">
                      <span class="fragment-label">
                        {gettext("Embedded")}<br /> {gettext("fragment")}
                      </span>
                    </div>
                  </div>

                  <div :if={!@fragment_id} class="block-instructions">
                    <p>
                      {gettext("This block embeds a fragment as a block, but no fragment is currently selected.")}
                    </p>
                    <button type="button" class="tiny" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
                      {gettext("Add fragment")}
                    </button>
                  </div>
                  <div :if={@fragment} class="fragment-info">
                    <.link :if={@update_url} class="tiny button" href={@update_url} target="_blank">
                      {gettext("Edit fragment")}
                    </.link>
                  </div>
                </div>
              </div>
            </.inputs_for>
          <% else %>
            <section class="alert danger">
              {gettext("This block is currently not allowed to be a child block :(")}
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

    block_cs = Block.get_block_changeset(changeset, belongs_to)
    palette = Changeset.get_assoc(block_cs, :palette, :struct)
    bg_color = extract_block_bg_color(palette)

    assigns =
      assign_derived(assigns, [:form, :belongs_to],
        uid: Changeset.get_field(block_cs, :uid),
        type: Changeset.get_field(block_cs, :type),
        container_id: Changeset.get_field(block_cs, :container_id),
        description: Changeset.get_field(block_cs, :description),
        active: Changeset.get_field(block_cs, :active),
        collapsed: Changeset.get_field(block_cs, :collapsed),
        palette: palette,
        bg_color: bg_color
      )

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && @focus_role != :target && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty",
        @focus_role && "focus-#{@focus_role}"
      ]}
    >
      <.plus
        click={@insert_block}
        modal={@module_picker_id}
        paste_context={:root}
        paste_event="paste_block"
        paste_target={@target}
      />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-container-id={@container_id}
        class="block"
        phx-hook="Brando.Block"
        style={"background-color: #{@bg_color}"}
      >
        <.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields fields={@hidden_block_fields} />
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
                open={@config_open == @uid}
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
              {gettext("This block is currently not allowed to be a child block :(")}
            </section>
          <% end %>
        </.form>
        <%= if @has_children? do %>
          {render_slot(@inner_block)}
          <.plus
            click={@insert_child_block}
            modal={@module_picker_id}
            paste_context={:container}
            paste_event="paste_child_block"
            paste_target={@target}
          />
        <% else %>
          <div class="blocks-empty-instructions">
            {gettext("Click the plus to start adding content blocks")}
          </div>
          <.plus
            click={@insert_child_block}
            modal={@module_picker_id}
            paste_context={:container}
            paste_event="paste_child_block"
            paste_target={@target}
          />
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
  attr :target, :any
  attr :target_ref, :any, default: nil
  attr :has_children?, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :liquid_splits, :any, default: []
  attr :insert_block, :any, default: nil
  attr :insert_child_block, :any, default: nil
  attr :insert_multi_block, :any, default: nil
  attr :module_picker_id, :string, default: nil
  attr :config_open, :string, default: nil
  attr :module_name, :string, default: nil
  attr :module_color, :string, default: nil
  attr :module_datasource_module_label, :string, default: ""
  attr :module_datasource_type, :string, default: ""
  attr :module_datasource_query, :string, default: ""
  attr :datasource_meta, :any, default: nil
  attr :available_identifiers, :any, default: []
  attr :datasource_preview, :map, default: nil
  attr :paste_multi_module_id, :any, default: nil
  attr :paste_context, :any, default: :root
  attr :form_id, :any, default: nil
  attr :module_type, :atom, default: :liquid
  attr :heex_compiled_module, :any, default: nil
  attr :entry, :any, default: nil
  attr :entry_language, :string, default: nil
  attr :hidden_block_fields, :list, default: []
  attr :focus_role, :atom, default: nil
  slot :inner_block

  def module(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = Block.get_block_changeset(changeset, belongs_to)

    assigns =
      assigns
      |> assign_derived([:form, :belongs_to],
        uid: Changeset.get_field(block_cs, :uid),
        type: Changeset.get_field(block_cs, :type),
        module_id: Changeset.get_field(block_cs, :module_id),
        description: Changeset.get_field(block_cs, :description),
        active: Changeset.get_field(block_cs, :active),
        collapsed: Changeset.get_field(block_cs, :collapsed),
        block_form: belongs_to == :root && nested_block_form(assigns.form)
      )
      |> assign_new(:heex_compiled_module, fn -> nil end)

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && @focus_role != :target && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty",
        @focus_role && "focus-#{@focus_role}"
      ]}
    >
      <.plus
        click={@insert_block}
        modal={@module_picker_id}
        paste_context={@paste_context}
        paste_event="paste_block"
        paste_target={@target}
      />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-module-id={@module_id}
        data-color={@module_color}
        class="block"
        phx-hook="Brando.Block"
      >
        <%!-- A plain form with the attributes `<.form>` gives it. The component
              rebuilds its attributes whenever anything inside it changes, so
              every entry-field update re-sent them for each consuming block. --%>
        <form
          id={@form.id}
          method={@form.options[:method]}
          phx-value-id={@form.data.id}
          phx-change="validate_block"
          phx-target={@target}
        >
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <input :for={{name, value} <- hidden_inputs(@block_form)} type="hidden" name={name} value={value} />
            <.hidden_block_fields fields={@hidden_block_fields} />
            <.toolbar
              uid={@uid}
              collapsed={@collapsed}
              type={@type}
              multi={@multi}
              config={true}
              block={@block_form}
              target={@target}
              is_ref?={false}
              is_datasource?={@is_datasource?}
              has_children?={@has_children?}
            >
              <:description>
                <.i18n map={@module_name} />
              </:description>
            </.toolbar>

            <.module_config
              open={@config_open == @uid}
              uid={@uid}
              block_form={@block_form}
              target={@target}
              form_id={@form_id}
              language={@entry_language}
            />
            <.module_content
              config_open={@config_open}
              uid={@uid}
              block_form={@block_form}
              liquid_splits={@liquid_splits}
              module_class={@module_class}
              module_type={@module_type}
              heex_compiled_module={@heex_compiled_module}
              has_table_template?={@has_table_template?}
              table_template_name={@table_template_name}
              target={@target}
              target_ref={@target_ref}
              form_id={@form_id}
              is_datasource?={@is_datasource?}
              datasource_meta={@datasource_meta}
              module_datasource_module_label={@module_datasource_module_label}
              module_datasource_type={@module_datasource_type}
              module_datasource_query={@module_datasource_query}
              available_identifiers={@available_identifiers}
              datasource_preview={@datasource_preview}
              block_identifiers={@block_form[:block_identifiers]}
              entry={@entry}
              entry_language={@entry_language}
            />
          <% else %>
            <Input.hidden field={@form[:sequence]} />
            <input type="hidden" name={@form[:id].name} value={@form[:id].value} />
            <.hidden_block_fields fields={@hidden_block_fields} />

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
                <.i18n map={@module_name} />
              </:description>
            </.toolbar>

            <.module_config
              open={@config_open == @uid}
              uid={@uid}
              block_form={@form}
              target={@target}
              form_id={@form_id}
              language={@entry_language}
            />
            <.module_content
              config_open={@config_open}
              uid={@uid}
              block_form={@form}
              liquid_splits={@liquid_splits}
              module_class={@module_class}
              module_type={@module_type}
              heex_compiled_module={@heex_compiled_module}
              has_table_template?={@has_table_template?}
              table_template_name={@table_template_name}
              target={@target}
              target_ref={@target_ref}
              form_id={@form_id}
              is_datasource?={@is_datasource?}
              datasource_meta={@datasource_meta}
              module_datasource_module_label={@module_datasource_module_label}
              module_datasource_type={@module_datasource_type}
              module_datasource_query={@module_datasource_query}
              available_identifiers={@available_identifiers}
              datasource_preview={@datasource_preview}
              block_identifiers={@form[:block_identifiers]}
              entry={@entry}
              entry_language={@entry_language}
            />
          <% end %>
        </form>
        <%= if @has_children? do %>
          {render_slot(@inner_block)}
          <.plus
            click={@insert_multi_block}
            modal={@module_picker_id}
            paste_context={multi_paste_context(@paste_multi_module_id, @module_id)}
            paste_event="paste_child_block"
            paste_target={@target}
          />
        <% else %>
          <%= if @multi do %>
            <div class="blocks-empty-instructions">
              {gettext("Click the plus to start adding content blocks")}
            </div>
            <.plus
              click={@insert_multi_block}
              modal={@module_picker_id}
              paste_context={multi_paste_context(@paste_multi_module_id, @module_id)}
              paste_event="paste_child_block"
              paste_target={@target}
            />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def module_content(%{module_type: :heex} = assigns) do
    heex_assigns = build_heex_admin_assigns(assigns)

    heex_render_fn =
      assigns.heex_compiled_module && Function.capture(assigns.heex_compiled_module, :render, 1)

    assigns =
      assigns
      |> assign(:heex_assigns, heex_assigns)
      |> assign(:heex_render_fn, heex_render_fn)
      |> assign_new(:entry_language, fn -> nil end)

    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars
          vars={@block_form[:vars]}
          uid={@uid}
          target={@target}
          form_id={@form_id}
          current_user_id={@block_form[:creator_id].value}
          language={@entry_language}
        />
        <.datasource
          :if={@is_datasource?}
          block_data={@block_form}
          uid={@uid}
          datasource_meta={@datasource_meta}
          module_datasource_module_label={@module_datasource_module_label}
          module_datasource_type={@module_datasource_type}
          module_datasource_query={@module_datasource_query}
          available_identifiers={@available_identifiers}
          datasource_preview={@datasource_preview}
          block_identifiers={@block_identifiers}
          target={@target}
        />
        <div :if={@has_table_template?} class="block-table" id={"block-#{@uid}-block-table"}>
          <.table
            block_data={@block_form}
            uid={@uid}
            target={@target}
            table_template_name={@table_template_name}
            form_id={@form_id}
          />
        </div>
        <div class="block-heex-preview">
          <%= if @heex_render_fn do %>
            {Phoenix.LiveView.TagEngine.component(
              @heex_render_fn,
              @heex_assigns,
              {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
            )}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def module_content(assigns) do
    # On a malformed template, render the actual ref controls without template
    # HTML. Resolve from the current form so newly added, unsaved refs retain
    # their inputs too; identity-only carried_refs cannot preserve their data.
    liquid_splits =
      case assigns.liquid_splits do
        [{:liquid_error, _reason} = error] ->
          refs = Changeset.get_assoc(assigns.block_form.source, :refs, :struct)
          [error | Enum.map(refs, &{:ref, &1.name})]

        splits ->
          splits
      end

    assigns =
      assigns
      |> assign_derived([:block_form], footnote_refs: footnote_ref_names(assigns.block_form.source))
      |> assign(:liquid_splits, liquid_splits)
      |> assign_new(:entry_language, fn -> nil end)

    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars
          vars={@block_form[:vars]}
          uid={@uid}
          target={@target}
          form_id={@form_id}
          current_user_id={@block_form[:creator_id].value}
          language={@entry_language}
        />
        <.datasource
          :if={@is_datasource?}
          block_data={@block_form}
          uid={@uid}
          datasource_meta={@datasource_meta}
          module_datasource_module_label={@module_datasource_module_label}
          module_datasource_type={@module_datasource_type}
          module_datasource_query={@module_datasource_query}
          available_identifiers={@available_identifiers}
          datasource_preview={@datasource_preview}
          block_identifiers={@block_identifiers}
          target={@target}
        />
        <div :if={@has_table_template?} class="block-table" id={"block-#{@uid}-block-table"}>
          <.table
            block_data={@block_form}
            uid={@uid}
            target={@target}
            table_template_name={@table_template_name}
            form_id={@form_id}
          />
        </div>
        <div :if={@liquid_splits != []} class="block-liquex-preview">
          <%= for split <- @liquid_splits do %>
            <%= case split do %>
              <% {:liquid_error, _reason} -> %>
                <div class="alert danger" role="alert">
                  {gettext(
                    "The module preview is unavailable because its Liquid tags are incomplete or mismatched. Check the module template. You can still edit the fields below."
                  )}
                </div>
              <% {:ref, ref} -> %>
                <.ref
                  refs_field={@block_form[:refs]}
                  ref_name={ref}
                  footnotes_enabled={ref in @footnote_refs}
                  config_open={@config_open}
                  target={@target}
                  target_ref={@target_ref}
                  form_id={@form_id}
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
                {raw(split)}
            <% end %>
          <% end %>
          <.carried_refs refs_field={@block_form[:refs]} liquid_splits={@liquid_splits} />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The block's identity inputs.

  Rendered from a precomputed `{name, id, value}` list rather than from the
  block form, because the root path renders inside `<.inputs_for>` and a
  comprehension entry re-renders every dynamic that depends on one of its own
  vars — and `block_form` is a fresh struct on every validate. Reading a
  single tracked assign instead keeps these out of the diff on any edit that
  does not change them. See `Block.assign_hidden_block_fields/1`.
  """
  attr :fields, :list, required: true

  def hidden_block_fields(assigns) do
    ~H"""
    <div class="hidden-block-fields">
      <input :for={{name, id, value} <- @fields} type="hidden" name={name} id={id} value={value} />
    </div>
    """
  end

  attr :uid, :string, required: true
  attr :block_form, :any, required: true
  attr :target, :any, required: true
  attr :form_id, :any, default: nil
  attr :open, :boolean, default: false
  attr :language, :string, default: nil

  @doc """
  The block's configure surface.

  Rendered eagerly this was 115 full modal subtrees nobody had opened. The
  chrome — panels, labels, buttons, and the `RenderVar` live_components — now
  renders only while open.

  What cannot be deferred is the *params surface*. This modal sits inside
  `<.form phx-change="validate_block">`, so its inputs are submitted on every
  validate; drop them wholesale and the `cast_assoc(:vars)` list shortens and
  Ecto **deletes** the config-placement and `:hidden` vars — the hazard already
  documented at `vars/1` and in the `vars/1` moduledoc. Block recovery reads DOM
  `FormData` too (`assets/src/hooks/BlockField/index.js`), so an absent input is
  also an unsaved value lost on reconnect.

  So while closed the var inputs are still rendered in full, just inside a
  hidden container. Reducing them to identity-only hidden inputs — the obvious
  saving, and what `carried_var/1` does for `:hidden` vars — is **not** safe
  here: `cast_assoc` matches params to existing records by primary key, so an
  unsaved var has nothing to match on and Ecto rebuilds it from the params
  alone, blanking `key`, `placement` and every other field. Blocks are created
  with unsaved vars, so that is the common case, not an edge one.

  `description` is a plain field on the block rather than an assoc, so a hidden
  input does carry it safely — `cast` leaves fields the params don't mention
  alone.

  > #### Known gap {: .warning}
  >
  > `:hidden` vars still round-trip through `carried_var/1` and so still get
  > blanked on an unsaved block. That predates this split and is unchanged by
  > it; fixing it needs identity that survives before the first save.
  """
  def module_config(assigns) do
    ~H"""
    <div :if={!@open} class="block-config-carried" hidden>
      <input type="hidden" name={@block_form[:description].name} value={@block_form[:description].value} />
      <.vars
        vars={@block_form[:vars]}
        uid={@uid}
        placement={:config}
        carry_persisted
        target={@target}
        form_id={@form_id}
        current_user_id={@block_form[:creator_id].value}
        language={@language}
      />
    </div>
    <Content.modal
      :if={@open}
      title={gettext("Configure block")}
      subtitle={@block_form[:description].value}
      icon="layout-grid"
      layout="editor"
      id={"block-#{@uid}_config"}
      show={true}
      close={JS.push("close_block_config", target: @target)}
      wide={true}
    >
      <Content.modal_sections id={"block-#{@uid}-config-sections"}>
        <:section id="settings" label={gettext("Settings")} icon="sliders-horizontal">
          <h3 class="modal-section-title">{gettext("Block settings")}</h3>
          <Input.text
            field={@block_form[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
          <Input.text field={@block_form[:anchor]} instructions={gettext("Anchor available to block.")} />
          <.vars
            vars={@block_form[:vars]}
            uid={@uid}
            placement={:config}
            target={@target}
            form_id={@form_id}
            current_user_id={@block_form[:creator_id].value}
            language={@language}
          />
          <div class="modal-technical-note">
            UID: <span class="text-mono">{@uid}</span>
          </div>
        </:section>
        <:section id="variables" label={gettext("Variables")} icon="code">
          <h3 class="modal-section-title">{gettext("Variables")}</h3>
          <div class="modal-maintenance-list">
            <.inputs_for :let={var} field={@block_form[:vars]}>
              <div class="var">
                <div class="key">{var[:key].value}</div>
                <div class="buttons">
                  <button
                    type="button"
                    class="tiny"
                    phx-click={JS.push("reset_var", target: @target)}
                    phx-value-id={var[:key].value}
                  >
                    {gettext("Reset")}
                  </button>
                  <button
                    type="button"
                    class="tiny"
                    phx-click={JS.push("delete_var", target: @target)}
                    phx-value-id={var[:key].value}
                  >
                    {gettext("Delete")}
                  </button>
                </div>
              </div>
            </.inputs_for>
          </div>
        </:section>
        <:section id="references" label={gettext("References")} icon="layout-grid">
          <h3 class="modal-section-title">{gettext("References")}</h3>
          <div class="modal-maintenance-list">
            <.inputs_for :let={ref} field={@block_form[:refs]}>
              <div class="ref">
                <div class="key">{ref[:name].value}</div>
                <button
                  type="button"
                  class="tiny"
                  phx-click={JS.push("reset_ref", target: @target)}
                  phx-value-id={ref[:name].value}
                >
                  {gettext("Reset")}
                </button>
              </div>
            </.inputs_for>
          </div>
        </:section>
        <:section id="advanced" label={gettext("Advanced")} icon="settings">
          <h3 class="modal-section-title">{gettext("Advanced")}</h3>
          <div class="button-group-vertical">
            <button type="button" class="secondary" phx-click={JS.push("fetch_missing_refs", target: @target)}>
              {gettext("Fetch missing refs")}
            </button>
            <button type="button" class="secondary" phx-click={JS.push("reset_refs", target: @target)}>
              {gettext("Reset all block refs")}
            </button>
            <button type="button" class="secondary" phx-click={JS.push("fetch_missing_vars", target: @target)}>
              {gettext("Fetch missing vars")}
            </button>
            <button type="button" class="secondary" phx-click={JS.push("reset_vars", target: @target)}>
              {gettext("Reset all variables")}
            </button>
            <a
              href={"/admin/config/content/modules/update/#{@block_form[:module_id].value}"}
              class="secondary"
              target="_blank"
            >
              {gettext("Edit module")}
            </a>
          </div>
        </:section>
      </Content.modal_sections>
      <:footer>
        <span class="modal-footer-note">{gettext("Saved with the page")}</span>
        <button type="button" class="primary" phx-click="close_block_config" phx-target={@target}>
          {gettext("Done")}
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
  attr :open, :boolean, default: false

  def fragment_config(assigns) do
    ~H"""
    <div :if={!@open} class="block-config-carried" hidden>
      <input type="hidden" name={@block[:fragment_id].name} value={@block[:fragment_id].value} />
      <input type="hidden" name={@block[:description].name} value={@block[:description].value} />
    </div>
    <Content.modal
      :if={@open}
      title={gettext("Configure")}
      id={"block-#{@uid}_config"}
      show={true}
      close={JS.push("close_block_config", target: @target)}
      wide={true}
    >
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
        <button type="button" class="primary" phx-click="close_block_config" phx-target={@target}>
          {gettext("Close")}
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
  # `nil` means "no palette select" — see the branch at `:1173`. Defaulting to
  # `[]` would be truthy and render an empty `<select>`.
  attr :palette_options, :any, default: nil
  attr :target, :any, required: true
  attr :open, :boolean, default: false

  def container_config(assigns) do
    ~H"""
    <div :if={!@open} class="block-config-carried" hidden>
      <input type="hidden" name={@block[:container_id].name} value={@block[:container_id].value} />
      <input type="hidden" name={@block[:palette_id].name} value={@block[:palette_id].value} />
      <input type="hidden" name={@block[:description].name} value={@block[:description].value} />
    </div>
    <Content.modal
      :if={@open}
      title={gettext("Configure")}
      id={"block-#{@uid}_config"}
      show={true}
      close={JS.push("close_block_config", target: @target)}
      wide={true}
    >
      <div class="panels">
        <div class="panel">
          <.live_component
            module={Input.Select}
            id={"#{@block.id}-container-select"}
            field={@block[:container_id]}
            origin_field={@block[:container_origin]}
            label={gettext("Container template")}
            opts={[options: @containers, resetable: true]}
            publish
          />
          <%= if @palette_options do %>
            <.live_component
              module={Input.Select}
              id={"#{@block.id}-palette-select"}
              field={@block[:palette_id]}
              origin_field={@block[:palette_origin]}
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
        <button type="button" class="primary" phx-click="close_block_config" phx-target={@target}>
          {gettext("Close")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :refs_field, :any, required: true
  attr :liquid_splits, :list, required: true

  @doc """
  Hidden identity inputs for refs the module code does not render.

  `LiquidPreview.strip_logic/1` removes `{% if %}` / `{% for %}` / `{% hide %}` regions
  before the code is split into ref slots, so a `{% ref refs.x %}` inside one
  produces no inputs at all. `refs` is `on_replace: :delete_if_exists`, so once
  *any* ref renders, the params carry a shortened list and `cast_assoc(:refs)`
  **deletes** every ref missing from it — on the first keystroke, silently.

  Carrying identity is enough for a persisted ref: `cast_assoc` matches on the
  primary key and leaves fields the params don't mention alone. This is the same
  trick `ref/1` relies on for persisted refs, and the ref-side counterpart of
  `carried_var/1`.

  > #### Known gap {: .warning}
  >
  > An UNSAVED ref inside a stripped region is still dropped. Identity-only
  > carrying cannot save it — with no primary key to match on, Ecto rebuilds the
  > record from the params alone and blanks every field, which is exactly why
  > `module_config/1` refuses the same shortcut for unsaved vars. Carrying it in
  > full is not possible either: `data` is a polymorphic embed whose shape is the
  > whole nested block editor. Reachable by adding a module ref inside `{% if %}`
  > and running "fetch missing refs" on an already-saved block.
  """
  def carried_refs(assigns) do
    rendered_names =
      for {:ref, name} <- assigns.liquid_splits, do: name

    assigns = assign(assigns, :rendered_names, rendered_names)

    ~H"""
    <div class="block-carried-refs" hidden>
      <.inputs_for :let={ref_form} field={@refs_field} skip_hidden>
        <%= if ref_form[:name].value not in @rendered_names and ref_form[:id].value not in [nil, ""] do %>
          <Input.input type={:hidden} field={ref_form[:id]} />
          <Input.input type={:hidden} field={ref_form[:_persistent_id]} value={ref_form.index} />
        <% end %>
      </.inputs_for>
    </div>
    """
  end

  attr :ref_name, :string, required: true
  attr :refs_field, :any, required: true
  attr :target, :any, required: true
  attr :target_ref, :any, default: nil
  attr :form_id, :any, default: nil
  attr :config_open, :string, default: nil

  attr :footnotes_enabled, :boolean

  def ref(assigns) do
    refs = Changeset.get_assoc(assigns.refs_field.form.source, :refs, :struct)
    ref_names = Enum.map(refs, & &1.name)
    ref_found = Enum.member?(ref_names, assigns.ref_name)

    assigns =
      assigns
      |> assign(:ref_found, ref_found)
      |> assign(:ref_names, ref_names)
      |> assign_new(:footnotes_enabled, fn ->
        assigns.ref_name in footnote_ref_names(assigns.refs_field.form.source)
      end)

    ~H"""
    <%= if @ref_found do %>
      <.inputs_for :let={ref_form} field={@refs_field} skip_hidden>
        <%= if ref_form[:name].value == @ref_name do %>
          <section b-ref={ref_form[:name].value} id={"block_ref-#{ref_form[:uid].value}"}>
            <.polymorphic_embed_inputs_for :let={block} field={ref_form[:data]}>
              <.dynamic_block
                id={"#{ref_form[:uid].value}-#{block[:type].value}"}
                block_id={ref_form[:uid].value}
                config_open={@config_open}
                is_ref?={true}
                ref_name={ref_form[:name].value}
                ref_description={ref_form[:description].value}
                ref_form={ref_form}
                footnotes_enabled={@footnotes_enabled}
                block={block}
                target={@target}
                target_ref={@target_ref}
                form_id={@form_id}
              />
            </.polymorphic_embed_inputs_for>
            <%!-- Ref identity. Same rule as vars: once the ref has a primary key,
                  `cast_assoc` matches on it and leaves the fields the params
                  don't mention alone, so only the identity needs to round-trip.
                  An unsaved ref has nothing to match on, so it carries everything. --%>
            <Input.input type={:hidden} field={ref_form[:id]} />
            <Input.input type={:hidden} field={ref_form[:_persistent_id]} value={ref_form.index} />
            <%= if ref_form[:id].value in [nil, ""] do %>
              <Input.input type={:hidden} field={ref_form[:description]} />
              <Input.input type={:hidden} field={ref_form[:name]} />
              <Input.input type={:hidden} field={ref_form[:uid]} />
            <% end %>
            <%!-- The media FKs are the exception, and they always round-trip.
                  They are set programmatically (picker/drawer → `commit_ref_data`),
                  so unlike every other field here they can hold a value that is in
                  the changeset but not yet in the DB — leaving them out of the DOM
                  means LiveView's form recovery has nothing to replay and the pick
                  dies with the process. Four fields per ref is the price of that.
                  The steady-state half of this lives in
                  `events.ex`'s `merge_programmatic_ref_media/2`. --%>
            <Input.input type={:hidden} field={ref_form[:image_id]} />
            <Input.input type={:hidden} field={ref_form[:video_id]} />
            <Input.input type={:hidden} field={ref_form[:gallery_id]} />
            <Input.input type={:hidden} field={ref_form[:file_id]} />
          </section>
        <% end %>
      </.inputs_for>
    <% else %>
      <section class="alert danger">
        Ref <code>{@ref_name}</code>
        is missing!<br /><br /> If the module has been changed, this block might be out of sync!<br /><br />
        Available refs are:<br /><br />
        <div :for={ref_name <- @ref_names} :key={ref_name}>
          &rarr; {ref_name}<br />
        </div>
      </section>
    <% end %>
    """
  end

  # Resolve module definitions once for the block, rather than once per text ref.
  # Keep this tied to the current form and module cache so edited definitions do
  # not become another mount-only snapshot.
  defp footnote_ref_names(block_cs) do
    refs = Changeset.get_assoc(block_cs, :refs, :struct)

    if Enum.any?(refs, &match?(%{data: %{type: "text"}}, &1)) do
      block_cs
      |> fetch_block_module()
      |> module_footnote_ref_names()
    else
      []
    end
  end

  defp fetch_block_module(block_cs) do
    Brando.Content.fetch_module(
      Changeset.get_field(block_cs, :module_id),
      Changeset.get_field(block_cs, :module_origin) || :local
    )
  end

  defp module_footnote_ref_names(module) do
    case module do
      %{refs: definitions} when is_list(definitions) ->
        for %{name: name, data: %{data: %{footnotes: true}}} <- definitions, do: name

      _ ->
        []
    end
  end

  def handle(assigns) do
    ~H"""
    <div class="sort-handle block-action" data-sortable-group={1} data-popover={gettext("Reposition block (click&drag)")}>
      <.icon name="arrow-up-down" />
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
      |> assign_new(:ref_form, fn -> nil end)
      |> assign_new(:config_open, fn -> nil end)
      |> assign_new(:form_id, fn -> nil end)
      |> assign_new(:target_ref, fn -> nil end)
      |> assign_new(:block_id, fn ->
        if assigns[:is_ref?] && assigns[:ref_form] do
          assigns.ref_form[:uid].value
        else
          assigns.block[:uid].value
        end
      end)
      |> assign_new(:component_target, fn ->
        # When dealing with polymorphic embeds (like refs), after form validation
        # the type field might not reflect the actual data type. Check the actual
        # block data type first if it exists.
        type_value =
          if assigns.block.source && assigns.block.source.data && Map.has_key?(assigns.block.source.data, :type) do
            # If we have actual changeset data with a type, use that (most reliable)
            assigns.block.source.data.type
          else
            # Otherwise fall back to the form field value
            assigns.block[:type].value
          end

        type_atom = String.to_existing_atom(type_value)

        block_type =
          (type_atom
           |> to_string()
           |> Macro.camelize()) <> "Block"

        block_module = Module.concat([Blocks, block_type])

        case Code.ensure_compiled(block_module) do
          {:module, _} ->
            block_module

          _ ->
            Function.capture(__MODULE__, type_atom, 1)
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
      {component(
        @component_target,
        assigns,
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      )}
    <% else %>
      <.live_component
        module={@component_target}
        id={@id}
        block={@block}
        config_open={@config_open}
        is_ref?={@is_ref?}
        opts={@opts}
        belongs_to={@belongs_to}
        ref_name={@ref_name}
        ref_description={@ref_description}
        ref_form={@ref_form}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
        target={@target}
        target_ref={@target_ref}
        form_id={@form_id}
      />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :block, :any, required: true
  attr :multi, :boolean, default: false
  attr :wide_config, :boolean, default: false
  attr :config_layout, :string, default: nil
  attr :config_title, :string, default: nil
  attr :config_subtitle, :string, default: nil
  attr :config_icon, :string, default: "sliders-horizontal"
  attr :type, :any
  attr :block_type, :any
  attr :is_datasource?, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :ref_form, :any, default: nil
  attr :datasource, :any
  attr :bg_color, :string, default: nil
  attr :uid, :any
  attr :config_open, :string, default: nil

  attr :carried_config, :list,
    default: nil,
    doc: """
    Scalar config fields to carry as bare hidden inputs while the config is
    closed: a field (sent as "" when nil, like a text or hidden input) or
    `{:radio, field}` (left out when nil, like a radio group with nothing checked).
    """

  slot :inner_block
  slot :config
  slot :config_footer
  slot :description
  slot :instructions

  def block(assigns) do
    block_cs = assigns.block.source

    # For refs, use the ref's UID to ensure modal targets match
    uid =
      if assigns[:is_ref?] && assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        Changeset.get_field(block_cs, :uid) || Brando.Utils.generate_uid()
      end

    # For refs, get active and collapsed from ref_form, otherwise from block
    {active, collapsed} =
      if assigns[:is_ref?] && assigns[:ref_form] do
        ref_cs = assigns.ref_form.source
        {Changeset.get_field(ref_cs, :active), Changeset.get_field(ref_cs, :collapsed)}
      else
        {Changeset.get_field(block_cs, :active), Changeset.get_field(block_cs, :collapsed)}
      end

    assigns =
      assigns
      |> assign_new(:block_type, fn ->
        Changeset.get_field(block_cs, :type) || (assigns.is_entry? && "entry")
      end)
      |> assign(:uid, uid)
      |> assign(:active, active)
      |> assign(:collapsed, collapsed)
      |> assign(:marked_as_deleted, Changeset.get_field(block_cs, :marked_as_deleted))

    assigns = assign(assigns, :config_open?, assigns.config_open == uid)

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        "ref-block",
        @block_type,
        @collapsed && "collapsed",
        !@active && "disabled"
      ]}
    >
      <%!-- Measured, not assumed: dropping the config slot while closed blanks
            the ref's `data` fields on the next validate. A polymorphic embed
            rebuilds from params the same way the block's `has_many` vars do, so
            "cast leaves unmentioned fields alone" does not hold here either.
            The slot therefore always renders; only the modal chrome is gated.
            Pinned by `blocks/block-ref-config-persistence.spec.js`. --%>
      <div :if={!@config_open?} class="block-config-carried" hidden>
        <%!-- A ref type that lists its config fields carries just their
              values: the full widgets (labels, radios, error and help
              elements) made up most of a ref's markup and were re-sent on
              every keystroke in it. Each value is sent the way its widget
              would send it; see `carried_inputs/1`. --%>
        <%= if @carried_config do %>
          <input :for={{name, value} <- carried_inputs(@carried_config)} type="hidden" name={name} value={value} />
        <% else %>
          <%= if @config do %>
            {render_slot(@config)}
          <% end %>
        <% end %>
      </div>
      <Content.modal
        :if={@config_open?}
        title={@config_title || gettext("Configure")}
        subtitle={@config_subtitle}
        icon={@config_icon}
        layout={@config_layout}
        id={"block-#{@uid}_config"}
        show={true}
        close={JS.push("close_block_config", target: @target)}
        wide={@wide_config}
      >
        <%= if @config do %>
          {render_slot(@config)}
        <% end %>
        <:footer>
          <span :if={@config_layout == "editor"} class="modal-footer-note">{gettext("Included when you save the entry")}</span>
          <button type="button" class="primary" phx-click="close_block_config" phx-target={@target}>
            {if @config_layout == "editor", do: gettext("Done"), else: gettext("Close")}
          </button>
          <%= if @config_footer do %>
            {render_slot(@config_footer)}
          <% end %>
        </:footer>
      </Content.modal>

      <Input.input type={:hidden} field={@block[:uid]} />

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
          ref_form={@ref_form}
          target={@target}
          multi={@multi}
          is_ref?={@is_ref?}
          is_datasource?={false}
        >
          <:description>
            {render_slot(@description)}
          </:description>
        </.toolbar>

        <div class="block-content" id={"block-#{@uid}-block-content"}>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  ##
  ## Ref blocks

  def html(assigns) do
    uid =
      if assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        assigns.block[:uid].value
      end

    assigns = assign(assigns, :uid, uid)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          ref_form={@ref_form}
          config_open={@config_open}
          multi={false}
          target={@target}
        >
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
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
    uid =
      if assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        assigns.block[:uid].value
      end

    assigns = assign(assigns, :uid, uid)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          ref_form={@ref_form}
          config_open={@config_open}
          multi={false}
          target={@target}
        >
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
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
    block_data_cs = Block.get_block_data_changeset(assigns.block)

    uid =
      if assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        assigns.block[:uid].value
      end

    assigns =
      assigns
      |> assign(:uid, uid)
      |> assign(:text, Changeset.get_field(block_data_cs, :text))

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          ref_form={@ref_form}
          config_open={@config_open}
          multi={false}
          target={@target}
          carried_config={[block_data[:text]]}
        >
          <:description>
            {gettext("Comment — not shown on frontend.")}
          </:description>
          <:config>
            <div id={"block-#{@uid}-conf-textarea"}>
              <Input.textarea field={block_data[:text]} />
            </div>
          </:config>
          <div id={"block-#{@uid}-comment"}>
            <%= if @text do %>
              {@text |> raw()}
            <% end %>
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def input(assigns) do
    uid =
      if assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        assigns.block[:uid].value
      end

    assigns = assign(assigns, :uid, uid)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          ref_form={@ref_form}
          config_open={@config_open}
          multi={false}
          target={@target}
        >
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
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
    uid =
      if assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        assigns.block[:uid].value
      end

    assigns = assign(assigns, :uid, uid)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          ref_form={@ref_form}
          config_open={@config_open}
          multi={false}
          target={@target}
          carried_config={[{:radio, block_data[:level]}, block_data[:id], block_data[:link]]}
        >
          <:description>
            (H{block_data[:level].value})<%= if @ref_description do %>
              {@ref_description}
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
            <%!-- NOT phx-update="ignore": remote-sync applies must reach the
            textarea's DOM value. LV's focused-input protection covers local
            typing, and the block owns its form (single-owner), so a parent
            re-render can never patch in stale content anymore — the ignore
            was a workaround from the propagate/clobber era. --%>
            <Input.input
              type={:textarea}
              field={block_data[:text]}
              class={"h#{block_data[:level].value}"}
              placeholder={block_data[:placeholder].value}
              phx-debounce={300}
              data-autosize={true}
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

  def blocks(assigns) do
    ~H"""
    <.inputs_for :let={data} field={@block[:data]}>
      <Input.hidden field={data[:module_set]} />
      <button
        type="button"
        class="block-region-entry"
        phx-click="open_block_slot"
        phx-target={@target}
        phx-value-ref_name={@ref_name}
      >
        <span class="block-region-icon" aria-hidden="true"><.icon name="group" /></span>
        <span class="block-region-copy">
          <span class="block-region-label">{@ref_description || @ref_name}</span>
          <span class="block-region-hint">{gettext("Edit blocks")} · {data[:module_set].value}</span>
        </span>
        <span class="block-region-arrow" aria-hidden="true"><.icon name="arrow-up-right" /></span>
      </button>
    </.inputs_for>
    """
  end

  # The ref's own placeholder, when its module sets one, replaces the editor's
  # generic "Write something…".
  defp text_labels(placeholder) do
    labels = BrandoAdmin.Components.Form.Input.RichTextLabels.labels()

    labels
    |> then(&if(placeholder in [nil, ""], do: &1, else: Map.put(&1, :placeholder, placeholder)))
    |> Jason.encode!()
  end

  def text(assigns) do
    block_data_cs = Block.get_block_data_changeset(assigns.block)

    extensions =
      case Changeset.get_field(block_data_cs, :extensions) do
        nil -> "all"
        extensions when is_list(extensions) -> Enum.join(extensions, "|")
        extensions -> extensions
      end

    uid =
      if assigns[:ref_form] do
        assigns.ref_form[:uid].value
      else
        assigns.block[:uid].value
      end

    styles =
      block_data_cs
      |> Changeset.get_field(:styles)
      |> Brando.Villain.Blocks.TextBlock.Data.normalize_styles()
      |> Jason.encode!()

    assigns =
      assigns
      |> assign(:uid, uid)
      |> assign(:text_type, Changeset.get_field(block_data_cs, :type))
      |> assign(
        :ai_enabled?,
        AI.field_ai_opts(:block_text) != [] && AI.configured?(AI.field_ai_opts(:block_text))
      )
      |> assign(:extensions, extensions)
      |> assign(:styles, styles)
      |> assign(:footnotes, assigns[:footnotes_enabled] == true)
      |> assign(:labels, text_labels(Changeset.get_field(block_data_cs, :placeholder)))

    ~H"""
    <.inputs_for :let={text_block_data} field={@block[:data]}>
      <div id={"ref-#{@uid}-wrapper"} data-block-uid={@uid}>
        <.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          ref_form={@ref_form}
          config_open={@config_open}
          multi={false}
          target={@target}
          carried_config={[
            text_block_data[:footnotes],
            text_block_data[:footnote_module_set],
            text_block_data[:placeholder],
            {:radio, text_block_data[:type]}
          ]}
        >
          <:description>
            <%= if @ref_description not in [nil, ""] do %>
              {@ref_description}
            <% else %>
              {@text_type}
            <% end %>
          </:description>
          <:config>
            <Input.hidden field={text_block_data[:footnotes]} />
            <Input.hidden field={text_block_data[:footnote_module_set]} />
            <Input.hidden field={text_block_data[:placeholder]} />
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
          </:config>
          <%!-- Not editable in the config, and a list, so it stays out of the
                carried config and always renders here. --%>
          <%= if @extensions == "all" do %>
            <Input.hidden field={text_block_data[:extensions]} />
          <% else %>
            <input :if={@extensions == ""} type="hidden" name={text_block_data[:extensions].name <> "[]"} value="" />
            <Primitives.array_inputs :let={%{value: array_value, name: array_name}} field={text_block_data[:extensions]}>
              <input type="hidden" name={array_name} value={array_value} />
            </Primitives.array_inputs>
          <% end %>
          <div class={["text-block", @text_type]}>
            <div class="tiptap-wrapper" id={"block-#{@uid}-rich-text-wrapper"}>
              <div
                id={"block-#{@uid}-rich-text"}
                data-block-uid={@uid}
                data-tiptap-extensions={@extensions}
                data-tiptap-styles={@styles}
                data-tiptap-labels={@labels}
                data-tiptap-label={@ref_description || @ref_name || gettext("Text")}
                data-footnotes={@footnotes && "true"}
                data-footnote-ref={@ref_name}
                phx-hook="Brando.TipTap"
                data-footnote-labels={
                  Jason.encode!(%{
                    add: gettext("Add footnote"),
                    edit: gettext("Edit footnote"),
                    numbered: gettext("Edit footnote %{number}", number: "%{number}")
                  })
                }
                data-tiptap-type="block"
                data-tiptap-ai={to_string(@ai_enabled?)}
                data-name="TipTap"
              >
                <div id={"block-#{@uid}-rich-text-target-wrapper"} class="tiptap-target-wrapper" phx-update="ignore">
                  <div id={"block-#{@uid}-rich-text-target"} class="tiptap-target"></div>
                </div>
                <Input.input type={:hidden} field={text_block_data[:text]} class="tiptap-text" phx-debounce={300} />
              </div>
            </div>
          </div>
        </.block>
      </div>
    </.inputs_for>
    """
  end

  attr :click, :any, required: true
  attr :paste_context, :any, default: nil
  attr :paste_event, :string, default: nil
  attr :paste_target, :any, default: nil
  # The module picker is one shared modal, so opening it is a plain id rather
  # than an inlined `show_modal/1` — see `assets/src/uiCommands.js`. A plus sits
  # above every block at every level, which made this one of the most-repeated
  # 749-byte attributes in the mount payload.
  attr :modal, :string, default: nil

  @doc """
  The insert affordance above a block: add, and — when something compatible is
  on the clipboard — paste.

  Paste visibility used to be `:if={can_paste?(@clipboard_meta, ...)}`, which
  meant every block in the tree took `clipboard_meta` as an assign. Copying one
  block then changed an assign on all 139 components and re-rendered every one
  of them: **849 KB in a single frame at 115 root blocks, 1.2 s of server round
  trip** — by far the largest frame left in the editor, for a change that
  toggles a handful of buttons.

  The `:root` and `:container` contexts are now decided in CSS instead, from a
  `data-paste-allow` attribute that `BlockField` renders once on its own root
  (see `Block.css`). No block needs the clipboard to know whether its own
  paste button applies, so nothing re-renders.

  `{:multi, module_id}` cannot go the same way: it is an equality test between
  the copied block's parent module and this block's, and CSS has no way to
  compare two attribute values. Those buttons stay server-decided, driven by
  the scalar `paste_multi_module_id` — see `multi_paste_context/2`.
  """
  def plus(assigns) do
    assigns = assign(assigns, :paste_ctx, paste_ctx(assigns.paste_context))

    ~H"""
    <div class="block-plus-wrapper">
      <button
        class="block-plus"
        type="button"
        phx-click={@click}
        data-ui-modal-show={@modal}
        aria-label={gettext("Add block")}
      >
        <.icon name="plus" />
      </button>
      <button
        :if={@paste_ctx}
        class="block-paste"
        data-paste-ctx={@paste_ctx}
        type="button"
        phx-click={@paste_event}
        phx-target={@paste_target}
        aria-label={gettext("Paste block here")}
        data-popover={gettext("Paste block here")}
      >
        <.icon name="clipboard-check" />
      </button>
    </div>
    """
  end

  # `{:multi, _}` arrives already resolved: the block only passes that context
  # when its own `paste_multi_module_id` matched, so there is nothing left to
  # compare here.
  defp paste_ctx(:root), do: "root"
  defp paste_ctx(:container), do: "container"
  defp paste_ctx({:multi, _module_id}), do: "multi"
  defp paste_ctx(_), do: nil

  @doc """
  The `{:multi, module_id}` paste context, or nil.

  This is the one `can_paste?` rule that cannot move to CSS: it compares the
  copied entry's parent module with this block's, and CSS has no operator for
  comparing two attribute values. `paste_multi_module_id` is nil unless the
  clipboard holds a `module_entry`, so copying anything else leaves every
  block's assigns untouched.
  """
  def multi_paste_context(module_id, module_id) when not is_nil(module_id), do: {:multi, module_id}
  def multi_paste_context(_paste_multi_module_id, _module_id), do: nil

  @doc """
  The `data-paste-allow` token list for the block field root.

  CSS shows a `.block-paste[data-paste-ctx="x"]` only when an ancestor's
  `data-paste-allow` contains `x`, so this is the whole `can_paste?` rule for
  the two contexts that are expressible as a type check.
  """
  def paste_allow(nil), do: nil
  def paste_allow(%{type: :module}), do: "root container"
  def paste_allow(%{type: type}) when type in [:container, :fragment], do: "root"
  def paste_allow(_), do: nil

  attr :uid, :string, required: true
  attr :vars, :any, required: true
  attr :placement, :atom, default: :content, values: [:content, :config]
  attr :carry_persisted, :boolean, default: false
  attr :target, :any
  attr :form_id, :any, default: nil
  attr :current_user_id, :any, default: nil
  attr :language, :string, default: nil, doc: "the entry's language; link pickers offer entries in it"

  @doc """
  Renders the vars belonging to one editing surface.

  Rows are derived from `sequence` + `new_row` by `Brando.Content.Var.Layout` —
  the same packing the module editor's layout canvas previews — so what the
  author composed is what the editor sees, in that order.

  The `:config` surface additionally carries `:hidden` vars as bare hidden
  inputs. They have no UI, but their params still have to reach `cast_assoc`
  or the association would be dropped on the next validate.
  """
  def vars(assigns) do
    all_forms = var_forms(assigns.vars)

    # `carry_persisted` is the closed config surface: a var that already has a
    # primary key only needs its identity to round-trip, because `cast_assoc`
    # matches on it and leaves `value` alone. Rendering its editing widget into
    # a hidden container instead cost 546 KB of a 115-block mount, measured on
    # a fixture where three of five module types carry config vars. An unsaved
    # var still renders in full — it has no key to match on.
    {carried, visible} =
      all_forms
      |> Enum.filter(&(&1.placement == assigns.placement))
      |> then(fn forms ->
        if assigns.carry_persisted, do: Enum.split_with(forms, &persisted_var?/1), else: {[], forms}
      end)

    rows = Layout.pack(visible)

    hidden_forms =
      if assigns.placement == :config,
        do: carried ++ Enum.filter(all_forms, &(&1.placement == :hidden)),
        else: carried

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:hidden_forms, hidden_forms)

    ~H"""
    <div :if={@rows != [] or @hidden_forms != []} class="block-vars-wrapper">
      <div :if={@rows != []} class="vars-info" phx-click="show_vars_instructions" phx-target={@target}>
        <div class="icon">
          <.icon name="variable" />
        </div>
        <div class="info">
          <span class="vars-label">
            {gettext("Block")}<br /> {gettext("Variables")}
          </span>
        </div>
      </div>
      <div :if={@rows != []} class="block-vars">
        <div :for={row <- @rows} class="block-vars-row">
          <.live_component
            :for={entry <- row}
            module={RenderVar}
            id={"block-#{@uid}-render-var-#{@placement}-#{entry.form.id}"}
            var={entry.form}
            render={@placement}
            on_change={send_to(@target)}
            form_id={@form_id}
            current_user_id={@current_user_id}
            language={@language}
            publish
          />
        </div>
      </div>
      <div :for={entry <- @hidden_forms} class="block-vars-carried" hidden>
        <.carried_var :if={entry.placement == :hidden} var={entry.form} />
        <.carried_var_value :if={entry.placement != :hidden} var={entry.form} type={entry.type} />
      </div>
    </div>
    """
  end

  attr :var, :any, required: true
  attr :type, :any, default: nil

  # A persisted var whose editing surface is not on screen: identity plus the
  # value it stores, and nothing else.
  defp carried_var_value(assigns) do
    assigns = assign(assigns, :fields, value_fields(assigns.type))

    ~H"""
    <input type="hidden" name={@var[:id].name} value={@var[:id].value} />
    <input type="hidden" name={@var[:_persistent_id].name} value={@var.index} />
    <input :for={field <- @fields} type="hidden" name={@var[field].name} value={@var[field].value} />
    """
  end

  @doc """
  Params-only round trip for a var with no editable UI (`:hidden` placement).

  Without it the var's params are absent on submit and `cast_assoc` drops the
  association entirely.

  For a **persisted** var the identity is enough: `cast_assoc` matches on the
  primary key and leaves every field the params don't mention alone, so
  re-emitting values would only risk writing back a stale copy.

  For an **unsaved** var there is no identity to match on. `Relation.pop_current/2`
  keys the existing records by primary key, so every pk-less var collides on
  `[nil]` and Ecto builds a brand new record out of whatever params arrived —
  identity alone yields a var with `key`, `placement` and `value` all nil, which
  is silent data loss on the first save of any block. So an unsaved var carries
  its cast surface, driven off `Brando.Content.Block.carried_var_attrs/0` so the
  two cannot drift. This is bounded and temporary: after the first save the var
  has an id and drops back to identity-only.

  What it does *not* carry is ownership and parentage — `creator_id` and the
  owner FKs. Every input here is hand-editable before submit, and those fields
  are server authority: `creator_id` is forced in `var_changeset/4`, and the
  owner FK is set by whichever schema's `cast_assoc(:vars, …)` builds the var.
  """
  attr :var, :any, required: true

  # Resolved at compile time, not per render. A function call in the template
  # cannot be change-tracked — LiveView has no way to know the list is constant,
  # so it re-evaluates and re-sends the whole comprehension on every diff.
  # Read off the leaf `Brando.Content.VarAttrs`, not off `Brando.Content.Block`:
  # this is a compile-time call, and `Block` is a Blueprint schema inside
  # Blueprint's compile-connected component — see issue #2737.
  @carried_var_fields VarAttrs.carried()

  def carried_var(assigns) do
    # Blank, not just nil: once a validate round trip has happened the id comes
    # back as the "" that this component's own hidden input submitted, and
    # treating that as persisted is what made the fix stop working after the
    # first keystroke.
    assigns =
      assigns
      |> assign(:unsaved?, assigns.var[:id].value in [nil, ""])
      |> assign(:carried_fields, @carried_var_fields)

    ~H"""
    <input type="hidden" name={@var[:id].name} value={@var[:id].value} />
    <input type="hidden" name={@var[:_persistent_id].name} value={@var.index} />
    <%= if @unsaved? do %>
      <.carried_var_field :for={field <- @carried_fields} field={@var[field]} />
      <.inputs_for :let={option} field={@var[:options]}>
        <.carried_var_field field={option[:label]} />
        <input type="hidden" name={option[:value].name} value={option[:value].value} />
      </.inputs_for>
    <% end %>
    """
  end

  attr :field, :any, required: true

  # An array field needs one `name[]` input per element — a single input would
  # arrive as a string and fail the cast.
  defp carried_var_field(%{field: %{value: value}} = assigns) when is_list(value) do
    ~H"""
    <input :for={v <- @field.value} type="hidden" name={"#{@field.name}[]"} value={v} />
    """
  end

  # A language map (the label): one input per language, so it casts back whole.
  defp carried_var_field(%{field: %{value: value}} = assigns) when is_map(value) and not is_struct(value) do
    ~H"""
    <input :for={{language, text} <- @field.value} type="hidden" name={"#{@field.name}[#{language}]"} value={text} />
    """
  end

  defp carried_var_field(assigns) do
    ~H"""
    <input type="hidden" name={@field.name} value={@field.value} />
    """
  end

  defp persisted_var?(%{form: form}), do: form[:id].value not in [nil, ""]

  # The fields a var actually stores its value in, by type. A carried var still
  # has to round-trip these: an edit made while the config modal was open lives
  # in the changeset's *changes*, and `validate_block` rebuilds entry blocks
  # from `changeset.data` — so a value missing from the params is an edit lost,
  # not an edit preserved. Everything around them (label, field wrapper, the
  # widget itself) is what gets dropped.
  defp value_fields(:boolean), do: [:value_boolean]
  defp value_fields(:image), do: [:value, :image_id]
  defp value_fields(:file), do: [:value, :file_id]
  defp value_fields(:video), do: [:value, :video_id]
  defp value_fields(:gallery), do: [:value, :gallery_id]
  defp value_fields(:form), do: [:value, :form_id]
  defp value_fields(:link), do: [:value, :identifier_id, :link_text, :link_type, :link_target_blank]
  defp value_fields(:color), do: [:value, :palette_id]
  defp value_fields(_), do: [:value]

  # Builds the same sub-forms `<.inputs_for>` would, then decorates each with
  # the layout facts so `Layout.pack/1` can group them without re-reading the
  # changeset for every comparison.
  defp var_forms(field) do
    field.form.source
    |> then(&field.form.impl.to_form(&1, field.form, field.field, []))
    |> Enum.map(fn form ->
      %{
        form: form,
        key: Changeset.get_field(form.source, :key),
        type: Changeset.get_field(form.source, :type),
        width: Changeset.get_field(form.source, :width) || :full,
        new_row: Changeset.get_field(form.source, :new_row) == true,
        placement: Changeset.get_field(form.source, :placement) || :content,
        sequence: Changeset.get_field(form.source, :sequence) || 0
      }
    end)
    |> Enum.sort_by(& &1.sequence)
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
  attr :ref_form, :any, default: nil
  attr :palette, :any, default: nil
  attr :container, :any, default: nil
  attr :module_datasource_module_label, :string, default: nil
  attr :module_datasource_type, :any, default: nil
  attr :module_datasource_query, :any, default: nil
  attr :available_identifiers, :list, default: []

  slot :inner_block
  slot :description

  def toolbar(assigns) do
    # Use ref_form fields when it's a ref, otherwise use block fields
    active_field = if assigns.is_ref? && assigns.ref_form, do: assigns.ref_form[:active], else: assigns.block[:active]

    collapsed_field =
      if assigns.is_ref? && assigns.ref_form, do: assigns.ref_form[:collapsed], else: assigns.block[:collapsed]

    assigns =
      assigns
      |> assign(:active_field, active_field)
      |> assign(:collapsed_field, collapsed_field)

    ~H"""
    <div class="block-toolbar">
      <div class="block-description">
        <Primitives.label field={@active_field} class="switch small on-off">
          <span class="visually-hidden">{gettext("Active")}</span>
          <Input.input type={:checkbox} field={@active_field} />
          <div class="slider round"></div>
        </Primitives.label>
        <span class="block-type">
          <span :if={@is_datasource?} class="datasource">
            {gettext("Datamodule")} |
          </span>
          <span :if={@type == :module and not @is_datasource?} phx-no-format>
            <%= if @multi do %>Multi <% end %><%= gettext("Module") %> |
          </span>
          <span :if={@type == :module_entry}>
            {gettext("Entry")} |
          </span>
          <span :if={@type == :container}>
            {gettext("Container")} |
          </span>
          <span :if={@type == :fragment}>
            {gettext("Fragment")} |
          </span>
        </span>
        <span :if={@description} class="block-name">
          {render_slot(@description)}<span :if={@active_field.value in [false, "false"]}> &lt;{gettext("Deactivated")}&gt;</span>
        </span>
        <%= if @type == :container do %>
          <%= if @container do %>
            {@container.name}
          <% else %>
            Standard
          <% end %>
          <%= if @palette do %>
            <div class="arrow">&rarr;</div>
            <button type="button" class="btn-palette" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
              {@palette.name}
            </button>
            <div class="circle-stack">
              <span
                :for={color <- Enum.reverse(@palette.colors)}
                :key={color.hex_value}
                class="circle tiny"
                style={"background-color:#{color.hex_value}"}
                data-popover={"#{color.name}"}
              ></span>
            </div>
            <div :if={@block[:anchor].value} class="container-target">
              &nbsp;|&nbsp;#{@block[:anchor].value}
            </div>
          <% else %>
            <div class="arrow">&rarr;</div>
            <button type="button" class="btn-palette" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
              {gettext("<No palette>")}
            </button>
          <% end %>
          <span :if={@block[:description].value not in ["", nil]} class="description">
            {@block[:description].value}
          </span>
        <% else %>
          <span :if={@block[:description].value not in ["", nil]} class="description">
            {@block[:description].value}
          </span>
        <% end %>
      </div>
      <div class="block-content" id={"block-#{@uid}-block-toolbar-content"}>
        {render_slot(@inner_block)}
      </div>
      <div class="block-actions" id={"block-#{@uid}-block-toolbar-actions"}>
        <%!-- Notes: the count of open notes is a sticky attribute the client
              sets (`assets/src/Notes`), so a note never re-renders a block. --%>
        <button
          :if={!@is_ref?}
          type="button"
          class="block-action block-note"
          data-block-note
          aria-label={gettext("Note on this block")}
        >
          <.icon name="message-square-text" />
        </button>
        <.handle :if={!@is_ref?} />
        <.block_actions_dropdown
          :if={!@is_ref?}
          uid={@uid}
          target={@target}
          instructions={@instructions}
          config={@config}
        />
        <%!-- Ref: keep inline buttons --%>
        <div
          :if={@is_ref? && @instructions}
          class="block-action help"
          phx-click="toggle_help"
          phx-target={@target}
          data-popover={gettext("Show instructions")}
          role="button"
          aria-label={gettext("Show instructions")}
        >
          <.icon name="circle-question-mark" />
        </div>
        <button
          :if={@is_ref? && @config}
          type="button"
          class="block-action config"
          phx-click="open_block_config"
          phx-value-uid={@uid}
          phx-target={@target}
          data-popover={gettext("Configure block")}
          aria-label={gettext("Configure block")}
        >
          <.icon name="cog" />
        </button>
        <Primitives.label
          field={@collapsed_field}
          class="block-action toggler"
          popover={gettext("Collapse (hide) block in block editor")}
        >
          <span class="visually-hidden">{gettext("Collapse (hide) block in block editor")}</span>
          <%!-- Both icons, switched in CSS off the checkbox before them, so the
                click shows at once instead of after the validate round trip.
                `uiCommands.js` flips the block's `collapsed` class the same way. --%>
          <Input.input type={:checkbox} field={@collapsed_field} />
          <.icon name="eye-off" class="when-collapsed" />
          <.icon name="eye" class="when-expanded" />
        </Primitives.label>

        <div
          :if={!@is_ref?}
          class="dirty block-action toggler"
          data-popover={gettext("Block has changes")}
          role="button"
          aria-label={gettext("Block has changes")}
          phx-click="show_dirty"
          phx-target={@target}
        >
          ●
        </div>
      </div>
    </div>
    """
  end

  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :instructions, :string, default: nil
  attr :config, :boolean, default: false

  # Every attribute here is emitted once per block at every nesting level, so
  # the encoded JS commands this used to carry (`toggle_dropdown` 443 B,
  # `show_modal |> hide_dropdown` 1 022 B, and four more) dominated the mount
  # payload. The triggers vary only by id, so they now name the id and let the
  # delegated handler in `assets/src/uiCommands.js` rebuild the command. The
  # handler also closes the open dropdown on any outside click, which is what
  # the removed `phx-click-away` and the per-item `hide_dropdown` did.
  defp block_actions_dropdown(assigns) do
    dropdown_id = "block-#{assigns.uid}-dropdown"
    assigns = assign(assigns, :dropdown_id, dropdown_id)

    ~H"""
    <div class="block-action-dropdown">
      <button
        type="button"
        class="block-action"
        data-ui-dropdown-toggle={@dropdown_id}
        data-popover={gettext("More actions")}
        aria-label={gettext("More actions")}
      >
        <.icon name="circle-ellipsis" />
      </button>
      <ul class="block-action-dropdown-content hidden" id={@dropdown_id}>
        <li :if={@instructions}>
          <button type="button" phx-click="toggle_help" phx-target={@target}>
            <.icon name="circle-question-mark" /> {gettext("Instructions")}
          </button>
        </li>
        <li :if={@config}>
          <button type="button" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
            <.icon name="cog" /> {gettext("Configure")}
          </button>
        </li>
        <li>
          <%!-- `handle_block_event/3` reads the uid off the component's own assigns, so
               the old `value: %{block_uid: @uid}` never reached anything. --%>
          <button type="button" phx-click="duplicate_block" phx-target={@target}>
            <.icon name="copy" /> {gettext("Duplicate here")}
          </button>
        </li>
        <li>
          <button type="button" phx-click="copy_block" phx-target={@target}>
            <.icon name="clipboard" /> {gettext("Copy to clipboard")}
          </button>
        </li>
        <li>
          <button type="button" phx-click="delete_block" phx-target={@target}>
            <.icon name="trash" /> {gettext("Delete")}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :table_template_name, :string
  attr :form_id, :any, default: nil

  def table(assigns) do
    table_rows_value = assigns.block_data[:table_rows].value

    valid? =
      table_rows_value not in [[], "", nil] &&
        !is_struct(table_rows_value, Ecto.Association.NotLoaded)

    assigns =
      assign_derived(assigns, [:block_data],
        valid?: valid?,
        columns: if(valid?, do: table_columns(table_rows_value), else: []),
        row_count: if(valid?, do: length(table_rows_value), else: 0)
      )

    ~H"""
    <div class="table-block-wrapper">
      <div class="table-info" phx-click="show_table_instructions" phx-target={@target}>
        <div class="icon">
          <.icon name="table" />
        </div>
        <div class="info">
          <span class="table-label">
            {gettext("Tabular data")}<br /> [{@table_template_name}]
          </span>
        </div>
      </div>
      <div class="table-block">
        <%= if !@valid? do %>
          <div class="block-instructions">
            <p>
              {gettext("This block implements tabular data, but the table is empty.")}<br />
              {gettext("Click the 'add row' button below to get started.")}
            </p>
            <button
              type="button"
              class="tiny add-table-row"
              phx-click="add_table_row"
              phx-target={@target}
              data-testid="add-table-row"
            >
              {gettext("Add row")}
            </button>
          </div>
        <% else %>
          <%!-- The rows are a table like an inline subform's (SubformTable.css):
                one line per row under one row of headings, the variables'
                compact controls in the cells --%>
          <div id={"block-#{@uid}-table-frame"} class="subform-table-frame" phx-hook="Brando.TableRows">
            <div class="subform-table-scroll">
              <div class="subform-table">
                <div class="subform-table-head" aria-hidden="true">
                  <div class="subform-table-row">
                    <span class="subform-tools"></span>
                    <span :for={column <- @columns} class="subform-table-heading" data-type={column.type}>
                      {column.label}
                    </span>
                    <span class="subform-row-end"></span>
                  </div>
                </div>
                <div
                  id={"sortable-#{@uid}-table-rows"}
                  class="subform-table-body table-rows"
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
                      <input type="hidden" name={"#{@block_data.name}[sort_table_row_ids][]"} value={table_row.index} />
                      <div class="subform-tools">
                        <button
                          type="button"
                          class="subform-insert"
                          phx-click="add_table_row"
                          phx-value-index={table_row.index}
                          phx-target={@target}
                          aria-label={gettext("Insert row")}
                        >
                          <.icon name="plus" />
                        </button>
                        <button type="button" class="sort-handle" aria-label={gettext("Reorder row")}>
                          <.icon name="arrow-up-down" />
                        </button>
                      </div>

                      <.inputs_for :let={var} field={table_row[:vars]}>
                        <.live_component
                          module={RenderVar}
                          id={"block-#{@uid}-table-row-#{var.id}"}
                          var={var}
                          render={:all}
                          form_id={@form_id}
                          publish
                        />
                      </.inputs_for>
                      <div class="subform-row-end">
                        <button
                          type="button"
                          class="subform-delete"
                          name={"#{@block_data.name}[drop_table_row_ids][]"}
                          value={table_row.index}
                          phx-click={JS.dispatch("change")}
                          aria-label={gettext("Remove row")}
                        >
                          <.icon name="x" />
                        </button>
                      </div>
                    </div>
                  </.inputs_for>
                  <input type="hidden" name={"#{@block_data.name}[drop_table_row_ids][]"} />
                </div>
              </div>
            </div>
            <div class="subform-table-foot">
              <button
                type="button"
                class="add-entry-button add-table-row"
                phx-click="add_table_row"
                phx-target={@target}
                data-testid="add-table-row"
              >
                <.icon name="list-plus" />
                {gettext("Add row")}
              </button>
              <span class="subform-table-count">
                {ngettext("1 row", "%{count} rows", @row_count)}
              </span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # A table's headings are its first row's variables, which every row repeats
  defp table_columns([first_row | _]) do
    first_row
    |> table_row_vars()
    |> Enum.map(fn var ->
      %{
        label: Brando.Type.I18nString.localized(field_value(var, :label)) || field_value(var, :key),
        type: to_string(field_value(var, :type))
      }
    end)
  end

  defp table_row_vars(%Ecto.Changeset{} = row), do: row |> Ecto.Changeset.get_assoc(:vars, :struct) |> List.wrap()
  defp table_row_vars(%{vars: vars}) when is_list(vars), do: vars
  defp table_row_vars(_row), do: []

  defp field_value(%Ecto.Changeset{} = changeset, key), do: Ecto.Changeset.get_field(changeset, key)
  defp field_value(%{} = var, key), do: Map.get(var, key)

  attr :block_data, :any, required: true
  attr :module_datasource_module_label, :string, required: true
  attr :module_datasource_type, :string, required: true
  attr :module_datasource_query, :string, required: true
  attr :datasource_meta, :any, default: nil
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :available_identifiers, :any, default: []
  attr :datasource_preview, :map, default: nil
  attr :block_identifiers, :any, default: []

  def datasource(assigns) do
    ~H"""
    <div class="block-datasource">
      <div
        class="datasource-info"
        title={"#{@module_datasource_type} · #{@module_datasource_query}"}
      >
        <div class="icon">
          <.icon name="database" />
        </div>
        <div class="info">
          <strong class="datasource-title">{datasource_title(@module_datasource_type, @module_datasource_module_label)}</strong>
          <span :if={@module_datasource_type == :selection} class="datasource-help">
            {gettext("Choose which to show, and in what order.")}
          </span>
          <span :if={@module_datasource_type == :list && @datasource_preview} class="datasource-help">
            {ngettext("%{count} is shown automatically", "%{count} are shown automatically", @datasource_preview.count)}
          </span>
        </div>
      </div>

      <div :if={@module_datasource_type == :list && @datasource_preview} class="datasource-preview">
        <p :if={@datasource_preview.count == 0}>{gettext("None to show right now.")}</p>
        <ol :if={@datasource_preview.count > 0}>
          <li :for={title <- @datasource_preview.titles} title={title}>{title}</li>
        </ol>
        <p :if={@datasource_preview.count > length(@datasource_preview.titles)} class="datasource-more">
          {gettext("And %{count} more", count: @datasource_preview.count - length(@datasource_preview.titles))}
        </p>
      </div>

      <%= if @module_datasource_type == :selection do %>
        <Content.modal title={gettext("Select entries")} id={"select-entries-#{@uid}"} remember_scroll_position narrow>
          <Entries.entry_picker id={"block-#{@uid}-entries"}>
            <Entries.block_identifier
              :for={identifier <- @available_identifiers}
              identifier={identifier}
              select={JS.push("select_identifier", value: %{id: identifier.id}, target: @target)}
              available_identifiers={@available_identifiers}
              block_identifiers={@block_identifiers}
            />
          </Entries.entry_picker>
        </Content.modal>

        <div class="module-datasource-selected identifier-field">
          <div
            id={"sortable-#{@uid}-identifiers"}
            class="selected-entries identifier-list"
            phx-hook="Brando.SortableAssocs"
            data-target={@target}
            data-sortable-id={"sortable-#{@uid}-identifiers"}
            data-sortable-handle=".identifier"
            data-sortable-selector=".identifier"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={block_identifier} field={@block_identifiers}>
              <Entries.block_identifier block_identifier={block_identifier} available_identifiers={@available_identifiers}>
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
                    aria-label={gettext("Remove")}
                    data-sortable-filter
                  >
                    <.icon name="x" />
                  </button>
                </:delete>
                <:meta :let={identifier} :if={@datasource_meta not in [nil, []]}>
                  <.identifier_meta
                    datasource_meta={@datasource_meta}
                    identifier={identifier}
                    block_data={@block_data}
                  />
                </:meta>
              </Entries.block_identifier>
            </.inputs_for>
            <input type="hidden" name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"} />
          </div>

          <div class="identifier-actions">
            <button
              class="media-button select-button"
              type="button"
              phx-click="assign_available_identifiers"
              phx-target={@target}
              data-ui-modal-show={"select-entries-#{@uid}"}
            >
              {gettext("Select entries")}
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc "What a datasource block shows, e.g. \"Selected cases\"."
  def datasource_title(:selection, plural), do: gettext("Selected %{plural}", plural: plural)
  def datasource_title(:list, plural), do: gettext("All %{plural}", plural: plural)
  def datasource_title(_type, plural), do: String.capitalize(plural || "")

  attr :datasource_meta, :any, required: true
  attr :identifier, :any, required: true
  attr :block_data, :any, required: true

  def identifier_meta(%{datasource_meta: nil} = assigns) do
    ~H""
  end

  def identifier_meta(assigns) do
    datasource_meta = assigns.datasource_meta
    block_data = assigns.block_data
    identifier = assigns.identifier

    key = "#{inspect(identifier.schema)}_#{identifier.entry_id}"

    # Get current identifier_metas or initialize empty map
    current_metas = block_data[:identifier_metas].value || %{}

    # Initialize empty meta structure for this identifier if missing
    identifier_metas =
      if Map.has_key?(current_metas, key) do
        current_metas
        # Create default meta map with empty values for all fields
      else
        default_meta =
          Map.new(datasource_meta, fn field -> {to_string(field.key), nil} end)

        Map.put(current_metas, key, default_meta)
      end

    this_meta = Map.get(identifier_metas, key)

    meta_form =
      to_form(
        this_meta,
        as: "#{block_data.name}[identifier_metas][#{key}]"
      )

    # An empty override is left out of sight behind a button that adds it:
    # most entries use none, and each field took a row of its own. The input
    # stays in the form either way, so its value is always posted.
    dom_prefix =
      String.replace("meta-#{block_data[:uid].value}-#{key}", ~r/[^A-Za-z0-9_-]/, "-")

    empty = for field <- datasource_meta, blank_meta?(this_meta[to_string(field.key)]), do: field.key

    assigns =
      assigns
      |> assign(:key, key)
      |> assign(:meta_form, meta_form)
      |> assign(:dom_prefix, dom_prefix)
      |> assign(:empty, empty)

    ~H"""
    <div :if={@datasource_meta != []} class="identifier-meta">
      <div class="meta-fields">
        <div
          :for={field <- @datasource_meta}
          :key={field.key}
          id={"#{@dom_prefix}-#{field.key}"}
          class="meta-field"
          hidden={field.key in @empty}
        >
          <%= case field.type do %>
            <% :text -> %>
              <Input.text field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :rich_text -> %>
              <Input.rich_text field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :textarea -> %>
              <Input.textarea field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :toggle -> %>
              <Input.checkbox field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :date -> %>
              <Input.date field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :datetime -> %>
              <Input.date field={@meta_form[field.key]} opts={field.opts} label={field.label} />
          <% end %>
        </div>
      </div>
      <div :if={@empty != []} class="meta-add">
        <button
          :for={field <- @datasource_meta}
          :if={field.key in @empty}
          id={"#{@dom_prefix}-#{field.key}-add"}
          type="button"
          phx-click={
            JS.remove_attribute("hidden", to: "##{@dom_prefix}-#{field.key}")
            |> JS.set_attribute({"hidden", ""}, to: "##{@dom_prefix}-#{field.key}-add")
            |> JS.focus_first(to: "##{@dom_prefix}-#{field.key}")
          }
        >
          <.icon name="plus" /> {field.label}
        </button>
      </div>
    </div>
    """
  end

  defp blank_meta?(value), do: value in [nil, "", false, "false"]

  ## Private helpers

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

  defp build_heex_admin_assigns(assigns) do
    # Build assigns map for HEEx admin preview rendering.
    # Read current var values from the form (live changeset data), not
    # from the static :vars assign which is only set at init.
    block_form = assigns[:block_form]
    block_cs = block_form.source

    processed_vars =
      if block_form[:vars] do
        block_cs
        |> Changeset.get_assoc(:vars, :struct)
        |> Parser.process_vars()
      else
        %{}
      end

    processed_refs =
      if block_form[:refs] do
        block_cs
        |> Changeset.get_assoc(:refs, :struct)
        |> Parser.process_refs()
      else
        %{}
      end

    block = %{
      class: assigns[:module_class],
      uid: assigns[:uid],
      module_id: block_form[:module_id] && block_form[:module_id].value,
      anchor: block_form[:anchor] && block_form[:anchor].value,
      description: block_form[:description] && block_form[:description].value
    }

    heex_ctx = %{
      refs_field: block_form[:refs],
      refs: processed_refs,
      target: assigns[:target],
      target_ref: assigns[:target_ref],
      form_id: assigns[:form_id]
    }

    system_assigns =
      assigns[:entry]
      |> Brando.Villain.get_base_context()
      |> Brando.Villain.TemplateAdapter.Heex.context_assigns()

    base =
      system_assigns
      |> Map.merge(%{
        render_context: :admin,
        parser_module: Parser.parser_module(),
        module_id: block.module_id,
        block: block,
        refs: processed_refs,
        entries: [],
        entries_with_meta: [],
        content: "",
        forloop: nil,
        refs_field: block_form[:refs],
        target: assigns[:target],
        target_ref: assigns[:target_ref],
        form_id: assigns[:form_id],
        _heex_ctx: heex_ctx
      })

    Brando.Villain.TemplateAdapter.Heex.put_vars(base, processed_vars)
  end

  # The language of the entry being edited, for link pickers. nil for entries
  # without one, which then offer every language.
  def entry_language(%{language: language}) when not is_nil(language), do: to_string(language)
  def entry_language(_entry), do: nil

  @doc """
  Returns a root's inner block form exactly as `<.inputs_for field={@form[:block]}>`
  builds it, persistent id included, so ids and names are unchanged.

  Built here instead, through `assign_derived/3`, because LiveView cannot track
  expressions that read an `inputs_for` `:let` variable: any change in the
  slot would re-send every input of the block.
  """
  def nested_block_form(%Phoenix.HTML.Form{} = form) do
    [inner] = form.impl.to_form(form.source, form, :block, Keyword.take(form.options, [:multipart]))
    id = inner.params["_persistent_id"] || "0"

    %{
      inner
      | id: "#{form.id}_block_#{id}",
        params: Map.put(inner.params, "_persistent_id", id),
        hidden: [{"_persistent_id", id} | inner.hidden],
        index: 0
    }
  end

  @doc """
  Returns the `{name, value}` pairs of the hidden inputs `inputs_for` renders
  ahead of its slot, for forms built with `nested_block_form/1`.
  """
  def hidden_inputs(form) do
    for {field, values} <- form.hidden, value <- List.wrap(values) do
      name = Phoenix.HTML.Form.input_name(form, field)
      {if(is_list(values), do: name <> "[]", else: name), value}
    end
  end

  # What each config widget would submit:
  #
  #   * a text, number, textarea or hidden input: its value, "" when nil;
  #   * `{:radio, field}`: nothing when nil, as no radio is checked;
  #   * `{:checkbox, field}`: "true" or "false", as `Input.toggle` always
  #     submits its hidden "false" and a checked box overrides it;
  #   * `{:override, field}`: only a real boolean, as
  #     `Input.override_toggle_group` leaves an inherited value out.
  #
  # `false` is written out, because `value={false}` drops the attribute and
  # would submit "".
  defp carried_inputs(fields) do
    Enum.flat_map(fields, fn
      {:radio, %{value: nil}} -> []
      {:radio, field} -> [{field.name, carried_value(field.value)}]
      {:checkbox, field} -> [{field.name, to_string(Phoenix.HTML.Form.normalize_value("checkbox", field.value))}]
      {:override, %{value: value} = field} when value in [true, "true"] -> [{field.name, "true"}]
      {:override, %{value: value} = field} when value in [false, "false"] -> [{field.name, "false"}]
      {:override, _field} -> []
      field -> [{field.name, carried_value(field.value)}]
    end)
  end

  defp carried_value(nil), do: ""
  defp carried_value(value) when is_binary(value), do: value
  defp carried_value(value), do: to_string(value)

  # An inline `fn params -> send_update(@target, params) end` closes over the
  # whole `assigns` of the template (`@target` reads `assigns.target`): every
  # var form of the block, ~120 KB, kept alive by each RenderVar, and a new
  # value on every render. This one holds only the target, and two of them for
  # the same target are equal, so an unchanged var is not updated.
  defp send_to(target), do: fn params -> send_update(target, params) end

  # Values a render function derives from its inputs. Set with `assign/3` they
  # count as changed on every render — a function component's assigns hold only
  # what the caller passed, so there is no previous value to compare with — and
  # every expression reading them is sent again. An entry-field keystroke, which
  # changes nothing but `entry` and `liquid_splits`, re-sent each consuming
  # block's ids, toolbar and form inputs: ~2.7 KB per block. They only change
  # when an input they derive from does, so that is when they are marked.
  defp assign_derived(assigns, inputs, derived) do
    if Enum.any?(inputs, &changed?(assigns, &1)),
      do: assign(assigns, derived),
      else: Map.merge(assigns, Map.new(derived))
  end

  # A stateful component's root must be a static tag, so the `*_not_found`
  # clauses wrap this in a `<div>`.
  attr :target, :any, required: true
  slot :inner_block, required: true

  defp missing_target(assigns) do
    ~H"""
    <div class="alert danger">
      <div>
        <p>{render_slot(@inner_block)}</p>
        <p>{gettext("If it was deleted by mistake, restore it. Otherwise you can delete this block.")}</p>
        <button type="button" phx-click="delete_block" phx-target={@target}>
          {gettext("Delete this block")}
        </button>
      </div>
    </div>
    """
  end
end
