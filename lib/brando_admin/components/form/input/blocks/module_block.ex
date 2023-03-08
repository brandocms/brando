defmodule BrandoAdmin.Components.Form.Input.Blocks.ModuleBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Brando.Blueprint.Identifier
  alias Brando.Villain
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Entries
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop block, :any
  # prop base_form, :any
  # prop index, :any
  # prop block_count, :integer
  # prop uploads, :any
  # prop data_field, :atom
  # prop belongs_to, :string

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data splits, :list
  # data block_data, :map
  # data module_name, :string
  # data module_class, :string
  # data module_code, :string
  # data entry_template, :any
  # data module_multi, :boolean
  # data refs, :list
  # data important_vars, :list
  # data uid, :string
  # data module_not_found, :boolean

  def v(form, field) do
    input_value(form, field)
  end

  defp get_module(id) do
    {:ok, modules} = Brando.Content.list_modules(%{cache: {:ttl, :infinite}})

    case Enum.find(modules, &(&1.id == id)) do
      nil -> nil
      module -> module
    end
  end

  def mount(socket) do
    {:ok, assign(socket, module_not_found: false, entry_template: nil)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:available_entries, fn -> [] end)
     |> assign_new(:indexed_available_entries, fn -> [] end)
     |> assign_new(:entry, fn -> Ecto.Changeset.apply_changes(assigns.base_form.source) end)
     |> assign_new(:module_id, fn -> v(assigns.block, :data).module_id end)
     |> assign_module_data()
     |> parse_module_code()
     |> assign_selected_entries()}
  end

  defp assign_module_data(%{assigns: %{block: block, module_id: module_id}} = socket) do
    case get_module(module_id) do
      nil ->
        assign(socket, :module_not_found, true)

      module ->
        block_data =
          block
          |> inputs_for(:data)
          |> List.first()

        refs_forms = Enum.with_index(inputs_for(block_data, :refs))
        refs = v(block_data, :refs) || []
        vars = v(block_data, :vars) || []
        uid = v(block, :uid)
        description = v(block, :description)

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
        |> assign(:uid, uid)
        |> assign(:description, description)
        |> assign(:block_data, block_data)
        |> assign(:indexed_vars, Enum.with_index(inputs_for_poly(block_data[:vars])))
        |> assign(:module_name, module.name)
        |> assign(:module_class, module.class)
        |> assign(:module_code, module.code)
        |> assign(:module_code, module.code)
        |> assign(:module_multi, input_value(block_data, :multi))
        |> assign(:module_datasource, module.datasource)
        |> assign(:module_datasource_module, module.datasource_module)
        |> assign(:module_datasource_module_label, module_datasource_module)
        |> assign(:module_datasource_type, module.datasource_type)
        |> assign(:module_datasource_query, module.datasource_query)
        |> assign(:datasource_selected_ids, input_value(block_data, :datasource_selected_ids))
        |> assign(:entry_template, module.entry_template)
        |> assign(:refs_forms, refs_forms)
        |> assign(:refs, refs)
        |> assign(:vars, vars)
        |> assign_new(:important_vars, fn -> Enum.filter(vars, &(&1.important == true)) end)
    end
  end

  def assign_available_entries(%{assigns: assigns} = socket) do
    module = assigns.module_datasource_module
    query = assigns.module_datasource_query
    entry = Ecto.Changeset.apply_changes(assigns.base_form.source)

    {:ok, available_entries} =
      Brando.Datasource.list_selection(
        module,
        query,
        Map.get(entry, :language),
        assigns.vars
      )

    socket
    |> assign(:available_entries, available_entries)
    |> assign(:indexed_available_entries, Enum.with_index(available_entries))
  end

  def assign_selected_entries(
        %{assigns: %{module_datasource_type: :selection} = assigns} = socket
      ) do
    module = assigns.module_datasource_module
    query = assigns.module_datasource_query
    ids = assigns.datasource_selected_ids

    assign_new(socket, :selected_entries, fn ->
      {:ok, selected_entries} = Brando.Datasource.get_selection(module, query, ids)
      {:ok, identifiers} = Identifier.identifiers_for(selected_entries)
      identifiers
    end)
  end

  def assign_selected_entries(socket), do: assign(socket, :selected_entries, [])

  def render(%{module_not_found: true} = assigns) do
    ~H"""
    <section class="alert danger">
      Module <code>#<%= @module_id %></code> is missing!<br><br>
    </section>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="module-block"
      data-block-index={@index}
      data-block-uid={@uid}>

      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
        is_datasource?={@module_datasource}>
        <:type><%= if @module_datasource do %><%= gettext "DATAMODULE" %><% else %><%= gettext "MODULE" %><% end %></:type>
        <:datasource>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg><%= @module_datasource_module_label %> | <%= @module_datasource_type %> | <%= @module_datasource_query %>
          <%= if @module_datasource_type == :selection do %>
            <Content.modal title={gettext("Select entries")} id={"select-entries-#{@uid}"} remember_scroll_position>
              <h2 class="titlecase"><%= gettext("Available entries") %></h2>
              <%= for {identifier, idx} <- @indexed_available_entries do %>
                <Entries.identifier
                  identifier={identifier}
                  select={JS.push("select_identifier", target: @myself)}
                  selected_identifiers={@selected_entries}
                  param={idx}
                />
              <% end %>
            </Content.modal>

            <div class="module-datasource-selected">
              <Form.array_inputs
                :let={%{value: array_value, name: array_name}}
                field={@block_data[:datasource_selected_ids]}>
                <input type="hidden" name={array_name} value={array_value} />
              </Form.array_inputs>

              <div
                id={"sortable-#{@uid}-identifiers"}
                class="selected-entries"
                phx-hook="Brando.Sortable"
                data-target={@myself}
                data-sortable-id={"sortable-#{@uid}-identifiers"}
                data-sortable-handle=".sort-handle"
                data-sortable-selector=".identifier">
                <%= for {identifier, idx} <- Enum.with_index(@selected_entries) do %>
                  <Entries.identifier
                    identifier={identifier}
                    remove={JS.push("remove_identifier", target: @myself)}
                    param={idx} />
                <% end %>
              </div>

              <button
                class="tiny select-button"
                type="button"
                phx-click={JS.push("select_entries", target: @myself) |> show_modal("#select-entries-#{@uid}")}>
                <%= gettext "Select entries" %>
              </button>
            </div>
          <% end %>
        </:datasource>
        <:description><%= if @description do %><strong><%= @description %></strong>&nbsp;| <% end %><%= @module_name %></:description>
        <:config>
          <div class="panels">
            <div class="panel">
              <Input.text field={@block[:description]} label={gettext "Block description"} instructions={gettext "Helpful for collapsed blocks"} />
              <%= for {var, index} <- @indexed_vars do %>
                <.live_component module={RenderVar} id={"block-#{@uid}-render-var-#{index}"} var={var} render={:only_regular} />
              <% end %>
            </div>
            <div class="panel">
              <h2 class="titlecase">Vars</h2>
              <%= for var <- @vars do %>
                <div class="var">
                  <div class="key"><%= var.key %></div>
                  <button type="button" class="tiny" phx-click={JS.push("reset_var", target: @myself)} phx-value-id={var.key}><%= gettext "Reset" %></button>
                </div>
              <% end %>

              <h2 class="titlecase">Refs</h2>
              <%= for ref <- @refs do %>
                <div class="ref">
                  <div class="key"><%= ref.name %></div>
                  <button type="button" class="tiny" phx-click={JS.push("reset_ref", target: @myself)} phx-value-id={ref.name}><%= gettext "Reset" %></button>
                </div>
              <% end %>
              <h2 class="titlecase"><%= gettext "Advanced" %></h2>
              <div class="button-group-vertical">
                <button type="button" class="secondary" phx-click={JS.push("fetch_missing_refs", target: @myself)}>
                  <%= gettext "Fetch missing refs" %>
                </button>
                <button type="button" class="secondary" phx-click={JS.push("reset_refs", target: @myself)}>
                  <%= gettext "Reset all block refs" %>
                </button>
                <button type="button" class="secondary" phx-click={JS.push("fetch_missing_vars", target: @myself)}>
                  <%= gettext "Fetch missing vars" %>
                </button>
                <button type="button" class="secondary" phx-click={JS.push("reset_vars", target: @myself)}>
                  <%= gettext "Reset all variables" %>
                </button>
              </div>
            </div>
          </div>
        </:config>

        <div b-editor-tpl={@module_class}>
          <%= unless Enum.empty?(@important_vars) do %>
            <div class="important-vars">
              <%= for {var, index} <- @indexed_vars do %>
                <.live_component module={RenderVar} id={"block-#{@uid}-render-var-blk-#{index}"} var={var} render={:only_important} />
              <% end %>
            </div>
          <% end %>
          <%= for split <- @splits do %>
            <%= case split do %>
              <% {:ref, ref} -> %>
                <Blocks.Module.Ref.render
                  data_field={@data_field}
                  uploads={@uploads}
                  module_refs={@refs_forms}
                  module_ref_name={ref}
                  base_form={@base_form} />

              <% {:content, _} -> %>
                <%= if @module_multi do %>
                  <.live_component module={Blocks.Module.Entries}
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
                <% end %>

              <% {:variable, var_name, variable_value} -> %>
                <div class="rendered-variable" data-popover={gettext "Edit the entry directly to affect this variable [%{var_name}]", var_name: var_name}>
                  <%= variable_value %>
                </div>

              <% {:picture, _, img_src} -> %>
                <figure>
                  <img src={img_src} />
                </figure>

              <% _ -> %>
                <%= raw split %>
            <% end %>
          <% end %>
          <Input.input type={:hidden} field={@block_data[:module_id]} uid={@uid} id_prefix="module_data" />
          <Input.input type={:hidden} field={@block_data[:sequence]} uid={@uid} id_prefix="module_data" />
          <Input.input type={:hidden} field={@block_data[:multi]} uid={@uid} id_prefix="module_data" />
        </div>
      </Blocks.block>
    </div>
    """
  end

  def handle_event("select_entries", _, socket) do
    {:noreply, assign_available_entries(socket)}
  end

  def handle_event(
        "select_identifier",
        %{"param" => idx},
        %{assigns: %{available_entries: available_entries, selected_entries: selected_entries}} =
          socket
      ) do
    picked_entry = Enum.at(available_entries, String.to_integer(idx))

    # deselect if already selected
    selected_entries =
      if Enum.find(selected_entries, &(&1 == picked_entry)) do
        Enum.filter(selected_entries, &(&1 != picked_entry))
      else
        selected_entries ++ List.wrap(picked_entry)
      end

    {:noreply,
     socket
     |> assign(:selected_entries, selected_entries)
     |> update_ids(:add, picked_entry)
     |> push_event("b:validate", %{})}
  end

  def handle_event(
        "remove_identifier",
        %{"param" => idx},
        %{assigns: %{selected_entries: selected_entries}} = socket
      ) do
    picked_entry = Enum.at(selected_entries, String.to_integer(idx))
    new_entries = selected_entries |> Enum.filter(&(&1 != picked_entry))

    {:noreply,
     socket
     |> assign(:selected_entries, new_entries)
     |> update_ids(:remove, picked_entry)
     |> push_event("b:validate", %{})}
  end

  def handle_event(
        "sequenced",
        %{"ids" => ordered_ids},
        %{
          assigns: %{
            base_form: form,
            uid: uid,
            block: block,
            data_field: data_field,
            selected_entries: selected_entries
          }
        } = socket
      ) do
    changeset = form.source
    current_data = input_value(block, :data)
    new_data = Map.put(current_data, :datasource_selected_ids, ordered_ids)

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    updated_entries =
      Enum.map(ordered_ids, fn id -> Enum.find(selected_entries, &(&1.id == id)) end)

    {:noreply, assign(socket, :selected_entries, updated_entries)}
  end

  def handle_event(
        "fetch_missing_vars",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field,
            module_id: module_id
          }
        } = socket
      ) do
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    current_vars = input_value(block_data, :vars) || []
    current_var_keys = Enum.map(current_vars, & &1.key)

    module_vars = module.vars || []
    module_var_keys = Enum.map(module_vars, & &1.key)

    missing_var_keys = module_var_keys -- current_var_keys
    missing_vars = Enum.filter(module_vars, &(&1.key in missing_var_keys))

    new_vars = current_vars ++ missing_vars

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{vars: new_vars}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :important_vars, Enum.filter(new_vars, &(&1.important == true)))}
  end

  def handle_event(
        "reset_vars",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            data_field: data_field,
            module_id: module_id
          }
        } = socket
      ) do
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{vars: module.vars}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :important_vars, Enum.filter(module.vars, &(&1.important == true)))}
  end

  def handle_event(
        "reset_var",
        %{"id" => var_id},
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field,
            module_id: module_id
          }
        } = socket
      ) do
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    reset_var = Enum.find(module.vars, &(&1.key == var_id))
    current_vars = input_value(block_data, :vars)

    updated_vars =
      Enum.map(current_vars, fn
        %{key: ^var_id} -> reset_var
        var -> var
      end)

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{vars: updated_vars}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "fetch_missing_refs",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field,
            module_id: module_id
          }
        } = socket
      ) do
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    current_refs = input_value(block_data, :refs)
    current_ref_names = Enum.map(current_refs, & &1.name)

    module_refs = module.refs
    module_ref_names = Enum.map(module_refs, & &1.name)

    missing_ref_names = module_ref_names -- current_ref_names
    missing_refs = Enum.filter(module_refs, &(&1.name in missing_ref_names))

    new_refs = current_refs ++ missing_refs

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(new_refs)

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{refs: refs_with_generated_uids}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "reset_refs",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            data_field: data_field,
            module_id: module_id
          }
        } = socket
      ) do
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{refs: refs_with_generated_uids}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "reset_ref",
        %{"id" => ref_id},
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field,
            module_id: module_id
          }
        } = socket
      ) do
    {:ok, module} = Brando.Content.get_module(module_id)

    changeset = base_form.source

    reset_ref = Enum.find(module.refs, &(&1.name == ref_id))
    current_refs = input_value(block_data, :refs)

    updated_refs =
      Enum.map(current_refs, fn
        %{name: ^ref_id} -> reset_ref
        ref -> ref
      end)

    updated_refs_with_generated_uids = Brando.Villain.add_uid_to_refs(updated_refs)

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{refs: updated_refs_with_generated_uids}}
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  defp update_ids(
         %{
           assigns: %{
             base_form: form,
             uid: uid,
             block: block,
             data_field: data_field
           }
         } = socket,
         action,
         entry
       ) do
    # replace block
    changeset = form.source
    current_data = input_value(block, :data)

    new_data =
      if action == :add do
        Map.put(
          current_data,
          :datasource_selected_ids,
          (current_data.datasource_selected_ids || []) ++ List.wrap(entry.id)
        )
      else
        Map.put(
          current_data,
          :datasource_selected_ids,
          Enum.filter(current_data.datasource_selected_ids || [], &(&1 != entry.id))
        )
      end

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    socket
  end

  @regex_strips ~r/(({% hide %}(?:.*?){% endhide %}))|((?:{%(?:-)? for (\w+) in [a-zA-Z0-9_.?|"-]+ (?:-)?%})(?:.*?)(?:{%(?:-)? endfor (?:-)?%}))|(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|({%(?:-)? assign .*? (?:-)?%})|(((?:{%(?:-)? if .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endif (?:-)?%})))|(((?:{%(?:-)? unless .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endunless (?:-)?%})))|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s
  @regex_splits ~r/{% (?:ref|headless_ref) refs.(\w+) %}|<.*?>|\{\{\s?(.*?)\s?\}\}|{% picture ([a-zA-Z0-9_.?|"-]+) {.*} %}/
  @regex_chunks ~r/^{% (?:ref|headless_ref) refs.(?<ref>\w+) %}$|^{{ (?<content>[\w\s.|\"\']+) }}$|^{% picture (?<picture>[a-zA-Z0-9_.?|"-]+) {.*} %}$/

  defp parse_module_code(%{assigns: %{module_not_found: true}} = socket), do: socket

  defp parse_module_code(%{assigns: %{module_code: module_code} = assigns} = socket) do
    module_code =
      module_code
      |> strip_logic()
      |> emphasize_datasources(assigns)

    splits =
      @regex_splits
      |> Regex.split(module_code, include_captures: true)
      |> Enum.map(fn chunk ->
        case Regex.run(@regex_chunks, chunk, capture: :all_names) do
          nil ->
            chunk

          ["content", "", ""] ->
            {:content, "content"}

          ["content | renderless", "", ""] ->
            {:content, "content"}

          [variable, "", ""] ->
            {:variable, variable, render_variable(variable, socket.assigns)}

          ["", pic, ""] ->
            {:picture, pic, render_picture_src(pic, socket.assigns)}

          ["", "", ref] ->
            {:ref, ref}
        end
      end)

    assign(socket, :splits, splits)
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

  # defp strip_l(tpl) do
  #   tpl
  #   |> Enum.reduce([], fn
  #     {:iteration, _}, acc -> acc
  #     {:control_flow, _}, acc -> acc
  #     expr, acc -> [expr | acc]
  #   end)
  #   |> Enum.reverse()
  # end

  defp strip_logic(module_code),
    do: Regex.replace(@regex_strips, module_code, "")

  defp render_picture_src("entry." <> var_path_string, assigns) do
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

  defp render_picture_src(var_name, %{vars: vars}) do
    # FIXME
    #
    # This is suboptimal at best. We preload all our image vars in the form, but when running
    # the polymorphic changesets, it clobbers the image's `value` - resetting it.
    #
    # Everything here will hopefully improve when we can update poly changesets instead
    # of replacing/inserting new every time.

    case Enum.find(vars, &(&1.key == var_name)) do
      %Brando.Content.Var.Image{value_id: nil} ->
        ""

      %Brando.Content.Var.Image{value: %Ecto.Association.NotLoaded{}, value_id: image_id} ->
        case Brando.Cache.get("var_image_#{image_id}") do
          nil ->
            image = Brando.Images.get_image!(image_id)
            media_path = Brando.Utils.media_url(image.path)
            Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
            media_path

          media_path ->
            media_path
        end

      %Brando.Content.Var.Image{value: image, value_id: image_id} ->
        media_path = Brando.Utils.media_url(image.path)
        Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
        media_path

      %Brando.Images.Image{path: path} ->
        Brando.Utils.media_url(path)

      _ ->
        ""
    end
  end

  defp render_variable("entry." <> var_path_string, assigns) do
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

  defp render_variable(var, assigns) do
    case Enum.find(assigns.vars, &(&1.key == var)) do
      %{value: value} -> value
      nil -> var
    end
  end
end
