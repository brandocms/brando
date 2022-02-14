defmodule BrandoAdmin.Components.Form.Input.Blocks.ModuleBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Brando.Content
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
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
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
    {:ok, modules} = Content.list_modules(%{cache: {:ttl, :infinite}})

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
     |> assign_new(:entry, fn -> Ecto.Changeset.apply_changes(assigns.base_form.source) end)
     |> assign_new(:module_id, fn -> v(assigns.block, :data).module_id end)
     |> assign_module_data()
     |> parse_module_code()}
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

        refs = Enum.with_index(inputs_for(block_data, :refs))
        vars = v(block_data, :vars) || []

        socket
        |> assign(:uid, v(block, :uid))
        |> assign(:block_data, block_data)
        |> assign(:module_name, module.name)
        |> assign(:module_class, module.class)
        |> assign(:module_code, module.code)
        |> assign(:module_multi, input_value(block_data, :multi))
        |> assign(:entry_template, module.entry_template)
        |> assign(:refs, refs)
        |> assign(:vars, vars)
        |> assign_new(:important_vars, fn ->
          Enum.filter(vars, &(&1.important == true))
        end)
    end
  end

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

      <.live_component module={Block}
        id={"block-#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description><%= @module_name %></:description>
        <:config>
          <div class="panels">
            <div class="panel">
              <%= for {var, index} <- Enum.with_index(inputs_for_poly(@block_data, :vars)) do %>
                <.live_component module={RenderVar} id={"block-#{@uid}-render-var-#{index}"} var={var} render={:only_regular} />
              <% end %>
            </div>
            <div class="panel">
              <h2 class="titlecase">Vars</h2>
              <%= for var <- v(@block_data, :vars) || [] do %>
                <div class="var">
                  <div class="key"><%= var.key %></div>
                  <button type="button" class="tiny" phx-click={JS.push("reset_var", target: @myself)} phx-value-id={var.key}><%= gettext "Reset" %></button>
                </div>
              <% end %>

              <h2 class="titlecase">Refs</h2>
              <%= for ref <- v(@block_data, :refs) || [] do %>
                <div class="ref">
                  <div class="key"><%= ref.name %></div>
                  <button type="button" class="tiny" phx-click={JS.push("reset_ref", target: @myself)} phx-value-id={ref.name}><%= gettext "Reset" %></button>
                </div>
              <% end %>
              <div class="button-group-vertical">
                <button type="button" class="secondary" phx-click={JS.push("fetch_missing_refs", target: @myself)}>
                  Fetch missing refs
                </button>
                <button type="button" class="secondary" phx-click={JS.push("reset_refs", target: @myself)}>
                  Reset all block refs
                </button>
                <button type="button" class="secondary" phx-click={JS.push("fetch_missing_vars", target: @myself)}>
                  Fetch missing vars
                </button>
                <button type="button" class="secondary" phx-click={JS.push("reset_vars", target: @myself)}>
                  Reset all variables
                </button>
              </div>
            </div>
          </div>
        </:config>

        <div b-editor-tpl={@module_class}>
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

              <% {:content, _} -> %>
                <%= if @module_multi do %>
                  <.live_component
                    module={Module.Entries}
                    id={"block-#{@uid}-entries"}
                    uid={@uid}
                    entry_template={@entry_template}
                    block_data={@block_data}
                    data_field={@data_field}
                    base_form={@base_form}
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
          <%= hidden_input @block_data, :module_id %>
          <%= hidden_input @block_data, :sequence %>
          <%= hidden_input @block_data, :multi %>
        </div>
      </.live_component>
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

    changeset = base_form.source

    current_vars = input_value(block_data, :vars)
    current_var_keys = Enum.map(current_vars, & &1.key)

    module_vars = module.vars
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
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
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
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
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
      updated_changeset: updated_changeset
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
      updated_changeset: updated_changeset
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
      updated_changeset: updated_changeset
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
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  @regex_strips ~r/((?:{%(?:-)? for (\w+) in [a-zA-Z0-9_.?|"-]+ (?:-)?%})(?:.*?)(?:{%(?:-)? endfor (?:-)?%}))|(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|({%(?:-)? assign .*? (?:-)?%})|(({%(?:-)? if .* (?:-)?%}(?:.*?){%(?:-)? endif (?:-)?%}))|(({%(?:-)? unless .* (?:-)?%}(?:.*?){%(?:-)? endunless (?:-)?%}))|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}._\s]+"))/s
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
