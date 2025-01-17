defmodule BrandoAdmin.Content.ModuleFormLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Module.Ref
  alias Brando.Content.Var
  alias Brando.Villain
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.ModuleProps
  alias Ecto.Changeset

  def mount(%{"entry_id" => entry_id}, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:save_redirect_target, :listing)
       |> assign_entry(entry_id)
       |> assign_current_user(token)
       |> assign_form()
       |> set_admin_locale()}
    else
      {:ok, assign(socket, :socket_connected, false)}
    end
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Content Modules")} subtitle={gettext("Edit module")} />

    <div id="module_form-el" phx-hook="Brando.Form" data-skip-keydown>
      <.form for={@form} phx-change="validate" phx-submit="save">
        <input type="hidden" name={"#{@form.name}[#{:__force_change}]"} phx-debounce="0" />
        <div class="block-editor">
          <div class="code">
            <Input.code field={@form[:code]} label={gettext("Code")} />
          </div>

          <.live_component
            module={ModuleProps}
            id="module-props"
            form={@form}
            create_ref={JS.push("create_ref")}
            delete_ref={JS.push("delete_ref")}
            duplicate_ref={JS.push("duplicate_ref")}
            create_var={JS.push("create_var")}
            delete_var={JS.push("delete_var")}
            duplicate_var={JS.push("duplicate_var")}
          />
        </div>
        <div class="button-group">
          <Form.submit_button
            processing={false}
            form_id="module_form"
            label={gettext("Save (⇧⌘S)")}
            class="primary submit-button"
          />
        </div>
      </.form>
    </div>
    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("save_redirect_target", _, socket) do
    {:noreply, assign(socket, :save_redirect_target, :self)}
  end

  ## Sequence event
  def handle_event("create_ref", %{"type" => block_type}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    refs = Changeset.get_field(changeset, :refs)

    block_module =
      block_type
      |> String.to_existing_atom()
      |> Villain.get_block_by_type()

    ref_data = struct(block_module, %{data: struct(Module.concat([block_module, Data]))})

    new_ref = %Ref{
      name: Brando.Utils.random_string(5),
      data: ref_data
    }

    updated_changeset = Changeset.put_change(changeset, :refs, [new_ref | refs])
    updated_form = to_form(updated_changeset, [])

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("delete_ref", %{"id" => ref_name}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    refs = Changeset.get_field(changeset, :refs)
    filtered_refs = Enum.reject(refs, &(&1.name == ref_name))

    updated_changeset = Changeset.put_change(changeset, :refs, filtered_refs)
    updated_form = to_form(updated_changeset, [])

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("duplicate_ref", %{"id" => ref_name}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    refs = Changeset.get_field(changeset, :refs)
    ref_to_dupe = Enum.find(refs, &(&1.name == ref_name))

    new_ref = Map.put(ref_to_dupe, :name, Brando.Utils.random_string(5))

    updated_changeset = Changeset.put_change(changeset, :refs, refs ++ [new_ref])
    updated_form = to_form(updated_changeset, [])

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("create_var", %{"type" => var_type}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_field(changeset, :vars) || []
    var_type = String.to_existing_atom(var_type)

    new_var =
      %Var{
        key: Brando.Utils.random_string(5),
        label: "Label",
        type: var_type
      }

    updated_changeset = Changeset.put_change(changeset, :vars, [new_var | vars])
    updated_form = to_form(updated_changeset, [])

    {:noreply,
     socket
     |> assign(:form, updated_form)
     |> assign(:var_name, nil)}
  end

  def handle_event("delete_var", %{"id" => var_key}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_field(changeset, :vars)
    filtered_vars = Enum.reject(vars, &(&1.key == var_key))

    updated_changeset = Changeset.put_change(changeset, :vars, filtered_vars)
    updated_form = to_form(updated_changeset, [])

    {:noreply,
     socket
     |> assign(:form, updated_form)
     |> assign(:var_name, nil)}
  end

  def handle_event("duplicate_var", %{"id" => var_key}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_field(changeset, :vars)
    var_to_dupe = Enum.find(vars, &(&1.key == var_key))

    new_var = Map.put(var_to_dupe, :key, Brando.Utils.random_string(5))

    updated_changeset = Changeset.put_change(changeset, :vars, vars ++ [new_var])
    updated_form = to_form(updated_changeset, [])

    {:noreply,
     socket
     |> assign(:form, updated_form)
     |> assign(:var_name, nil)}
  end

  def handle_event("validate", %{"module" => module_params}, socket) do
    %{current_user: current_user, entry: entry} = socket.assigns
    changeset = Brando.Content.Module.changeset(entry, module_params, current_user)
    updated_changeset = %{changeset | action: :update}

    updated_form = to_form(updated_changeset, [])

    socket
    |> assign(:form, updated_form)
    |> then(&{:noreply, &1})
  end

  def handle_event("save", %{"module" => module_params}, socket) do
    user = socket.assigns.current_user
    entry = socket.assigns.entry
    changeset = Brando.Content.Module.changeset(entry, module_params, user)
    updated_changeset = %{changeset | action: :update}

    changeset =
      if Changeset.changed?(updated_changeset, :svg) do
        svg = Changeset.get_change(updated_changeset, :svg)

        if String.starts_with?(svg, "<svg") do
          updated_svg = Base.encode64(svg, padding: false)
          Changeset.put_change(updated_changeset, :svg, updated_svg)
        else
          updated_changeset
        end
      else
        updated_changeset
      end

    case Brando.Content.update_module(changeset, user) do
      {:ok, _entry} ->
        send(self(), {:toast, gettext("Module updated")})
        {:noreply, push_navigate(socket, to: "/admin/config/content/modules")}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger

        raise "Changeset error"

        traversed_errors =
          Changeset.traverse_errors(changeset, fn
            {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
            msg -> msg
          end)

        Logger.error("""

        update_module returned an error

        """)

        Logger.error(inspect(changeset, pretty: true))
        Logger.error(inspect(changeset.errors, pretty: true))
        Logger.error(inspect(traversed_errors, pretty: true))

        form = to_form(changeset, [])

        socket
        |> assign(:form, form)
        |> then(&{:noreply, &1})
    end
  end

  def handle_info({:add_select_var_option, var_key}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_field(changeset, :vars) || []

    vars =
      Enum.reduce(vars, [], fn
        %{key: ^var_key} = var, acc ->
          var_changeset = Changeset.change(var)
          opts = Changeset.get_embed(var_changeset, :options) || []
          updated_opts = opts ++ [Changeset.change(%Var.Option{label: "label", value: "option"})]
          updated_var_changeset = Changeset.put_embed(var_changeset, :options, updated_opts)

          acc ++ [updated_var_changeset]

        var, acc ->
          acc ++ [Changeset.change(var)]
      end)

    updated_changeset = Changeset.put_assoc(changeset, :vars, vars)
    updated_form = to_form(updated_changeset, [])

    {:noreply, assign(socket, :form, updated_form)}
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_entry(socket, entry_id) do
    assign_new(socket, :entry, fn ->
      Brando.Content.get_module!(%{matches: %{id: entry_id}, preload: [:vars]})
    end)
  end

  defp assign_form(%{assigns: %{entry: entry, current_user: current_user}} = socket) do
    assign_new(socket, :form, fn ->
      entry
      |> Brando.Content.Module.changeset(%{}, current_user)
      |> to_form([])
    end)
  end
end
