defmodule BrandoAdmin.Content.ModuleFormLive do
  @moduledoc false
  use BrandoAdmin, :live_view

  def __authorization_resource__, do: {:form, Brando.Content.Module}
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Content.ModuleDiff
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Villain.Blocks.TextBlock
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.ModuleProps
  alias BrandoAdmin.Components.Form.Primitives
  alias Ecto.Changeset

  def mount(%{"entry_id" => entry_id}, %{"user_token" => token}, socket) do
    shared_library? = socket.assigns.live_action == :shared_update

    cond do
      shared_library? and
          (Brando.Tenant.mode() != :multi or
             not if(Brando.Authorization.enabled?(),
               do:
                 Brando.Authorization.can?(
                   Brando.Authorization.Scope.installation(socket.assigns.current_user),
                   :update,
                   :shared_library
                 ),
               else: socket.assigns.current_user.role == :superuser
             )) ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:shared_library?, shared_library?)
         |> assign(:save_redirect_target, :listing)
         |> assign(:open_item_modal, nil)
         |> assign(:pending_destructive_save, nil)
         |> assign(:active_tab, :template)
         |> assign_entry(entry_id)
         |> assign_current_user(token)
         |> assign_form()
         |> set_admin_locale()
         |> maybe_use_public_library_context()}

      true ->
        {:ok,
         socket
         |> assign(:socket_connected, false)
         |> assign(:shared_library?, shared_library?)}
    end
  end

  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <Content.header
      title={if @shared_library?, do: gettext("Shared module library"), else: gettext("Content Modules")}
      subtitle={gettext("Edit module")}
    />

    <div id="module_form-el" phx-hook="Brando.Form" data-skip-keydown>
      <.form for={@form} class="main-form" phx-change="validate" phx-submit="save">
        <input type="hidden" name={"#{@form.name}[#{:__force_change}]"} phx-debounce="0" />

        <.tab_bar active_tab={@active_tab} form={@form} />

        <div :if={@shared_library?} class="module-version-note">
          <Input.text
            field={@form[:version_note]}
            label={gettext("Changelog note")}
            instructions={gettext("Describe what changed for sites with customized versions.")}
          />
        </div>

        <%!-- Every panel stays in the DOM and is hidden with CSS. Rendering only
              the active one would drop the other panels' inputs from the form
              params, and would tear down and rebuild the code editor — losing
              its undo history — on every tab switch. --%>
        <div class="module-editor-panels">
          <section class={["module-panel", @active_tab == :template && "is-active"]} data-tab="template">
            <div class="code">
              <Input.code field={@form[:code]} label={gettext("Code")} />
              <div class="module-code-help">
                <p>{gettext("Use references for editable content and variables for reusable values.")}</p>
                <code>&lcub;% ref refs.name %&rcub;</code>
                <code>&lcub;&lcub; variable_key &rcub;&rcub;</code>
              </div>
            </div>
          </section>

          <.live_component
            module={ModuleProps}
            id="module-props"
            form={@form}
            active_tab={@active_tab}
            open_item_modal={@open_item_modal}
            create_ref={JS.push("create_ref")}
            duplicate_ref={JS.push("duplicate_ref")}
            create_var={JS.push("create_var")}
            duplicate_var={JS.push("duplicate_var")}
          />
        </div>

        <div class="button-group module-editor-actions">
          <Primitives.submit_button
            processing={false}
            form_id="module_form"
            label={gettext("Save (⇧⌘S)")}
            class="primary submit-button"
          />
        </div>
      </.form>
    </div>

    <.destructive_save_modal pending={@pending_destructive_save} />
    """
  end

  attr :pending, :any, required: true

  # Saving a module migrates every block that uses it, across every entry on the
  # site. When that migration would orphan content the editor typed — a removed
  # reference, a variable whose type changed — say so before it happens, and say
  # how far it reaches. The data is retained either way (see
  # `Brando.Content.Blocks.sync_module/2`), but the affected blocks stop
  # matching their module until someone resolves them.
  defp destructive_save_modal(assigns) do
    ~H"""
    <Content.modal
      :if={@pending}
      id="module-destructive-modal"
      title={gettext("This change affects existing content")}
      show={true}
      medium
      close={JS.push("cancel_destructive_save")}
    >
      <p>{affected_line(@pending.affected)}</p>
      <ul class="destructive-change-list">
        <li :for={line <- @pending.summary}>{line}</li>
      </ul>
      <p>
        {gettext(
          "Existing content is kept, not deleted — but those blocks will no longer match this module until they are reviewed."
        )}
      </p>
      <:footer>
        <button type="button" class="secondary" phx-click={JS.push("cancel_destructive_save")}>
          {gettext("Cancel")}
        </button>
        <button type="button" class="primary" phx-click={JS.push("confirm_destructive_save")}>
          {gettext("Save anyway")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  defp affected_line({:blocks, count}) do
    ngettext(
      "%{count} block on this site uses this module.",
      "%{count} blocks on this site use this module.",
      count,
      count: count
    )
  end

  defp affected_line({:sites, count}) do
    ngettext(
      "%{count} site uses this shared module.",
      "%{count} sites use this shared module.",
      count,
      count: count
    )
  end

  @tabs ~w(template overview variables references datasource)a

  defp to_tab(tab), do: Enum.find(@tabs, :template, &(to_string(&1) == tab))

  # Count from the changeset, not from `form[field].value`.
  #
  # That value is a list of structs only while it comes from the changeset data;
  # after a change event has cast the assoc it is an index-keyed params map
  # (`%{"0" => %{...}}`). `length/1` raised on that shape, killing the LiveView
  # mid-render of the tab bar — the client then silently remounted and discarded
  # any unsaved edits, so a just-deleted variable reappeared. The params map is
  # also wrong to count: it still carries entries dropped via `drop_*_ids`.
  # `get_field/2` applies the changes, so it matches what the panels render.
  defp assoc_count(%Phoenix.HTML.Form{source: %Ecto.Changeset{} = changeset}, field) do
    changeset
    |> Ecto.Changeset.get_field(field)
    |> case do
      nil -> 0
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp assoc_count(_form, _field), do: 0

  attr :active_tab, :atom, required: true
  attr :form, :any, required: true

  defp tab_bar(assigns) do
    assigns =
      assign(assigns, :tabs, [
        {:template, gettext("Template"), nil},
        {:overview, gettext("Overview"), nil},
        {:variables, gettext("Variables"), assoc_count(assigns.form, :vars)},
        {:references, gettext("References"), assoc_count(assigns.form, :refs)},
        {:datasource, gettext("Datasource"), nil}
      ])

    ~H"""
    <nav class="module-editor-tabs" role="tablist" aria-label={gettext("Module editor sections")}>
      <button
        :for={{tab, label, count} <- @tabs}
        type="button"
        role="tab"
        class={["module-editor-tab", @active_tab == tab && "is-active"]}
        aria-selected={to_string(@active_tab == tab)}
        phx-click={JS.push("select_tab")}
        phx-value-tab={tab}
      >
        {label}<span :if={count && count > 0} class="module-editor-tab-count">{count}</span>
      </button>
    </nav>
    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, to_tab(tab))}
  end

  def handle_event("save_redirect_target", _, socket) do
    {:noreply, assign(socket, :save_redirect_target, :self)}
  end

  def handle_event("close_item_modal", _, socket) do
    {:noreply, assign(socket, :open_item_modal, nil)}
  end

  ## Sequence event
  def handle_event("create_ref", %{"type" => block_type}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    refs = Changeset.get_assoc(changeset, :refs)

    block_module =
      block_type
      |> String.to_existing_atom()
      |> ContentBlocks.get_block_by_type()

    ref_data = struct(block_module, %{data: build_ref_data(block_module)})

    new_ref =
      %Ref{
        name: unique_identifier(refs, :name, block_type),
        data: ref_data,
        uid: Brando.Utils.generate_uid()
      }
      |> Changeset.change()
      |> Map.put(:action, :insert)

    updated_changeset = Changeset.put_assoc(changeset, :refs, [new_ref | refs])
    updated_form = to_form(updated_changeset, [])

    {:noreply,
     socket
     |> assign(:form, updated_form)
     |> assign(:open_item_modal, :ref)}
  end

  def handle_event("delete_ref", params, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    refs = Changeset.get_assoc(changeset, :refs)
    ref_to_delete = find_assoc(refs, params, :name)

    filtered_refs =
      Enum.reject(refs, fn
        %Changeset{action: :replace} -> true
        ref_cs -> ref_cs == ref_to_delete
      end)

    updated_changeset = Changeset.put_assoc(changeset, :refs, filtered_refs)
    updated_form = to_form(updated_changeset, [])

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("duplicate_ref", params, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    refs = Changeset.get_assoc(changeset, :refs)
    ref_to_dupe = find_assoc(refs, params, :name)

    if ref_to_dupe do
      ref_name = Changeset.get_field(ref_to_dupe, :name)

      new_ref =
        %Ref{
          name: unique_identifier(refs, :name, "#{ref_name}_copy"),
          description: Changeset.get_field(ref_to_dupe, :description),
          data: Changeset.get_field(ref_to_dupe, :data),
          uid: Brando.Utils.generate_uid()
        }
        |> Changeset.change()
        |> Map.put(:action, :insert)

      updated_changeset = Changeset.put_assoc(changeset, :refs, [new_ref | refs])
      updated_form = to_form(updated_changeset, [])

      {:noreply,
       socket
       |> assign(:form, updated_form)
       |> assign(:open_item_modal, :ref)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("create_var", %{"type" => var_type}, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_assoc(changeset, :vars)
    var_type = String.to_existing_atom(var_type)

    new_var =
      %Var{
        key: unique_identifier(vars, :key, to_string(var_type)),
        label: var_type |> to_string() |> Brando.Utils.humanize(),
        type: var_type
      }
      |> Changeset.change()
      |> Map.put(:action, :insert)

    updated_changeset = Changeset.put_assoc(changeset, :vars, [new_var | vars])
    updated_form = to_form(updated_changeset, [])

    {:noreply,
     socket
     |> assign(:form, updated_form)
     |> assign(:open_item_modal, :var)}
  end

  def handle_event("delete_var", params, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_assoc(changeset, :vars)
    var_to_delete = find_assoc(vars, params, :key)
    filtered_vars = Enum.reject(vars, &(&1 == var_to_delete))

    updated_changeset = Changeset.put_assoc(changeset, :vars, filtered_vars)
    updated_form = to_form(updated_changeset, [])

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("duplicate_var", params, %{assigns: %{form: form}} = socket) do
    changeset = form.source
    vars = Changeset.get_assoc(changeset, :vars)
    var_to_dupe = find_assoc(vars, params, :key)

    if var_to_dupe do
      var = Changeset.apply_changes(var_to_dupe)

      new_var =
        var
        |> Map.merge(%{
          id: nil,
          module_id: nil,
          sequence: nil,
          inserted_at: nil,
          updated_at: nil,
          key: unique_identifier(vars, :key, "#{var.key}_copy")
        })
        |> Ecto.put_meta(state: :built)
        |> Changeset.change()
        |> Map.put(:action, :insert)

      updated_changeset = Changeset.put_assoc(changeset, :vars, [new_var | vars])
      updated_form = to_form(updated_changeset, [])

      {:noreply,
       socket
       |> assign(:form, updated_form)
       |> assign(:open_item_modal, :var)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", %{"module" => module_params}, socket) do
    %{current_user: current_user, entry: entry} = socket.assigns

    changeset =
      entry
      |> Brando.Content.Module.changeset(module_params, current_user)
      |> maybe_require_version_note(socket.assigns.shared_library?)

    updated_changeset = %{changeset | action: :update}

    updated_form = to_form(updated_changeset, [])

    socket
    |> assign(:form, updated_form)
    |> then(&{:noreply, &1})
  end

  def handle_event("save", %{"module" => module_params}, socket) do
    case pending_destructive_change(socket, module_params) do
      nil -> do_save(socket, module_params)
      pending -> {:noreply, assign(socket, :pending_destructive_save, pending)}
    end
  end

  def handle_event("cancel_destructive_save", _, socket) do
    {:noreply, assign(socket, :pending_destructive_save, nil)}
  end

  def handle_event("confirm_destructive_save", _, socket) do
    %{params: module_params} = socket.assigns.pending_destructive_save
    do_save(assign(socket, :pending_destructive_save, nil), module_params)
  end

  # Returns what the confirmation dialog needs, or nil when the save may go
  # straight through. The diff is taken against the persisted entry, so it
  # describes exactly the migration this save is about to run.
  defp pending_destructive_change(%{assigns: %{pending_destructive_save: nil}} = socket, module_params) do
    %{current_user: current_user, entry: entry} = socket.assigns
    changeset = Brando.Content.Module.changeset(entry, module_params, current_user)
    diff = ModuleDiff.diff(entry, changeset)

    if ModuleDiff.destructive?(diff) do
      %{
        params: module_params,
        summary: ModuleDiff.summary(diff),
        affected: count_affected(socket)
      }
    end
  end

  defp pending_destructive_change(_socket, _module_params), do: nil

  # A shared module is edited in the public schema, where no tenant's blocks are
  # visible — count the sites it reaches instead, and let the dialog say so.
  defp count_affected(%{assigns: %{shared_library?: true, entry: entry}}) do
    {:sites, length(Brando.Content.SharedLibrary.usage(:module, entry.id))}
  end

  defp count_affected(%{assigns: %{entry: entry}}) do
    {:blocks, length(ContentBlocks.list_block_ids_using_module(entry.id))}
  end

  defp do_save(socket, module_params) do
    user = socket.assigns.current_user
    entry = socket.assigns.entry

    changeset =
      entry
      |> Brando.Content.Module.changeset(module_params, user)
      |> maybe_require_version_note(socket.assigns.shared_library?)

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

    case persist_module(changeset, user, socket.assigns.shared_library?) do
      {:error, :stale} ->
        send(
          self(),
          {:toast,
           gettext(
             "This module was changed by someone else while you were editing. Reload to see their version before saving yours."
           )}
        )

        {:noreply, socket}

      {:ok, entry} ->
        send(self(), {:toast, gettext("Module updated")})

        redirected_socket =
          case socket.assigns.save_redirect_target do
            :self ->
              socket
              |> assign(:entry, entry)
              |> assign(:form, module_form(entry, user, socket.assigns.shared_library?))

            :listing when socket.assigns.shared_library? ->
              push_navigate(socket, to: "/admin/config/content/shared_library")

            :listing ->
              push_navigate(socket, to: "/admin/config/content/modules")
          end

        {:noreply, assign(redirected_socket, :save_redirect_target, :listing)}

      {:error, %Ecto.Changeset{} = changeset} ->
        require Logger

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
        send(self(), {:toast, gettext("Could not save module. Check the highlighted fields.")})

        form = to_form(changeset, [])

        socket
        |> assign(:form, form)
        |> then(&{:noreply, &1})
    end
  end

  # Applies a layout change composed in the variable layout canvas. The canvas
  # is a live component but the module changeset lives here, so it hands back a
  # whole changeset rather than trying to reach into ours.
  def handle_info({:var_layout_changeset, changeset}, socket) do
    {:noreply, assign(socket, :form, to_form(changeset, []))}
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
    assign(socket, :current_user, Brando.Users.get_user_by_session_token(token))
  end

  defp assign_entry(socket, entry_id) do
    assign_new(socket, :entry, fn ->
      if socket.assigns.shared_library? do
        Brando.Content.SharedLibrary.get_shared(:module, entry_id) ||
          raise Ecto.NoResultsError, queryable: Brando.Content.Module
      else
        Brando.Content.get_module!(%{matches: %{id: entry_id}, preload: [:vars, :refs]})
      end
    end)
  end

  defp assign_form(%{assigns: %{entry: entry, current_user: current_user}} = socket) do
    assign_new(socket, :form, fn ->
      module_form(entry, current_user, socket.assigns.shared_library?)
    end)
  end

  defp module_form(entry, current_user, shared_library?) do
    entry
    |> Brando.Content.Module.changeset(%{}, current_user)
    |> then(fn changeset ->
      if shared_library?, do: Changeset.put_change(changeset, :version_note, ""), else: changeset
    end)
    |> to_form([])
  end

  defp maybe_require_version_note(changeset, true),
    do: Changeset.validate_required(changeset, [:version_note])

  defp maybe_require_version_note(changeset, false), do: changeset

  defp maybe_use_public_library_context(%{assigns: %{shared_library?: true}} = socket) do
    Brando.Tenant.put_prefix(nil)
    assign(socket, :tenant_prefix, nil)
  end

  defp maybe_use_public_library_context(socket), do: socket

  # `Brando.Trait.ModuleVersioned` bumps the version under an optimistic lock, so
  # a second editor saving over a revision they never saw raises instead of
  # silently winning. Turn that into an answer this function's caller can render.
  defp persist_module(changeset, user, shared_library?) do
    do_persist_module(changeset, user, shared_library?)
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  defp do_persist_module(changeset, user, true) do
    Brando.Content.SharedLibrary.update_shared(:module, changeset.data.id, changeset, user)
  end

  defp do_persist_module(changeset, user, false), do: Brando.Content.update_module(changeset, user)

  defp build_ref_data(TextBlock) do
    struct(TextBlock.Data, %{styles: TextBlock.Data.default_styles()})
  end

  defp build_ref_data(block_module) do
    struct(Module.concat([block_module, Data]))
  end

  defp find_assoc(assocs, %{"index" => index}, _field) do
    case Integer.parse(to_string(index)) do
      {parsed_index, ""} -> Enum.at(assocs, parsed_index)
      _ -> nil
    end
  end

  defp find_assoc(assocs, %{"id" => identifier}, field) do
    Enum.find(assocs, &(Changeset.get_field(&1, field) == identifier))
  end

  defp unique_identifier(assocs, field, base) do
    identifiers = MapSet.new(assocs, &Changeset.get_field(&1, field))

    Stream.iterate(1, &(&1 + 1))
    |> Enum.find_value(fn
      1 -> if base not in identifiers, do: base
      suffix -> if "#{base}_#{suffix}" not in identifiers, do: "#{base}_#{suffix}"
    end)
  end
end
