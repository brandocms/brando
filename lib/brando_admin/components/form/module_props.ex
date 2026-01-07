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
  alias BrandoAdmin.Components.Form.ModuleProps.RefBlockForm

  @ref_types [
    %{value: "text", label: "Text"},
    %{value: "header", label: "Header"},
    %{value: "picture", label: "Picture"},
    %{value: "gallery", label: "Gallery"},
    %{value: "video", label: "Video"},
    %{value: "media", label: "Media"},
    %{value: "html", label: "HTML"},
    %{value: "svg", label: "SVG"},
    %{value: "markdown", label: "Markdown"},
    %{value: "map", label: "Map"},
    %{value: "comment", label: "Comment"}
  ]

  @var_types [
    %{value: "text", label: "Rich text"},
    %{value: "string", label: "String"},
    %{value: "image", label: "Image"},
    %{value: "file", label: "File"},
    %{value: "boolean", label: "Boolean"},
    %{value: "select", label: "Select"},
    %{value: "link", label: "Link"},
    %{value: "datetime", label: "Datetime"},
    %{value: "color", label: "Color"},
    %{value: "html", label: "Html"}
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
  # prop delete_ref, :event, required: true
  # prop create_var, :event, required: true
  # prop delete_var, :event, required: true
  # data open_col_vars, :list

  def mount(socket) do
    {:ok,
     socket
     |> assign(open_col_vars: [], datasource: false)
     |> assign_new(:ref_types, fn -> @ref_types end)
     |> assign_new(:var_types, fn -> @var_types end)
     |> assign_new(:entry_form, fn -> false end)
     |> assign_new(:key, fn -> "default" end)
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
    <div class="properties shaded">
      <div class="inner">
        <Input.radios
          field={@form[:type]}
          label={gettext("Type")}
          opts={[
            options: [
              %{label: gettext("Liquid"), value: :liquid},
              %{label: gettext("Heex"), value: :heex}
            ]
          ]}
        />
        <Input.i18n_text field={@form[:name]} label={gettext("Name")} />
        <Input.i18n_text field={@form[:namespace]} label={gettext("Namespace")} />
        <Input.i18n_textarea field={@form[:help_text]} label={gettext("Help text")} />
        <Input.text field={@form[:class]} label={gettext("Class")} />
        <Input.toggle field={@form[:multi]} label={gettext("Multi")} />

        <.live_component
          module={Input.Select}
          id={"#{@form.id}-color"}
          field={@form[:color]}
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
          opts={[options: @available_parents]}
        />

        <.live_component
          module={Input.Select}
          id={"#{@form.id}-table_template_id"}
          field={@form[:table_template_id]}
          inline={true}
          opts={[options: @available_table_templates]}
        />

        <%= if !@entry_form do %>
          <div class="button-group">
            <button phx-click={show_modal("##{@form.id}-#{@key}-icon")} class="secondary" type="button">
              Edit icon
            </button>
          </div>
        <% end %>

        <Content.modal title="Edit icon" id={"#{@form.id}-#{@key}-icon"}>
          <Input.code id={"#{@form.id}-svg"} field={@form[:svg]} label={gettext("SVG")} />
        </Content.modal>

        <Content.modal title="Create ref" id={"#{@form.id}-#{@key}-create-ref"} narrow>
          <.type_buttons
            types={@ref_types}
            on_click={@create_ref}
            hide_modal_id={"##{@form.id}-#{@key}-create-ref"}
            show_modal_id={"##{@form.id}-#{@key}-ref-0"}
          />
        </Content.modal>

        <div class="refs">
          <h2>
            <div class="header-spread">REFs</div>
            <button phx-click={show_modal("##{@form.id}-#{@key}-create-ref")} type="button" class="circle">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" />
              </svg>
            </button>
          </h2>

          <ul>
            <input type="hidden" name={@form[:refs].name} value="" />
            <.inputs_for :let={ref} field={@form[:refs]}>
              <li class="padded">
                <Form.inputs_for_block :let={ref_data} field={ref[:data]}>
                  <div>
                    <span class="text-mono">{ref_data[:type].value}</span>
                    <span class="text-mono">- %&lcub;{ref[:name].value}&rcub;</span>
                  </div>

                  <div class="actions">
                    <button class="tiny" type="button" phx-click={show_modal("##{@form.id}-#{@key}-ref-#{ref.index}")}>
                      <.icon name="hero-pencil" />
                    </button>
                    <button class="tiny" type="button" phx-click={@duplicate_ref} phx-value-id={ref[:name].value}>
                      <.icon name="hero-document-duplicate" />
                    </button>
                    <button class="tiny" type="button" phx-click={@delete_ref} phx-value-id={ref[:name].value}>
                      <.icon name="hero-x-mark" />
                    </button>
                  </div>
                </Form.inputs_for_block>

                <Content.modal title="Edit ref" id={"#{@form.id}-#{@key}-ref-#{ref.index}"} wide>
                  <div class="panels">
                    <Form.inputs_for_block :let={ref_data} field={ref[:data]}>
                      <Input.input type={:hidden} field={ref_data[:type]} />
                      <div class="panel">
                        <h2 class="titlecase">Block template</h2>
                        <RefBlockForm.block_form
                          type={ref_data[:type].value}
                          ref_data={ref_data}
                          form_id={@form.id}
                          key={@key}
                          ref_name={ref[:name].value}
                        />
                      </div>

                      <div class="panel">
                        <h2 class="titlecase">Ref config — {ref_data[:type].value}</h2>
                        <Input.text field={ref[:name]} label={gettext("Name")} />
                        <Input.text field={ref[:description]} label={gettext("Description")} />
                        <Input.input type={:hidden} field={ref[:uid]} value={ref[:uid].value || Brando.Utils.generate_uid()} />
                      </div>
                    </Form.inputs_for_block>
                  </div>
                </Content.modal>
              </li>
            </.inputs_for>
          </ul>
        </div>

        <Content.modal title={gettext("Create var")} id={"#{@form.id}-#{@key}-create-var"} narrow>
          <.type_buttons
            types={@var_types}
            on_click={@create_var}
            hide_modal_id={"##{@form.id}-#{@key}-create-var"}
          />
        </Content.modal>

        <div class="vars">
          <h2>
            <div class="header-spread">Vars</div>
            <button phx-click={show_modal("##{@form.id}-#{@key}-create-var")} type="button" class="circle">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="18" height="18">
                <path fill="none" d="M0 0h24v24H0z" /><path d="M11 11V5h2v6h6v2h-6v6h-2v-6H5v-2z" />
              </svg>
            </button>
          </h2>
          <ul
            id={"#{@form.id}-vars-#{@key}-list"}
            phx-hook="Brando.SortableAssocs"
            data-sortable-id={"sortable-vars#{@entry_form && "-entry-form" || ""}"}
            data-sortable-selector=".var"
            data-sortable-handle=".sort-handle"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={var} field={@form[:vars]} skip_hidden>
              <Content.modal title={gettext("Edit var")} id={"#{@form.id}-#{@key}-var-#{var.index}"}>
                <.live_component
                  module={RenderVar}
                  id={"#{@form.id}-#{@key}-render-var-#{var.index}"}
                  var={var}
                  render={:all}
                  target={@myself}
                  edit
                />
                <!-- ^- had publish -->
              </Content.modal>
              <li class="var padded sort-handle draggable" data-id={var.index}>
                <Input.input type={:hidden} field={var[:id]} />
                <Input.input type={:hidden} field={var[:_persistent_id]} value={var.index} />
                <input type="hidden" name={"#{@form.name}[sort_var_ids][]"} value={var.index} />

                <span class="text-mono">
                  {var[:type].value} - &lcub;&lcub; {var[:key].value} &rcub;&rcub;
                </span>
                <div class="actions">
                  <button class="tiny" type="button" phx-click={show_modal("##{@form.id}-#{@key}-var-#{var.index}")}>
                    <.icon name="hero-pencil" />
                  </button>
                  <button class="tiny" type="button" phx-click={@duplicate_var} phx-value-id={var[:key].value}>
                    <.icon name="hero-document-duplicate" />
                  </button>
                  <button
                    class="tiny"
                    type="button"
                    phx-click={JS.dispatch("change")}
                    name={"#{@form.name}[drop_var_ids][]"}
                    value={var.index}
                  >
                    <.icon name="hero-x-mark" />
                  </button>
                </div>
              </li>
            </.inputs_for>
            <input type="hidden" name={"#{@form.name}[drop_var_ids][]"} />
          </ul>
        </div>

        <div class="datasource">
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
        </div>
      </div>
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
  attr :show_modal_id, :string, default: nil

  defp type_buttons(assigns) do
    ~H"""
    <div class="button-group-vertical">
      <button
        :for={%{value: value, label: label} <- @types}
        type="button"
        phx-click={build_click_action(@on_click, @hide_modal_id, @show_modal_id)}
        phx-value-type={value}
        class="secondary"
      >
        {label}
      </button>
    </div>
    """
  end

  defp build_click_action(on_click, nil, nil), do: on_click
  defp build_click_action(on_click, hide_id, nil), do: on_click |> hide_modal(hide_id)
  defp build_click_action(on_click, nil, show_id), do: on_click |> show_modal(show_id)

  defp build_click_action(on_click, hide_id, show_id),
    do: on_click |> hide_modal(hide_id) |> show_modal(show_id)

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
