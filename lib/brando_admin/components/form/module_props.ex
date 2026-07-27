defmodule BrandoAdmin.Components.Form.ModuleProps do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  use Gettext, backend: Brando.Gettext

  alias Brando.Datasource
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.VarLayout
  alias BrandoAdmin.Components.Form.ModuleProps.RefBlockForm

  @ref_types [
    %{value: "text", label: "Text", description: "Rich, editable body content"},
    %{value: "header", label: "Header", description: "A semantic heading"},
    %{value: "picture", label: "Picture", description: "A configured responsive image"},
    %{value: "gallery", label: "Gallery", description: "An image or video collection"},
    %{value: "video", label: "Video", description: "Hosted or remote video"},
    %{value: "media", label: "Media", description: "Let editors choose the media type"},
    %{value: "file", label: "File", description: "A downloadable file"},
    %{value: "html", label: "HTML", description: "Editable HTML content"},
    %{value: "svg", label: "SVG", description: "Inline vector markup"},
    %{value: "markdown", label: "Markdown", description: "Markdown content"},
    %{value: "map", label: "Map", description: "An embedded map"},
    %{value: "comment", label: "Comment", description: "An editor-only note"}
  ]

  @var_types [
    %{value: "string", label: "String", description: "A short line of text"},
    %{value: "text", label: "Text", description: "Longer plain text"},
    %{value: "html", label: "Rich text", description: "Formatted rich text"},
    %{value: "boolean", label: "Boolean", description: "An on/off choice"},
    %{value: "select", label: "Select", description: "A choice from predefined options"},
    %{value: "link", label: "Link", description: "A URL or content link"},
    %{value: "datetime", label: "Date & time", description: "A date and time value"},
    %{value: "color", label: "Color", description: "A palette or custom color"},
    %{value: "image", label: "Image", description: "A reusable image value"},
    %{value: "video", label: "Video", description: "A reusable video value"},
    %{value: "file", label: "File", description: "A reusable file value"},
    %{value: "gallery", label: "Gallery", description: "A reusable media collection"}
  ]

  @format_options [
    %{label: "Original", value: "original"},
    %{label: "jpg", value: "jpg"},
    %{label: "png", value: "png"},
    %{label: "webp", value: "webp"},
    %{label: "avif", value: "avif"}
  ]

  # prop form, :form, required: true
  # prop key, :string, default: "default"
  # prop entry_form, :boolean, default: false

  # prop create_ref, :event, required: true
  # prop create_var, :event, required: true
  # data open_col_vars, :list

  def mount(socket) do
    {:ok,
     socket
     |> assign(open_col_vars: [], datasource: false)
     |> assign_new(:ref_types, fn -> @ref_types end)
     |> assign_new(:var_types, fn -> @var_types end)
     |> assign_new(:entry_form, fn -> false end)
     |> assign_new(:key, fn -> "default" end)
     |> assign_new(:open_item_modal, fn -> nil end)
     |> assign_new(:active_tab, fn -> :overview end)
     |> assign_available_datasources()
     |> assign_available_parents()
     |> assign_available_table_templates()}
  end

  def update(assigns, socket) do
    datasource = Phoenix.HTML.Form.normalize_value("checkbox", assigns.form[:datasource].value)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:datasource, datasource)
     |> assign_available_queries()}
  end

  def assign_available_parents(socket) do
    {:ok, available_parents} = Brando.Content.list_modules(%{filter: %{parent_id: nil}})
    assign(socket, :available_parents, available_parents)
  end

  def assign_available_table_templates(socket) do
    {:ok, available_table_templates} = Brando.Content.list_table_templates(%{order: "asc name"})

    available_table_templates =
      Enum.map(available_table_templates, &%{label: &1.name, value: &1.id})

    assign_new(socket, :available_table_templates, fn -> available_table_templates end)
  end

  def render(assigns) do
    ~H"""
    <div class="module-props">
      <%!-- Each panel mirrors a tab in the editor's tab bar. They all stay
            rendered — see the note at the call site — so `is-active` is purely
            a CSS concern. --%>
      <section class={["module-panel", @active_tab == :overview && "is-active"]} data-tab="overview">
        <div class="properties shaded">
          <div class="inner">
            <section class="module-settings">
              <div class="module-section-heading">
                <span>{gettext("Module details")}</span>
                <small>{gettext("How this module appears to editors")}</small>
              </div>

              <Input.i18n_text field={@form[:name]} label={gettext("Name")} />
              <Input.i18n_text field={@form[:namespace]} label={gettext("Namespace")} />
              <Input.i18n_textarea field={@form[:help_text]} label={gettext("Help text")} />
              <Input.text field={@form[:class]} label={gettext("CSS class")} />
            </section>

            <section class="module-settings">
              <div class="module-section-heading">
                <span>{gettext("Behavior")}</span>
                <small>{gettext("Rendering, nesting and editor presentation")}</small>
              </div>

              <Input.radios
                field={@form[:type]}
                label={gettext("Template language")}
                opts={[
                  options: [
                    %{label: gettext("Liquid"), value: :liquid},
                    %{label: gettext("Heex"), value: :heex}
                  ]
                ]}
              />
              <Input.toggle field={@form[:multi]} label={gettext("Allow multiple entries")} />

              <.live_component
                module={Input.Select}
                id={"#{@form.id}-color"}
                field={@form[:color]}
                label={gettext("Editor color")}
                inline={true}
                opts={[
                  options: [
                    %{label: gettext("Blue"), value: :blue},
                    %{label: gettext("Emerald"), value: :emerald},
                    %{label: gettext("Peach"), value: :peach},
                    %{label: gettext("Pink"), value: :pink}
                  ]
                ]}
              />

              <.live_component
                module={Input.Select}
                id={"#{@form.id}-parent_id"}
                field={@form[:parent_id]}
                label={gettext("Parent module")}
                opts={[options: @available_parents]}
              />

              <.live_component
                module={Input.Select}
                id={"#{@form.id}-table_template_id"}
                field={@form[:table_template_id]}
                label={gettext("Table template")}
                inline={true}
                opts={[options: @available_table_templates]}
              />

              <button
                :if={!@entry_form}
                phx-click={show_modal("##{@form.id}-#{@key}-icon")}
                class="secondary module-icon-button"
                type="button"
              >
                <.icon name="hero-photo" />
                {gettext("Edit module icon")}
              </button>
            </section>
          </div>
        </div>

        <Content.modal title={gettext("Edit module icon")} id={"#{@form.id}-#{@key}-icon"}>
          <Input.code id={"#{@form.id}-svg"} field={@form[:svg]} label={gettext("SVG")} />
          <:footer>
            <button type="button" class="primary" phx-click={hide_modal("##{@form.id}-#{@key}-icon")}>
              {gettext("Done")}
            </button>
          </:footer>
        </Content.modal>
      </section>

      <section
        class={["module-panel", @active_tab == :references && "is-active"]}
        data-tab="references"
      >
        <div class="properties shaded">
          <div class="inner">
            <Content.modal title={gettext("Add reference")} id={"#{@form.id}-#{@key}-create-ref"} medium>
              <p class="module-picker-intro">
                {gettext("References place editable content and media directly in the module template.")}
              </p>
              <.type_buttons
                types={@ref_types}
                on_click={@create_ref}
                hide_modal_id={"##{@form.id}-#{@key}-create-ref"}
              />
            </Content.modal>

            <section class="module-collection refs">
              <header class="module-collection-header">
                <div>
                  <div class="module-collection-title">
                    <h2>{gettext("References")}</h2>
                    <span class="module-count">{Enum.count(@form[:refs].value || [])}</span>
                  </div>
                  <p>{gettext("Editable content and media used by the template.")}</p>
                </div>
              </header>

              <div :if={Enum.empty?(@form[:refs].value || [])} class="module-empty-state">
                <.icon name="hero-cube-transparent" />
                <p>{gettext("No references yet")}</p>
                <span>{gettext("Add one, then insert it in the template with the ref tag.")}</span>
              </div>

              <ul
                id={"#{@form.id}-refs-#{@key}-list"}
                phx-hook="Brando.SortableAssocs"
                data-sortable-id={"sortable-refs#{@entry_form && "-entry-form" || ""}"}
                data-sortable-selector=".ref"
                data-sortable-handle=".sort-handle"
                data-sortable-dispatch-event="true"
              >
                <.inputs_for :let={ref} field={@form[:refs]} skip_hidden>
                  <li class="ref module-item draggable" data-id={ref.index}>
                    <Input.input type={:hidden} field={ref[:id]} />
                    <Input.input type={:hidden} field={ref[:_persistent_id]} value={ref.index} />
                    <input type="hidden" name={"#{@form.name}[sort_ref_ids][]"} value={ref.index} />

                    <button
                      class="module-drag-handle sort-handle"
                      type="button"
                      aria-label={gettext("Reorder reference")}
                      title={gettext("Drag to reorder")}
                    >
                      <%!-- Dot grid rather than a heroicon: none of them read as
                            "grab me", and this matches the layout canvas's chips. --%>
                      <span class="drag-grip" aria-hidden="true"></span>
                    </button>

                    <Form.inputs_for_block :let={ref_data} field={ref[:data]} skip_hidden>
                      <button
                        class="module-item-summary"
                        type="button"
                        phx-click={show_modal("##{@form.id}-#{@key}-ref-#{ref.index}")}
                        aria-label={gettext("Edit reference %{name}", name: ref[:name].value)}
                      >
                        <span class="module-item-type">{ref_data[:type].value}</span>
                        <span class="module-item-identity">
                          <code>%&lcub;{ref[:name].value}&rcub;</code>
                          <small>{ref[:description].value || gettext("No description")}</small>
                        </span>
                      </button>

                      <div class="actions">
                        <button
                          class="module-item-action"
                          type="button"
                          phx-click={@duplicate_ref}
                          phx-value-index={ref.index}
                          aria-label={gettext("Duplicate reference %{name}", name: ref[:name].value)}
                          title={gettext("Duplicate")}
                        >
                          <.icon name="hero-document-duplicate" />
                        </button>
                        <button
                          class="module-item-action module-danger"
                          type="button"
                          phx-click={JS.dispatch("change")}
                          phx-confirm={gettext("Delete reference %{name}?", name: ref[:name].value)}
                          name={"#{@form.name}[drop_ref_ids][]"}
                          value={ref.index}
                          aria-label={gettext("Delete reference %{name}", name: ref[:name].value)}
                          title={gettext("Delete")}
                        >
                          <.icon name="hero-x-mark" />
                        </button>
                      </div>
                    </Form.inputs_for_block>

                    <Content.modal
                      title={gettext("Edit reference")}
                      id={"#{@form.id}-#{@key}-ref-#{ref.index}"}
                      show={@open_item_modal == :ref && ref.index == 0}
                      close={close_item_modal("##{@form.id}-#{@key}-ref-#{ref.index}")}
                      wide
                    >
                      <Form.inputs_for_block :let={ref_data} field={ref[:data]}>
                        <Input.input type={:hidden} field={ref_data[:type]} />
                        <div class="panels">
                          <div class="panel">
                            <div class="module-modal-heading">
                              <span class="module-item-type">{ref_data[:type].value}</span>
                              <h2>{gettext("Content defaults")}</h2>
                            </div>
                            <RefBlockForm.block_form
                              type={ref_data[:type].value}
                              ref_data={ref_data}
                              form_id={@form.id}
                              key={@key}
                              ref_name={ref[:name].value}
                            />
                          </div>

                          <div class="panel">
                            <div class="module-modal-heading">
                              <h2>{gettext("Reference settings")}</h2>
                            </div>
                            <Input.text
                              field={ref[:name]}
                              label={gettext("Template name")}
                              instructions={gettext("Reference it from the template with the ref tag.")}
                              monospace
                            />
                            <Input.textarea field={ref[:description]} label={gettext("Editor description")} />
                            <Input.input
                              type={:hidden}
                              field={ref[:uid]}
                              value={ref[:uid].value || Brando.Utils.generate_uid()}
                            />
                          </div>
                        </div>
                        <RefBlockForm.block_form_extras
                          type={ref_data[:type].value}
                          block_data={ref_data}
                        />
                      </Form.inputs_for_block>
                      <:footer>
                        <button
                          type="button"
                          class="primary"
                          phx-click={close_item_modal("##{@form.id}-#{@key}-ref-#{ref.index}")}
                        >
                          {gettext("Done")}
                        </button>
                      </:footer>
                    </Content.modal>
                  </li>
                </.inputs_for>
                <input type="hidden" name={"#{@form.name}[drop_ref_ids][]"} />
              </ul>

              <div class="module-collection-foot">
                <button
                  phx-click={show_modal("##{@form.id}-#{@key}-create-ref")}
                  type="button"
                  class="module-add-button"
                  aria-label={gettext("Add reference")}
                >
                  <.icon name="hero-plus" />
                  {gettext("Add reference")}
                </button>
              </div>
            </section>
          </div>
        </div>
      </section>

      <section class={["module-panel", @active_tab == :variables && "is-active"]} data-tab="variables">
        <Content.modal title={gettext("Add variable")} id={"#{@form.id}-#{@key}-create-var"} medium>
          <p class="module-picker-intro">
            {gettext("Variables expose reusable values to the template and the block editor.")}
          </p>
          <.type_buttons
            types={@var_types}
            on_click={@create_var}
            hide_modal_id={"##{@form.id}-#{@key}-create-var"}
          />
        </Content.modal>

        <%!-- The layout canvas *is* the variable list: its chips open these
              modals and carry the duplicate/delete controls. What stays here is
              only what has to be part of the form — the per-var edit modal, and
              the hidden inputs that let `cast_assoc` match each row. --%>
        <div class="module-var-forms">
          <.inputs_for :let={var} field={@form[:vars]} skip_hidden>
            <Content.modal
              title={gettext("Edit variable")}
              id={"#{@form.id}-#{@key}-var-#{var.index}"}
              show={@open_item_modal == :var && var.index == 0}
              close={close_item_modal("##{@form.id}-#{@key}-var-#{var.index}")}
              wide
            >
              <.live_component
                module={RenderVar}
                id={"#{@form.id}-#{@key}-render-var-#{var.index}"}
                var={var}
                render={:all}
                target={@myself}
                initially_open
                edit
              />
              <:footer>
                <button
                  type="button"
                  class="primary"
                  phx-click={close_item_modal("##{@form.id}-#{@key}-var-#{var.index}")}
                >
                  {gettext("Done")}
                </button>
              </:footer>
            </Content.modal>

            <Input.input type={:hidden} field={var[:id]} />
            <Input.input type={:hidden} field={var[:_persistent_id]} value={var.index} />
            <input type="hidden" name={"#{@form.name}[sort_var_ids][]"} value={var.index} />
          </.inputs_for>
          <input type="hidden" name={"#{@form.name}[drop_var_ids][]"} />
        </div>

        <div :if={Enum.empty?(@form[:vars].value || [])} class="module-empty-state">
          <.icon name="hero-variable" />
          <p>{gettext("No variables yet")}</p>
          <span>{gettext("Add one, then reference its key in the template.")}</span>
          <button
            phx-click={show_modal("##{@form.id}-#{@key}-create-var")}
            type="button"
            class="secondary"
          >
            <.icon name="hero-plus" />
            {gettext("Add variable")}
          </button>
        </div>

        <.live_component
          :if={@form[:vars].value not in [nil, []]}
          module={VarLayout}
          id={"#{@form.id}-#{@key}-var-layout"}
          form={@form}
          form_key={@key}
        />
      </section>

      <section
        class={["module-panel", @active_tab == :datasource && "is-active"]}
        data-tab="datasource"
      >
        <div class="properties shaded">
          <div class="inner">
            <section class="module-settings datasource">
              <div class="module-section-heading">
                <span>{gettext("Datasource")}</span>
                <small>{gettext("Optional dynamic content for this module")}</small>
              </div>
              <Input.toggle field={@form[:datasource]} label={gettext("Datasource")} />

              <%= if @datasource do %>
                <.live_component
                  module={Input.Select}
                  id={"#{@form.id}-datasource-module"}
                  field={@form[:datasource_module]}
                  opts={[options: @available_sources]}
                />

                <Input.radios
                  field={@form[:datasource_type]}
                  label={gettext("Type")}
                  opts={[
                    options: [
                      %{label: gettext("List"), value: :list},
                      %{label: gettext("Single"), value: :single},
                      %{label: gettext("Selection"), value: :selection}
                    ]
                  ]}
                />

                <.live_component
                  if={@form[:datasource_module].value}
                  module={Input.Select}
                  id={"#{@form.id}-datasource-query"}
                  field={@form[:datasource_query]}
                  opts={[options: @available_queries]}
                />
              <% end %>
            </section>
          </div>
        </div>
      </section>
    </div>
    """
  end

  def assign_available_datasources(socket) do
    {:ok, available_sources} = Datasource.list_datasources()

    available_sources =
      Enum.map(
        available_sources,
        fn module_bin ->
          module = Module.concat(List.wrap(module_bin))
          domain = module.__naming__().domain
          schema = module.__naming__().schema

          gettext_module = module.__modules__().gettext
          gettext_domain = String.downcase("#{domain}_#{schema}")
          msgid = Brando.Utils.humanize(module.__naming__().singular, :downcase)

          %{
            label: String.capitalize(Gettext.dgettext(gettext_module, gettext_domain, msgid)),
            value: module_bin
          }
        end
      )

    assign(socket, :available_sources, available_sources)
  end

  def assign_available_queries(%{assigns: %{form: form}} = socket) do
    module = form[:datasource_module].value
    type = form[:datasource_type].value
    type = (is_binary(type) && String.to_existing_atom(type)) || type

    if module && type do
      {:ok, all_available_queries} = Datasource.list_datasource_keys(module)

      all_available_queries_by_type = Map.get(all_available_queries, type, [])

      available_queries_as_options =
        Enum.map(
          all_available_queries_by_type,
          &%{label: to_string(&1), value: &1}
        )

      assign(socket, :available_queries, available_queries_as_options)
    else
      assign(socket, :available_queries, [])
    end
  end

  def handle_event("focus", %{"field" => _field_name}, socket) do
    {:noreply, socket}
  end

  def handle_event("toggle_col_var", %{"id" => col_name}, %{assigns: %{open_col_vars: open_col_vars}} = socket) do
    updated_open_col_vars =
      if col_name in open_col_vars do
        Enum.reject(open_col_vars, &(&1 == col_name))
      else
        [col_name | open_col_vars]
      end

    {:noreply, assign(socket, :open_col_vars, updated_open_col_vars)}
  end

  def handle_event("add_select_var_option", %{"var_key" => var_key}, socket) do
    send(self(), {:add_select_var_option, var_key})
    {:noreply, socket}
  end

  def handle_event("del_select_var_option", params, socket) do
    send(self(), {:del_select_var_option, params})
    {:noreply, socket}
  end

  # --- Function components ---

  attr :types, :list, required: true
  attr :on_click, :any, required: true
  attr :hide_modal_id, :string, default: nil

  defp type_buttons(assigns) do
    ~H"""
    <div class="module-type-picker">
      <button
        :for={type <- @types}
        :key={type.value}
        type="button"
        phx-click={build_click_action(@on_click, @hide_modal_id)}
        phx-value-type={type.value}
        class="module-type-option"
      >
        <span>{type.label}</span>
        <small>{type.description}</small>
        <.icon name="hero-arrow-right" />
      </button>
    </div>
    """
  end

  defp build_click_action(on_click, nil), do: on_click
  defp build_click_action(on_click, hide_id), do: on_click |> hide_modal(hide_id)

  defp close_item_modal(selector) do
    JS.push("close_item_modal")
    |> hide_modal(selector)
  end

  attr :field, :any, required: true

  def format_checkboxes(assigns) do
    assigns = assign(assigns, :options, @format_options)

    ~H"""
    <Form.array_inputs_from_data
      :let={%{id: array_id, value: array_value, label: array_label, name: array_name, checked: checked}}
      field={@field}
      options={@options}
    >
      <div class="field-wrapper compact">
        <div class="check-wrapper small">
          <input type="checkbox" id={array_id} name={array_name} value={array_value} checked={checked} />
          <label class="control-label small" for={array_id}>{array_label}</label>
        </div>
      </div>
    </Form.array_inputs_from_data>
    """
  end
end
