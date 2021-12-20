defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.EntryBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils
  alias Brando.Villain
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.Blocks.Module

  # prop block, :any
  # prop base_form, :any
  # prop index, :any
  # prop block_count, :integer
  # prop uploads, :any
  # prop data_field, :atom
  # prop entry_template, :map
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
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

    refs = Enum.with_index(inputs_for(block_data, :refs))
    vars = v(block_data, :vars) || []

    socket
    |> assign(:uid, v(block, :uid) || Brando.Utils.generate_uid())
    |> assign(:block_data, block_data)
    |> assign(:module_name, entry_template.name)
    |> assign(:module_class, entry_template.class)
    |> assign(:module_code, entry_template.code)
    |> assign(:module_multi, true)
    |> assign(:refs, refs)
    |> assign(:vars, vars)
    |> assign_new(:important_vars, fn ->
      Enum.filter(vars, &(&1.important == true))
    end)
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>

      <.live_component module={Block}
        id={"block-#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        is_entry?={true}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description><%= @module_name %></:description>
        <:config>
          <%= for {var, index} <- Enum.with_index(inputs_for_poly(@block_data, :vars)) do %>
            <.live_component module={RenderVar} id={"block-#{@uid}-render-var-#{index}"} var={var} render={:only_regular} />
          <% end %>

          <button type="button" class="secondary" phx-click={JS.push("reinit_vars", target: @myself)}>
            Reinitialize variables
          </button>

          <button type="button" class="secondary" phx-click={JS.push("reinit_refs", target: @myself)}>
            Reset block refs
          </button>
        </:config>

        <div class="module-block" b-editor-tpl={@module_class}>
          <%= unless Enum.empty?(@important_vars) do %>
            <div class="important-vars">
              <%= for {var, index} <- Enum.with_index(inputs_for_poly(@block_data, :vars)) do %>
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
                  module_refs={@refs}
                  module_ref_name={ref}
                  base_form={@base_form} />

              <% {:variable, var_name, variable_value} -> %>
                <div class="rendered-variable" data-popover={gettext "Edit the entry directly to affect this variable [%{var_name}]", var_name: var_name}>
                  <%= variable_value %>
                </div>

              <% {:picture, _, img_src} -> %>
                <img src={img_src} />

              <% _ -> %>
                <%= raw split %>
            <% end %>
          <% end %>
          <%= hidden_input @block_data, :module_id %>
          <%= hidden_input @block_data, :sequence %>
          <%= hidden_input @block_data, :multi %>
        </div>
      </.live_component>
    </div>
    """
  end

  def handle_event(
        "reinit_vars",
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
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
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
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  @regex_strips ~r/((?:{% for (\w+) in [a-zA-Z0-9_.?|"-]+ %})(?:.*?)(?:{% endfor %}))|({% assign .*? %})|(({% if .* %}(?:.*?){% endif %}))|(({% unless .* %}(?:.*?){% endunless %}))/s
  @regex_splits ~r/{% (?:ref|headless_ref) refs.(\w+) %}|<.*?>|\{\{\s?(.*?)\s?\}\}|{% picture ([a-zA-Z0-9_.?|"-]+) {.*} %}/
  @regex_chunks ~r/^{% (?:ref|headless_ref) refs.(?<ref>\w+) %}$|^{{ (?<content>[\w.]+) }}$|^{% picture (?<picture>[a-zA-Z0-9_.?|"-]+) {.*} %}$/

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
