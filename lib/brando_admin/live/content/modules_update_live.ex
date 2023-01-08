defmodule BrandoAdmin.Content.ModuleUpdateLive do
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Phoenix.HTML

  import Brando.Gettext
  import Ecto.Changeset

  alias Brando.Villain
  alias Brando.Content.Module.Ref
  alias Brando.Villain.Blocks

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.ModuleProps

  def mount(%{"entry_id" => entry_id}, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> assign(:socket_connected, true)
       |> assign(:save_redirect_target, :listing)
       |> assign_entry(entry_id)
       |> assign_current_user(token)
       |> assign_changeset()
       |> set_admin_locale()}
    else
      {:ok,
       socket
       |> assign(:socket_connected, false)}
    end
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Content Modules")} subtitle={gettext("Edit module")} />

    <div id="module-form-el" phx-hook="Brando.Form">
      <.form
        :let={form}
        for={@changeset}
        phx-change="validate"
        phx-submit="save">
        <div class="block-editor">
          <div class="code">
            <Input.code form={form} field={:code} label={gettext "Code"} />
          </div>

          <.live_component module={ModuleProps}
            id="module-props"
            form={form}
            create_ref={JS.push("create_ref")}
            delete_ref={JS.push("delete_ref")}
            duplicate_ref={JS.push("duplicate_ref")}
            create_var={JS.push("create_var")}
            delete_var={JS.push("delete_var")}
            duplicate_var={JS.push("duplicate_var")}
            add_table_row="add_table_row"
            add_table_col="add_table_col"
            add_table_template="add_table_template"
          />
        </div>
        <Form.inputs
          :if={input_value(form, :wrapper) in [true, "true"]}
          :let={%{form: entry}}
          form={form}
          for={:entry_template}
        >
          <div class="entry-template">
            <hr>
            <h2>Entry template</h2>
            <p>
              This module will be used as a template when generating new entries inside the wrapper module
            </p>

            <div class="block-editor">
              <div class="code">
                <Input.code form={entry} field={:code} label={gettext "Code"} />
              </div>

              <Input.input type={:hidden} form={entry} field={:id} />

              <.live_component module={ModuleProps}
                id={"entry-module-props-#{entry.id}"}
                form={entry}
                entry_form
                create_ref={JS.push("entry_create_ref")}
                duplicate_ref={JS.push("entry_duplicate_ref")}
                delete_ref="entry_delete_ref"
                create_var={JS.push("entry_create_var")}
                duplicate_var={JS.push("entry_duplicate_var")}
                delete_var="entry_delete_var"
                show_modal="show_modal"
              />
            </div>
          </div>
        </Form.inputs>

        <div class="button-group">
          <Form.submit_button
            processing={false}
            form_id={"module-form"}
            label={gettext("Save (⇧⌘S)")}
            class="primary submit-button" />
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

  ## Table events

  def handle_event(
        "add_table_template",
        %{"id" => ref_name},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    new_row = %Blocks.TableBlock.Row{cols: []}
    refs = get_field(changeset, :refs)
    ref = Enum.find(refs, &(&1.name == ref_name))

    updated_ref =
      put_in(ref, [Access.key(:data), Access.key(:data), Access.key(:template_row)], new_row)

    updated_refs = Enum.map(refs, &((&1.name == ref_name && updated_ref) || &1))
    updated_changeset = put_change(changeset, :refs, updated_refs)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "add_table_col",
        %{"id" => ref_name, "type" => var_type},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    var_module =
      var_type
      |> String.to_existing_atom()
      |> Brando.Content.get_var_by_type()

    new_col =
      struct(var_module, %{
        key: Brando.Utils.random_string(5),
        label: "Label",
        type: var_type,
        important: true
      })

    refs = get_field(changeset, :refs)
    ref = Enum.find(refs, &(&1.name == ref_name))

    updated_ref =
      update_in(
        ref,
        [
          Access.key(:data),
          Access.key(:data),
          Access.key(:template_row),
          Access.key(:cols)
        ],
        &(&1 ++ [new_col])
      )

    updated_refs = Enum.map(refs, &((&1.name == ref_name && updated_ref) || &1))
    updated_changeset = put_change(changeset, :refs, updated_refs)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "add_table_row",
        %{"id" => ref_name},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    new_row = %Blocks.TableBlock.Row{}
    refs = get_field(changeset, :refs)
    ref = Enum.find(refs, &(&1.name == ref_name))
    update_in(ref, [Access.key(:data), Access.key(:data), Access.key(:rows)], &[new_row | &1])

    # filtered_vars = Enum.reject(vars, &(&1.key == var_key))
    # updated_changeset = put_change(changeset, :vars, filtered_vars)

    # {:noreply, assign(socket, :changeset, updated_changeset)}

    require Logger
    Logger.error("==> add_table_row #{ref_name}")
    {:noreply, socket}
  end

  ## Sequence event

  def handle_event(
        "sequenced",
        %{
          "ids" => order_indices,
          "sortable_id" => "sortable-table-cols",
          "sortable_params" => ref_name
        },
        %{assigns: %{changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)
    ref = Enum.find(refs, &(&1.name == ref_name))

    cols = ref.data.data.template_row.cols
    sorted_cols = Enum.map(order_indices, &Enum.at(cols, &1))

    updated_ref =
      put_in(
        ref,
        [
          Access.key(:data),
          Access.key(:data),
          Access.key(:template_row),
          Access.key(:cols)
        ],
        sorted_cols
      )

    updated_refs = Enum.map(refs, &((&1.name == ref_name && updated_ref) || &1))
    updated_changeset = put_change(changeset, :refs, updated_refs)

    {:noreply, assign(socket, :changeset, updated_changeset)}
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

  def handle_event(
        "sequenced",
        %{"ids" => order_indices, "sortable_id" => "sortable-vars-entry-form"},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)
    vars = entry_template.vars

    sorted_vars = Enum.map(order_indices, &Enum.at(vars, &1))

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:vars, sorted_vars)

    updated_changeset = put_change(changeset, :entry_template, updated_entry_template)
    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "create_ref",
        %{"type" => block_type},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)

    block_module =
      block_type
      |> String.to_existing_atom()
      |> Villain.get_block_by_type()

    ref_data = struct(block_module, %{data: struct(Module.concat([block_module, Data]))})

    new_ref = %Ref{
      name: Brando.Utils.random_string(5),
      data: ref_data
    }

    updated_changeset = put_change(changeset, :refs, [new_ref | refs])

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)}
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
        "duplicate_ref",
        %{"id" => ref_name},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    refs = get_field(changeset, :refs)
    ref_to_dupe = Enum.find(refs, &(&1.name == ref_name))

    new_ref = Map.put(ref_to_dupe, :name, Brando.Utils.random_string(5))
    updated_changeset = put_change(changeset, :refs, refs ++ [new_ref])

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "create_var",
        %{"type" => var_type},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars) || []

    var_module =
      var_type
      |> String.to_existing_atom()
      |> Brando.Content.get_var_by_type()

    new_var =
      struct(var_module, %{
        key: Brando.Utils.random_string(5),
        label: "Label",
        type: var_type
      })

    updated_changeset = put_change(changeset, :vars, [new_var | vars])

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

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:var_name, nil)}
  end

  def handle_event(
        "duplicate_var",
        %{"id" => var_key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars)
    var_to_dupe = Enum.find(vars, &(&1.key == var_key))

    new_var = Map.put(var_to_dupe, :key, Brando.Utils.random_string(5))
    updated_changeset = put_change(changeset, :vars, vars ++ [new_var])

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:var_name, nil)}
  end

  ## Entry events

  def handle_event(
        "entry_create_ref",
        %{"type" => block_type},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)
    refs = entry_template.refs

    block_module =
      block_type
      |> String.to_existing_atom()
      |> Villain.get_block_by_type()

    ref_data = struct(block_module, %{data: struct(Module.concat([block_module, Data]))})

    new_ref = %Ref{
      name: Brando.Utils.random_string(5),
      data: ref_data
    }

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:refs, [new_ref | refs])

    updated_changeset = put_embed(changeset, :entry_template, updated_entry_template)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)}
  end

  def handle_event(
        "entry_delete_ref",
        %{"id" => ref_name},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)

    refs = entry_template.refs
    filtered_refs = Enum.reject(refs, &(&1.name == ref_name))

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:refs, filtered_refs)

    updated_changeset = put_change(changeset, :entry_template, updated_entry_template)

    {:noreply, assign(socket, :changeset, updated_changeset)}
  end

  def handle_event(
        "entry_create_var",
        %{"type" => var_type},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)
    vars = entry_template.vars || []

    var_module =
      var_type
      |> String.to_existing_atom()
      |> Brando.Content.get_var_by_type()

    new_var =
      struct(var_module, %{
        key: Brando.Utils.random_string(5),
        label: "Label",
        type: var_type
      })

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:vars, [new_var | vars])

    updated_changeset = put_embed(changeset, :entry_template, updated_entry_template)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)
     |> push_event("b:validate", %{})}
  end

  def handle_event(
        "entry_duplicate_var",
        %{"id" => var_key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)
    vars = entry_template.vars || []
    var_to_dupe = Enum.find(vars, &(&1.key == var_key))

    new_var = Map.put(var_to_dupe, :key, Brando.Utils.random_string(5))

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:vars, [new_var | vars])

    updated_changeset = put_embed(changeset, :entry_template, updated_entry_template)

    {:noreply,
     socket
     |> assign(:changeset, updated_changeset)}
  end

  def handle_event(
        "entry_delete_var",
        %{"id" => var_key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    entry_template = get_field(changeset, :entry_template)

    vars = entry_template.vars
    filtered_vars = Enum.reject(vars, &(&1.key == var_key))

    updated_entry_template =
      entry_template
      |> Map.from_struct()
      |> Map.drop([:__meta__, :id])
      |> Map.put(:vars, filtered_vars)

    updated_changeset = put_change(changeset, :entry_template, updated_entry_template)

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

    case Brando.Content.update_module(changeset, user) do
      {:ok, _entry} ->
        send(self(), {:toast, gettext("Module updated")})
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

  def handle_info(
        {:add_select_var_option, var_key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    vars = get_field(changeset, :vars) || []

    vars =
      Enum.reduce(vars, [], fn
        %{key: ^var_key} = var, acc ->
          acc ++
            [
              put_in(
                var,
                [Access.key(:options)],
                (var.options || []) ++
                  [%Brando.Content.Var.Select.Option{label: "label", value: "option"}]
              )
            ]

        var, acc ->
          acc ++ [var]
      end)

    updated_changeset = put_change(changeset, :vars, vars)

    {:noreply, assign(socket, :changeset, updated_changeset)}
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
