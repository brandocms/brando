defmodule BrandoAdmin.Villain.ModuleUpdateLive do
  use Surface.LiveView, layout: {BrandoAdmin.LayoutView, "live.html"}
  use BrandoAdmin.Toast
  use BrandoAdmin.Presence
  use Phoenix.HTML

  import Brando.Gettext
  import Ecto.Changeset
  import Phoenix.LiveView.Helpers

  alias Brando.Villain
  alias Brando.Content.Module.Ref

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.ModuleProps
  alias BrandoAdmin.Components.Form.Submit
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Toast

  alias Surface.Components.Form
  alias Surface.Components.Form.Inputs

  def mount(%{"entry_id" => entry_id}, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> Surface.init()
     |> assign_entry(entry_id)
     |> assign_current_user(token)
     |> assign_changeset()
     |> set_admin_locale()
     |> assign(ref_name: nil)
     |> assign(var_name: nil)
     |> assign(entry_ref_name: nil)
     |> assign(entry_var_name: nil)}
  end

  def render(assigns) do
    ~F"""
    <Content.Header title={gettext("Content Modules")} subtitle={gettext("Edit module")} />

    <div id="module-form-el">
      <Form for={@changeset} :let={form: form} change="validate" submit="save">
        <div class="block-editor">
          <div class="code">
            <Input.Code id={"#{form.id}-code"} form={form} field={:code} />
          </div>

          <ModuleProps
            form={form}
            ref_name={@ref_name}
            var_name={@var_name}
            create_ref="create_ref"
            delete_ref="delete_ref"
            update_ref_name="update_ref_name"
            create_var="create_var"
            delete_var="delete_var"
            update_var_name="update_var_name"
            show_modal="show_modal"
          />
        </div>
        {#if input_value(form, :entry_template)}
          <Inputs form={form} for={:entry_template} :let={form: entry, index: _idx}>
            <div class="entry-template">
              <hr>
              <h2>Entry template</h2>
              <p>
                This module will be used as a template when generating new entries inside the wrapper module
              </p>

              <div class="block-editor">
                <div class="code">
                  <Input.Code id={"#{entry.id}-entry-code"} form={entry} field={:code} />
                </div>

                <ModuleProps
                  form={entry}
                  ref_name={@entry_ref_name}
                  var_name={@entry_var_name}
                  entry_form
                  create_ref="entry_create_ref"
                  delete_ref="entry_delete_ref"
                  update_ref_name="entry_update_ref_name"
                  create_var="entry_create_var"
                  delete_var="entry_delete_var"
                  update_var_name="entry_update_var_name"
                  show_modal="show_modal"
                />
              </div>
            </div>
          </Inputs>
        {/if}

        <div class="button-group">
          <Submit
            processing={false}
            form_id={"module-form"}
            label={gettext("Save (⌘S)")}
            class="primary submit-button" />
        </div>
      </Form>
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

  def handle_event(
        "sequenced",
        %{"ids" => order_indices, "sortable_id" => "sortable-vars"},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars)
    sorted_vars = Enum.map(order_indices, &Enum.at(vars, &1))
    updated_changeset = put_change(changeset, :vars, sorted_vars)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event("show_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)
    {:noreply, socket}
  end

  def handle_event("update_ref_name", %{"ref_name" => ref_name}, socket) do
    {:noreply, assign(socket, :ref_name, ref_name)}
  end

  def handle_event("update_var_name", %{"var_name" => var_name}, socket) do
    {:noreply, assign(socket, :var_name, var_name)}
  end

  def handle_event(
        "create_ref",
        %{"type" => block_type, "id" => modal_id},
        %{assigns: %{ref_name: ref_name, changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)

    block_module =
      block_type
      |> String.to_existing_atom()
      |> Villain.get_block_by_type()

    ref_data = struct(block_module, %{data: struct(Module.concat([block_module, Data]))})

    new_ref = %Ref{
      name: ref_name,
      data: ref_data
    }

    updated_changeset = put_change(changeset, :refs, [new_ref | refs])
    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:ref_name, nil)}
  end

  def handle_event(
        "delete_ref",
        %{"id" => ref_name},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)
    filtered_refs = Enum.reject(refs, &(&1.name == ref_name))
    updated_changeset = put_change(changeset, :refs, filtered_refs)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "create_var",
        %{"type" => var_type, "id" => modal_id},
        %{assigns: %{var_name: var_name, changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars) || []

    var_module =
      var_type
      |> String.to_existing_atom()
      |> Brando.Content.get_var_by_type()

    new_var =
      struct(var_module, %{
        key: var_name,
        type: var_type
      })

    updated_changeset = put_change(changeset, :vars, [new_var | vars])
    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:var_name, nil)}
  end

  def handle_event(
        "delete_var",
        %{"id" => var_key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars)
    filtered_vars = Enum.reject(vars, &(&1.key == var_key))
    updated_changeset = put_change(changeset, :vars, filtered_vars)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  ## Entry events

  def handle_event("entry_update_ref_name", %{"ref_name" => ref_name}, socket) do
    require Logger
    Logger.error("=> entry_update_ref_name #{inspect(ref_name)}")
    {:noreply, assign(socket, :entry_ref_name, ref_name)}
  end

  def handle_event("entry_update_var_name", %{"var_name" => var_name}, socket) do
    {:noreply, assign(socket, :entry_var_name, var_name)}
  end

  def handle_event(
        "entry_create_ref",
        %{"type" => block_type, "id" => modal_id},
        %{assigns: %{entry_ref_name: ref_name, changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)
    refs = entry_template.refs

    block_module =
      block_type
      |> String.to_existing_atom()
      |> Villain.get_block_by_type()

    ref_data = struct(block_module, %{data: struct(Module.concat([block_module, Data]))})

    new_ref = %Ref{
      name: ref_name,
      data: ref_data
    }

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.put(:refs, [new_ref | refs])

    updated_changeset = put_embed(changeset, :entry_template, updated_entry_template)

    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:entry_ref_name, nil)}
  end

  def handle_event(
        "entry_delete_ref",
        %{"id" => ref_name},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)
    filtered_refs = Enum.reject(refs, &(&1.name == ref_name))
    updated_changeset = put_change(changeset, :refs, filtered_refs)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "entry_create_var",
        %{"type" => var_type, "id" => modal_id},
        %{assigns: %{var_name: var_name, changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars) || []

    var_module =
      var_type
      |> String.to_existing_atom()
      |> Brando.Content.get_var_by_type()

    new_var =
      struct(var_module, %{
        key: var_name,
        type: var_type
      })

    updated_changeset = put_change(changeset, :vars, [new_var | vars])
    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:var_name, nil)}
  end

  def handle_event(
        "entry_delete_var",
        %{"id" => var_key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars)
    filtered_vars = Enum.reject(vars, &(&1.key == var_key))
    updated_changeset = put_change(changeset, :vars, filtered_vars)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "validate",
        %{"module" => module_params},
        %{assigns: %{current_user: current_user, entry: entry}} = socket
      ) do
    changeset = Brando.Content.Module.changeset(entry, module_params, current_user)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event(
        "save",
        _,
        %{assigns: %{current_user: user, changeset: changeset}} = socket
      ) do
    changeset = %{changeset | action: :update}
    require Logger
    Logger.error("==> saving module!")

    case Brando.Content.update_module(changeset, user) do
      {:ok, _entry} ->
        Toast.send_delayed("Module updated")
        {:noreply, push_redirect(socket, to: "/admin/config/content/modules")}

      {:error, %Ecto.Changeset{} = changeset} ->
        traversed_errors =
          traverse_errors(changeset, fn
            {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
            msg -> msg
          end)

        require Logger
        Logger.error(inspect(changeset, pretty: true))
        Logger.error(inspect(changeset.errors, pretty: true))
        Logger.error(inspect(traversed_errors, pretty: true))

        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
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
      Brando.Content.get_module!(entry_id)
    end)
  end

  defp assign_changeset(%{assigns: %{entry: entry, current_user: current_user}} = socket) do
    assign_new(socket, :changeset, fn ->
      Brando.Content.Module.changeset(entry, %{}, current_user)
    end)
  end
end
