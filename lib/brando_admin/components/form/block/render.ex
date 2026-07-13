defmodule BrandoAdmin.Components.Form.Block.Render do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext
  import Phoenix.HTML
  import Phoenix.Component
  import Phoenix.LiveView, only: [send_update: 2]
  import Phoenix.LiveView.TagEngine
  import PolymorphicEmbed.HTML.Component

  alias Phoenix.LiveView.JS
  alias Ecto.Changeset
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Entries
  alias BrandoAdmin.Components.Form.Input.RenderVar

  def render(%{module_not_found: true} = assigns) do
    ~H"""
    <div class="alert danger text-mono">
      <div>
        Missing module — #{inspect(assigns.module_id)}.<br /><br />
        If this is a mistake, you can hopefully undelete the module.<br /><br /> If you're sure the module is gone, you can
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
        module_color={@module_color}
        module_name={@module_name}
        module_type={@module_type}
        heex_compiled_module={@heex_compiled_module}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        target={@myself}
        target_ref={{Block, @id}}
        form_id={@form_id}
        entry={@entry}
        insert_block={
          JS.push("insert_block", target: @myself)
          |> show_modal(@module_picker_id)
        }
        insert_multi_block={
          JS.push("insert_block_entry", value: %{multi: true}, target: @myself)
          |> show_modal(@module_picker_id)
        }
        insert_child_block={
          JS.push("insert_block", value: %{multi: true}, target: @myself)
          |> show_modal(@module_picker_id)
        }
        has_children?={@has_children?}
        clipboard_meta={@clipboard_meta}
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
            :for={{child_block_form, list_index} <- Enum.with_index(@children_forms)}
            :key={child_block_form[:uid].value}
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
              module_set={@module_set}
              form={child_block_form}
              form_id={@form_id}
              entry={@entry}
              current_user_id={@current_user_id}
              belongs_to={:multi}
              clipboard_meta={@clipboard_meta}
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
        vars={@vars}
        liquid_splits={@liquid_splits}
        entry={@entry}
        insert_block={JS.push("insert_block", target: @myself) |> show_modal(@module_picker_id)}
        has_children?={false}
        module_name={@module_name}
        module_color={@module_color}
        module_datasource_module_label={@module_datasource_module_label}
        module_datasource_type={@module_datasource_type}
        module_datasource_query={@module_datasource_query}
        datasource_meta={@datasource_meta}
        available_identifiers={@available_identifiers}
        clipboard_meta={@clipboard_meta}
        paste_context={if @belongs_to == :container, do: :container, else: :root}
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
        vars={@vars}
        liquid_splits={@liquid_splits}
        entry={@entry}
        insert_block={JS.push("insert_block_entry", target: @myself) |> show_modal(@module_picker_id)}
        has_children?={false}
        module_name={@module_name}
        module_color={@module_color}
        clipboard_meta={@clipboard_meta}
        paste_context={{:multi, @parent_module_id}}
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
        insert_block={
          JS.push("insert_block", target: @myself)
          |> show_modal(@module_picker_id)
        }
        insert_child_block={
          JS.push("insert_block", value: %{container: true}, target: @myself)
          |> show_modal(@module_picker_id)
        }
        has_children?={@has_children?}
        clipboard_meta={@clipboard_meta}
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
            :for={{child_block_form, list_index} <- Enum.with_index(@children_forms)}
            :key={child_block_form[:uid].value}
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
              clipboard_meta={@clipboard_meta}
              level={@level + 1}
            >
            </.live_component>
          </div>
        </div>
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
        insert_block={JS.push("insert_block", target: @myself) |> show_modal(@module_picker_id)}
        deleted={@deleted}
        target={@myself}
        block_module={@block_module}
        clipboard_meta={@clipboard_meta}
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
  attr :clipboard_meta, :map, default: nil

  def fragment_block(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = Block.get_block_changeset(changeset, belongs_to)
    fragment_id = Changeset.get_field(block_cs, :fragment_id)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:fragment_id, fragment_id)
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))
      |> assign(
        :update_url,
        fragment_id && Brando.Pages.Fragment.__admin_route__(:update, [fragment_id])
      )

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
      <.plus
        click={@insert_block}
        clipboard_meta={@clipboard_meta}
        paste_context={:root}
        paste_click={JS.push("paste_block", target: @target)}
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
                    [{@fragment.parent_key}/<strong><%= @fragment.key %></strong>] {@fragment.title} — {@fragment.language}
                  <% end %>
                </:description>
              </.toolbar>
              <.fragment_config uid={@uid} block={block_form} target={@target} fragment={@fragment} fragments={@fragments} />
              <div class="block-content">
                <div class="block-fragment-wrapper">
                  <div class="fragment-info" phx-click="show_fragment_instructions" phx-target={@target}>
                    <div class="icon">
                      <span class="hero-puzzle-piece"></span>
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
                    <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")} phx-target={@target}>
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
      <.plus
        click={@insert_block}
        clipboard_meta={@clipboard_meta}
        paste_context={:root}
        paste_click={JS.push("paste_block", target: @target)}
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
              {gettext("This block is currently not allowed to be a child block :(")}
            </section>
          <% end %>
        </.form>
        <%= if @has_children? do %>
          {render_slot(@inner_block)}
          <.plus
            click={@insert_child_block}
            clipboard_meta={@clipboard_meta}
            paste_context={:container}
            paste_click={JS.push("paste_child_block", target: @target)}
          />
        <% else %>
          <div class="blocks-empty-instructions">
            {gettext("Click the plus to start adding content blocks")}
          </div>
          <.plus
            click={@insert_child_block}
            clipboard_meta={@clipboard_meta}
            paste_context={:container}
            paste_click={JS.push("paste_child_block", target: @target)}
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
  attr :vars, :list, default: []
  attr :target, :any
  attr :target_ref, :any, default: nil
  attr :has_children?, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :liquid_splits, :any, default: []
  attr :insert_block, :any, default: nil
  attr :insert_child_block, :any, default: nil
  attr :insert_multi_block, :any, default: nil
  attr :module_name, :string, default: nil
  attr :module_color, :string, default: nil
  attr :module_datasource_module_label, :string, default: ""
  attr :module_datasource_type, :string, default: ""
  attr :module_datasource_query, :string, default: ""
  attr :datasource_meta, :any, default: nil
  attr :available_identifiers, :any, default: []
  attr :clipboard_meta, :map, default: nil
  attr :paste_context, :any, default: :root
  attr :form_id, :any, default: nil
  attr :module_type, :atom, default: :liquid
  attr :heex_compiled_module, :any, default: nil
  attr :entry, :any, default: nil
  slot :inner_block

  def module(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = Block.get_block_changeset(changeset, belongs_to)

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
      <.plus
        click={@insert_block}
        clipboard_meta={@clipboard_meta}
        paste_context={@paste_context}
        paste_click={JS.push("paste_block", target: @target)}
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
        <.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
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
                  <.i18n map={@module_name} />
                </:description>
              </.toolbar>

              <.module_config uid={@uid} block_form={block_form} target={@target} form_id={@form_id} />
              <.module_content
                uid={@uid}
                block_form={block_form}
                liquid_splits={@liquid_splits}
                module_class={@module_class}
                module_type={@module_type}
                heex_compiled_module={assigns[:heex_compiled_module]}
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
                block_identifiers={block_form[:block_identifiers]}
                vars={@vars}
                entry={@entry}
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
                <.i18n map={@module_name} />
              </:description>
            </.toolbar>

            <.module_config uid={@uid} block_form={@form} target={@target} form_id={@form_id} />
            <.module_content
              uid={@uid}
              block_form={@form}
              liquid_splits={@liquid_splits}
              module_class={@module_class}
              module_type={@module_type}
              heex_compiled_module={assigns[:heex_compiled_module]}
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
              block_identifiers={@form[:block_identifiers]}
              vars={@vars}
              entry={@entry}
            />
          <% end %>
        </.form>
        <%= if @has_children? do %>
          {render_slot(@inner_block)}
          <.plus
            click={@insert_multi_block}
            clipboard_meta={@clipboard_meta}
            paste_context={{:multi, @module_id}}
            paste_click={JS.push("paste_child_block", target: @target)}
          />
        <% else %>
          <%= if @multi do %>
            <div class="blocks-empty-instructions">
              {gettext("Click the plus to start adding content blocks")}
            </div>
            <.plus
              click={@insert_multi_block}
              clipboard_meta={@clipboard_meta}
              paste_context={{:multi, @module_id}}
              paste_click={JS.push("paste_child_block", target: @target)}
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

    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars vars={@block_form[:vars]} uid={@uid} target={@target} form_id={@form_id} />
        <.datasource
          :if={@is_datasource?}
          block_data={@block_form}
          uid={@uid}
          datasource_meta={@datasource_meta}
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
    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars vars={@block_form[:vars]} uid={@uid} target={@target} form_id={@form_id} />
        <.datasource
          :if={@is_datasource?}
          block_data={@block_form}
          uid={@uid}
          datasource_meta={@datasource_meta}
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
            form_id={@form_id}
          />
        </div>
        <div class="block-liquex-preview">
          <%= for split <- @liquid_splits do %>
            <%= case split do %>
              <% {:ref, ref} -> %>
                <.ref
                  refs_field={@block_form[:refs]}
                  ref_name={ref}
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
  attr :form_id, :any, default: nil

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
          <Input.text field={@block_form[:anchor]} instructions={gettext("Anchor available to block.")} />
          <.vars vars={@block_form[:vars]} uid={@uid} important={false} target={@target} form_id={@form_id} />
          <div>
            UID: <span class="text-mono">{@uid}</span>
          </div>
        </div>
        <div class="panel">
          <h2 class="titlecase">Vars</h2>
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

          <h2 class="titlecase">Refs</h2>
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
          <h2 class="titlecase">{gettext("Advanced")}</h2>
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
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          {gettext("Close")}
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
          {gettext("Close")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :ref_name, :string, required: true
  attr :refs_field, :any, required: true
  attr :target, :any, required: true
  attr :target_ref, :any, default: nil
  attr :form_id, :any, default: nil

  def ref(assigns) do
    refs = Changeset.get_assoc(assigns.refs_field.form.source, :refs, :struct)
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
          <section b-ref={ref_form[:name].value} id={"block_ref-#{ref_form[:uid].value}"}>
            <.polymorphic_embed_inputs_for :let={block} field={ref_form[:data]}>
              <.dynamic_block
                id={"#{ref_form[:uid].value}-#{block[:type].value}"}
                block_id={ref_form[:uid].value}
                is_ref?={true}
                ref_name={ref_form[:name].value}
                ref_description={ref_form[:description].value}
                ref_form={ref_form}
                block={block}
                target={@target}
                target_ref={@target_ref}
                form_id={@form_id}
              />
            </.polymorphic_embed_inputs_for>
            <!-- ref assocs -->
            <Input.input type={:hidden} field={ref_form[:description]} />
            <Input.input type={:hidden} field={ref_form[:name]} />
            <Input.input type={:hidden} field={ref_form[:uid]} />
            <Input.input type={:hidden} field={ref_form[:id]} />
            <Input.input type={:hidden} field={ref_form[:_persistent_id]} value={ref_form.index} />
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

  def handle(assigns) do
    ~H"""
    <div class="sort-handle block-action" data-sortable-group={1} data-popover={gettext("Reposition block (click&drag)")}>
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
      |> assign_new(:ref_form, fn -> nil end)
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
  attr :type, :any
  attr :block_type, :any
  attr :is_datasource?, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :ref_form, :any, default: nil
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
      <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={@wide_config}>
        <%= if @config do %>
          {render_slot(@config)}
        <% end %>
        <:footer>
          <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
            {gettext("Close")}
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
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} ref_form={@ref_form} multi={false} target={@target}>
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
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} ref_form={@ref_form} multi={false} target={@target}>
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
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} ref_form={@ref_form} multi={false} target={@target}>
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
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} ref_form={@ref_form} multi={false} target={@target}>
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
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} ref_form={@ref_form} multi={false} target={@target}>
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
            <Input.input
              type={:textarea}
              field={block_data[:text]}
              class={"h#{block_data[:level].value}"}
              phx-debounce={300}
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
      |> assign(:extensions, extensions)
      |> assign(:styles, styles)

    ~H"""
    <.inputs_for :let={text_block_data} field={@block[:data]}>
      <div id={"ref-#{@uid}-wrapper"} data-block-uid={@uid}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} ref_form={@ref_form} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in [nil, ""] do %>
              {@ref_description}
            <% else %>
              {@text_type}
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
              <Form.array_inputs :let={%{value: array_value, name: array_name}} field={text_block_data[:extensions]}>
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
                data-tiptap-styles={@styles}
                phx-hook="Brando.TipTap"
                data-tiptap-type="block"
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
  attr :clipboard_meta, :map, default: nil
  attr :paste_context, :any, default: nil
  attr :paste_click, :any, default: nil

  def plus(assigns) do
    assigns = assign(assigns, :show_paste, can_paste?(assigns.clipboard_meta, assigns.paste_context))

    ~H"""
    <div class="block-plus-wrapper">
      <button class="block-plus" type="button" phx-click={@click} aria-label={gettext("Add block")}>
        <.icon name="hero-plus" />
      </button>
      <button
        :if={@show_paste}
        class="block-paste"
        type="button"
        phx-click={@paste_click}
      >
        <.icon name="hero-clipboard-document-check" />
      </button>
    </div>
    """
  end

  defp can_paste?(nil, _), do: false
  defp can_paste?(%{type: t}, :root) when t in [:module, :container, :fragment], do: true
  defp can_paste?(%{type: :module}, :container), do: true
  defp can_paste?(%{type: :module_entry, parent_module_id: pmid}, {:multi, mid}), do: pmid == mid
  defp can_paste?(_, _), do: false

  attr :uid, :string, required: true
  attr :vars, :any, required: true
  attr :important, :boolean, default: true
  attr :target, :any
  attr :form_id, :any, default: nil

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
            {gettext("Block")}<br /> {gettext("Variables")}
          </span>
        </div>
      </div>
      <div class="block-vars">
        <.inputs_for :let={var} field={@vars} skip_hidden>
          <.live_component
            module={RenderVar}
            id={"block-#{@uid}-render-var-#{@important && "important" || "regular"}-#{var.id}"}
            var={var}
            render={(@important && :only_important) || :only_regular}
            on_change={fn params -> send_update(@target, params) end}
            form_id={@form_id}
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
        <Form.label field={@active_field} class="switch small inverse">
          <Input.input type={:checkbox} field={@active_field} />
          <div class="slider round"></div>
        </Form.label>
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
            <button type="button" class="btn-palette" phx-click={show_modal("#block-#{@uid}_config")}>
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
            <button type="button" class="btn-palette" phx-click={show_modal("#block-#{@uid}_config")}>
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
          phx-click={JS.push("toggle_help", target: @target)}
          data-popover={gettext("Show instructions")}
        >
          <.icon name="hero-question-mark-circle" />
        </div>
        <button
          :if={@is_ref? && @config}
          type="button"
          class="block-action config"
          phx-click={show_modal("#block-#{@uid}_config")}
          data-popover={gettext("Configure block")}
        >
          <.icon name="hero-cog-8-tooth" />
        </button>
        <Form.label
          field={@collapsed_field}
          class="block-action toggler"
          popover={gettext("Collapse (hide) block in block editor")}
        >
          <.icon :if={@collapsed} name="hero-eye-slash" />
          <.icon :if={!@collapsed} name="hero-eye" />
          <Input.input type={:checkbox} field={@collapsed_field} />
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

  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :instructions, :string, default: nil
  attr :config, :boolean, default: false

  defp block_actions_dropdown(assigns) do
    dropdown_id = "block-#{assigns.uid}-dropdown"
    assigns = assign(assigns, :dropdown_id, dropdown_id)

    ~H"""
    <div class="block-action-dropdown">
      <button
        type="button"
        class="block-action"
        phx-click={toggle_dropdown("##{@dropdown_id}")}
        phx-click-away={hide_dropdown("##{@dropdown_id}")}
        data-popover={gettext("More actions")}
      >
        <.icon name="hero-ellipsis-horizontal-circle" />
      </button>
      <ul class="block-action-dropdown-content hidden" id={@dropdown_id}>
        <li :if={@instructions}>
          <button
            type="button"
            phx-click={JS.push("toggle_help", target: @target) |> hide_dropdown("##{@dropdown_id}")}
          >
            <.icon name="hero-question-mark-circle" /> {gettext("Instructions")}
          </button>
        </li>
        <li :if={@config}>
          <button
            type="button"
            phx-click={show_modal("#block-#{@uid}_config") |> hide_dropdown("##{@dropdown_id}")}
          >
            <.icon name="hero-cog-8-tooth" /> {gettext("Configure")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click={
              JS.push("duplicate_block", target: @target, value: %{block_uid: @uid})
              |> hide_dropdown("##{@dropdown_id}")
            }
          >
            <.icon name="hero-document-duplicate" /> {gettext("Duplicate")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click={JS.push("copy_block", target: @target) |> hide_dropdown("##{@dropdown_id}")}
          >
            <.icon name="hero-clipboard-document" /> {gettext("Copy")}
          </button>
        </li>
        <li>
          <button
            type="button"
            phx-click={JS.push("delete_block", target: @target) |> hide_dropdown("##{@dropdown_id}")}
          >
            <.icon name="hero-trash" /> {gettext("Delete")}
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

    assigns = assign(assigns, :valid?, valid?)

    ~H"""
    <div class="table-block-wrapper">
      <div class="table-info" phx-click="show_table_instructions" phx-target={@target}>
        <div class="icon">
          <span class="hero-table-cells"></span>
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
                <input type="hidden" name={"#{@block_data.name}[sort_table_row_ids][]"} value={table_row.index} />
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
                    form_id={@form_id}
                    publish
                  />
                </.inputs_for>
              </div>
              <div class="insert-row">
                <button
                  type="button"
                  class="tiny add-table-row"
                  phx-click="add_table_row"
                  phx-target={@target}
                >
                  {gettext("Add row")}
                </button>
              </div>
            </.inputs_for>
            <div class="add-row">
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
  attr :datasource_meta, :any, default: nil
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :available_identifiers, :any, default: []
  attr :block_identifiers, :any, default: []

  def datasource(assigns) do
    translated_module_datasource_type =
      Gettext.dgettext(
        Brando.Gettext,
        "datasource",
        to_string(assigns.module_datasource_type)
      )

    assigns =
      assign(
        assigns,
        :translated_module_datasource_type,
        translated_module_datasource_type
      )

    ~H"""
    <div class="block-datasource">
      <div class="datasource-info" phx-click="show_datasource_instructions" phx-target={@target}>
        <div class="icon">
          <.icon name="hero-circle-stack" />
        </div>
        <div class="info">
          <span class="datasource-label">
            {gettext("Datasource")} [{@translated_module_datasource_type}]<br />
            {@module_datasource_module_label} &rarr; {@module_datasource_query}
          </span>
        </div>
      </div>

      <%= if @module_datasource_type == :selection do %>
        <Content.modal title={gettext("Select entries")} id={"select-entries-#{@uid}"} remember_scroll_position narrow>
          <h2 class="titlecase">{gettext("Available entries")}</h2>
          <Entries.block_identifier
            :for={identifier <- @available_identifiers}
            :key={identifier.id}
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
                    data-sortable-filter
                  >
                    <.icon name="hero-x-circle" />
                  </button>
                </:delete>
                <:meta :let={identifier}>
                  <.identifier_meta
                    :if={@datasource_meta != []}
                    datasource_meta={@datasource_meta}
                    identifier={identifier}
                    block_data={@block_data}
                  />
                </:meta>
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
            {gettext("Select entries")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end

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

    assigns =
      assigns
      |> assign(:key, key)
      |> assign(:meta_form, meta_form)

    ~H"""
    <div :if={@datasource_meta != []} class="identifier-meta">
      <div class="meta-fields">
        <div :for={field <- @datasource_meta} :key={field.key} class="meta-field">
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
    </div>
    """
  end

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

    var_assigns =
      case block_form[:vars] do
        nil ->
          %{}

        vars_field ->
          block_cs = vars_field.form.source
          vars = Changeset.get_assoc(block_cs, :vars, :struct)

          Map.new(vars, fn var ->
            value =
              case var.type do
                :boolean -> var.value_boolean
                :image -> var.image
                :file -> var.file
                :link -> var
                _ -> var.value
              end

            {String.to_existing_atom(var.key), value}
          end)
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
      target: assigns[:target],
      target_ref: assigns[:target_ref],
      form_id: assigns[:form_id]
    }

    base = %{
      render_context: :admin,
      block: block,
      refs: %{},
      entries: [],
      content: "",
      entry: assigns[:entry],
      _heex_ctx: heex_ctx
    }

    Map.merge(base, var_assigns)
  end
end
