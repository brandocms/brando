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
  alias Brando.Content.Block, as: ContentBlock
  alias Brando.Content.Var.Layout
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

  # Without these two, a block referencing a deleted container/fragment falls
  # through to `render(%{type: :container})` / `render(%{type: :fragment})`,
  # which read `@container` / `@palette_options` / `@fragment`. Those are now
  # always assigned (see `Block.maybe_assign_container/1`), but rendering the
  # normal chrome for a target that no longer exists is still wrong — say so,
  # and offer the same escape hatch as `module_not_found`.
  def render(%{container_not_found: true} = assigns) do
    ~H"""
    <div class="alert danger text-mono">
      <div>
        Missing container — #{inspect(assigns.container_id)}.<br /><br />
        If this is a mistake, you can hopefully undelete the container.<br /><br />
        If you're sure the container is gone, you can
        <button type="button" phx-click="delete_block" phx-target={@myself}>
          delete this block.
        </button>
      </div>
    </div>
    """
  end

  def render(%{fragment_not_found: true} = assigns) do
    ~H"""
    <div class="alert danger text-mono">
      <div>
        Missing fragment — #{inspect(assigns.fragment_id)}.<br /><br />
        If this is a mistake, you can hopefully undelete the fragment.<br /><br />
        If you're sure the fragment is gone, you can
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
        liquid_splits={@liquid_splits}
        target={@myself}
        target_ref={{Block, @id}}
        form_id={@form_id}
        entry={@entry}
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
            :for={{child_uid, child_block_form, list_index} <- Block.child_shells(@block_list, @children_forms)}
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
              module_set={@module_set}
              form={child_block_form}
              form_id={@form_id}
              entry={@entry}
              current_user_id={@current_user_id}
              belongs_to={:multi}
              paste_multi_module_id={@paste_multi_module_id}
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
        liquid_splits={@liquid_splits}
        entry={@entry}
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
        paste_multi_module_id={@paste_multi_module_id}
        hidden_block_fields={@hidden_block_fields}
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
        liquid_splits={@liquid_splits}
        entry={@entry}
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
            :for={{child_uid, child_block_form, list_index} <- Block.child_shells(@block_list, @children_forms)}
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
    ~H"""
    <div class="block-unknown-type">
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
  attr :module_picker_id, :string, default: nil
  attr :config_open, :string, default: nil
  attr :fragment, :any, default: nil
  attr :fragments, :list, default: []
  attr :paste_multi_module_id, :any, default: nil
  attr :hidden_block_fields, :list, default: []

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
  attr :paste_multi_module_id, :any, default: nil
  attr :paste_context, :any, default: :root
  attr :form_id, :any, default: nil
  attr :module_type, :atom, default: :liquid
  attr :heex_compiled_module, :any, default: nil
  attr :entry, :any, default: nil
  attr :hidden_block_fields, :list, default: []
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

              <.module_config
                open={@config_open == @uid}
                uid={@uid}
                block_form={block_form}
                target={@target}
                form_id={@form_id}
              />
              <.module_content
                config_open={@config_open}
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
                entry={@entry}
              />
            </.inputs_for>
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
            />
            <.module_content
              config_open={@config_open}
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
              entry={@entry}
            />
          <% end %>
        </.form>
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

    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars
          vars={@block_form[:vars]}
          uid={@uid}
          target={@target}
          form_id={@form_id}
          current_user_id={@block_form[:creator_id].value}
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
        <.vars
          vars={@block_form[:vars]}
          uid={@uid}
          target={@target}
          form_id={@form_id}
          current_user_id={@block_form[:creator_id].value}
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
      />
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
          />
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
        <button type="button" class="primary" phx-click="close_block_config" phx-target={@target}>
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

  `liquid_strip_logic/1` removes `{% if %}` / `{% for %}` / `{% hide %}` regions
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
                config_open={@config_open}
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
  attr :type, :any
  attr :block_type, :any
  attr :is_datasource?, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :ref_form, :any, default: nil
  attr :datasource, :any
  attr :bg_color, :string, default: nil
  attr :uid, :any
  attr :config_open, :string, default: nil

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
        <%= if @config do %>
          {render_slot(@config)}
        <% end %>
      </div>
      <Content.modal
        :if={@config_open?}
        title={gettext("Configure")}
        id={"block-#{@uid}_config"}
        show={true}
        close={JS.push("close_block_config", target: @target)}
        wide={@wide_config}
      >
        <%= if @config do %>
          {render_slot(@config)}
        <% end %>
        <:footer>
          <button type="button" class="primary" phx-click="close_block_config" phx-target={@target}>
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
        <.icon name="hero-plus" />
      </button>
      <button
        :if={@paste_ctx}
        class="block-paste"
        data-paste-ctx={@paste_ctx}
        type="button"
        phx-click={@paste_event}
        phx-target={@paste_target}
      >
        <.icon name="hero-clipboard-document-check" />
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
          <span class="hero-variable-mini"></span>
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
            on_change={fn params -> send_update(@target, params) end}
            form_id={@form_id}
            current_user_id={@current_user_id}
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
  @carried_var_fields ContentBlock.carried_var_attrs()

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
        <input type="hidden" name={option[:label].name} value={option[:label].value} />
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
        >
          <.icon name="hero-question-mark-circle" />
        </div>
        <button
          :if={@is_ref? && @config}
          type="button"
          class="block-action config"
          phx-click="open_block_config"
          phx-value-uid={@uid}
          phx-target={@target}
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
      >
        <.icon name="hero-ellipsis-horizontal-circle" />
      </button>
      <ul class="block-action-dropdown-content hidden" id={@dropdown_id}>
        <li :if={@instructions}>
          <button type="button" phx-click="toggle_help" phx-target={@target}>
            <.icon name="hero-question-mark-circle" /> {gettext("Instructions")}
          </button>
        </li>
        <li :if={@config}>
          <button type="button" phx-click="open_block_config" phx-value-uid={@uid} phx-target={@target}>
            <.icon name="hero-cog-8-tooth" /> {gettext("Configure")}
          </button>
        </li>
        <li>
          <%!-- `handle_block_event/3` reads the uid off the component's own assigns, so
               the old `value: %{block_uid: @uid}` never reached anything. --%>
          <button type="button" phx-click="duplicate_block" phx-target={@target}>
            <.icon name="hero-document-duplicate" /> {gettext("Duplicate")}
          </button>
        </li>
        <li>
          <button type="button" phx-click="copy_block" phx-target={@target}>
            <.icon name="hero-clipboard-document" /> {gettext("Copy")}
          </button>
        </li>
        <li>
          <button type="button" phx-click="delete_block" phx-target={@target}>
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
            phx-click="assign_available_identifiers"
            phx-target={@target}
            data-ui-modal-show={"select-entries-#{@uid}"}
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
                :video -> var.video
                :gallery -> var.gallery
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
