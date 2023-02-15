defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.EntryBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils
  alias Brando.Villain
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Blocks.Module

  # prop block, :any
  # prop base_form, :any
  # prop index, :any
  # prop block_count, :integer
  # prop uploads, :any
  # prop data_field, :atom
  # prop entry_template, :map
  # prop belongs_to, :string

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data splits, :list
  # data block_data, :map
  # data module_name, :string
  # data module_class, :string
  # data module_code, :string
  # data module_multi, :boolean
  # data refs, :list
  # data important_vars, :list
  # data uid, :string
  # data module_not_found, :boolean

  def v(form, field) do
    input_value(form, field)
  end

  def mount(socket) do
    {:ok, assign(socket, uploads: nil)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_module_data()
     |> parse_module_code()}
  end

  defp assign_module_data(%{assigns: %{block: block, entry_template: entry_template}} = socket) do
    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    refs_forms = Enum.with_index(inputs_for(block_data, :refs))
    refs = v(block_data, :refs) || []
    vars = v(block_data, :vars) || []
    description = v(block, :description)

    socket
    |> assign(:uid, v(block, :uid) || Brando.Utils.generate_uid())
    |> assign(:description, description)
    |> assign(:block_data, block_data)
    |> assign(:indexed_vars, Enum.with_index(inputs_for_poly(block_data[:vars])))
    |> assign(:module_name, entry_template.name)
    |> assign(:module_class, entry_template.class)
    |> assign(:module_code, entry_template.code)
    |> assign(:module_multi, true)
    |> assign(:refs_forms, refs_forms)
    |> assign(:refs, refs)
    |> assign(:vars, vars)
    |> assign_new(:important_vars, fn -> Enum.filter(vars, &(&1.important == true)) end)
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>

      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        is_entry?={true}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}>
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
                <button type="button" class="secondary" phx-click={JS.push("reinit_vars", target: @myself)}>
                  Reinitialize variables
                </button>

                <button type="button" class="secondary" phx-click={JS.push("reinit_refs", target: @myself)}>
                  Reset block refs
                </button>

                <button type="button" class="secondary" phx-click={JS.push("fetch_missing_vars", target: @myself)}>
                  Fetch missing vars
                </button>
              </div>
            </div>
          </div>
        </:config>

        <div class="module-block" b-editor-tpl={@module_class}>
          <%= unless Enum.empty?(@important_vars) do %>
            <div class="important-vars">
              <%= for {var, index} <- Enum.with_index(inputs_for_poly(@block_data[:vars])) do %>
                <.live_component module={RenderVar} id={"block-#{@uid}-render-var-blk-#{index}"} var={var} render={:only_important} />
              <% end %>
            </div>
          <% end %>

          <%= for split <- @splits do %>
            <%= case split do %>
              <% {:ref, ref} -> %>
                <Module.Ref.render
                  data_field={@data_field}
                  uploads={@uploads}
                  module_refs={@refs_forms}
                  module_ref_name={ref}
                  base_form={@base_form} />

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
          <Input.input type={:hidden} field={@block_data[:module_id]} />
          <Input.input type={:hidden} field={@block_data[:sequence]} />
          <Input.input type={:hidden} field={@block_data[:multi]} />
        </div>
      </Blocks.block>
    </div>
    """
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

    entry_template = module.entry_template

    changeset = base_form.source

    current_vars = input_value(block_data, :vars) || []
    current_var_keys = Enum.map(current_vars, & &1.key)

    module_vars = entry_template.vars
    module_var_keys = Enum.map(module_vars, & &1.key)

    missing_var_keys = module_var_keys -- current_var_keys
    missing_vars = Enum.filter(module_vars, &(&1.key in missing_var_keys))

    new_vars = current_vars ++ missing_vars

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{vars: new_vars}},
        true
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
        "reinit_vars",
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

    entry_template = module.entry_template
    changeset = base_form.source
    module_vars = entry_template.vars

    updated_changeset =
      Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{vars: module_vars}},
        true
      )

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :important_vars, Enum.filter(module_vars, &(&1.important == true)))}
  end

  def handle_event(
        "reinit_refs",
        _,
        %{
          assigns: %{
            base_form: base_form,
            uid: block_uid,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    module_id = input_value(block_data, :module_id)
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

  @regex_strips ~r/(({% hide %}(?:.*?){% endhide %}))|((?:{%(?:-)? for (\w+) in [a-zA-Z0-9_.?|"-]+ (?:-)?%})(?:.*?)(?:{%(?:-)? endfor (?:-)?%}))|(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|({%(?:-)? assign .*? (?:-)?%})|(((?:{%(?:-)? if .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endif (?:-)?%})))|(((?:{%(?:-)? unless .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endunless (?:-)?%})))|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s
  @regex_splits ~r/{% (?:ref|headless_ref) refs.(\w+) %}|<.*?>|\{\{\s?(.*?)\s?\}\}|{% picture ([a-zA-Z0-9_.?|"-]+) {.*} %}/
  @regex_chunks ~r/^{% (?:ref|headless_ref) refs.(?<ref>\w+) %}$|^{{ (?<content>[\w\s.|\"\']+) }}$|^{% picture (?<picture>[a-zA-Z0-9_.?|"-]+) {.*} %}$/

  defp parse_module_code(%{assigns: %{module_not_found: true}} = socket), do: socket

  defp parse_module_code(%{assigns: %{module_code: module_code}} = socket) do
    splits =
      @regex_splits
      |> Regex.split(strip_logic(module_code), include_captures: true)
      |> Enum.map(fn chunk ->
        case Regex.run(@regex_chunks, chunk, capture: :all_names) do
          nil ->
            chunk

          ["content", "", ""] ->
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

  defp strip_logic(module_code), do: Regex.replace(@regex_strips, module_code, "")

  defp render_picture_src("entry." <> var_path_string, assigns) do
    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    entry = Ecto.Changeset.apply_changes(assigns.base_form.source)

    if img = Brando.Utils.try_path(entry, var_path) do
      Brando.Utils.media_url(img.path)
    else
      ""
    end
  end

  defp render_variable("entry." <> var_path_string, assigns) do
    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    entry = Ecto.Changeset.apply_changes(assigns.base_form.source)

    # TODO: Find a way to preload any changed associations here? otherwise, if we for instance have
    # an `entry.category_id` that changes, entry.category will still show the old relation.
    # if we Brando.repo().preload(entry, [:category], force: true) it will be correct.
    # However, it isn't very efficient to force a preload on every render_variable call!

    # We could track all relations from the schema blueprint, store their ids and check, but .. ugh.
    # If we assign the entry as rendered_entry every time, we at least won't have to preload
    # on every render

    # The best might be to not preload here, but preload directly from the input component
    # that updates the relation. So if it is a select box, send_update to the form with
    # the field we wish to reload?

    # entry = Brando.repo().preload(entry, [:category], force: true)
    Brando.Utils.try_path(entry, var_path) |> raw()
  end

  defp render_variable(var, assigns) do
    case Enum.find(assigns.vars, &(&1.key == var)) do
      %{value: value} -> value
      nil -> var
    end
  end
end
