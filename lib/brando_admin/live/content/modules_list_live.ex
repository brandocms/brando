defmodule BrandoAdmin.Content.ModuleListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Module, page_title: &__MODULE__.page_title/0
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace
  alias Phoenix.LiveView.JS

  def mount(_, _session, socket) do
    {:ok,
     socket
     |> assign(:base64_modules, nil)
     |> assign(:imported_modules, nil)
     |> assign(:sketches, %{
       available?: Brando.Content.ModuleSketch.available?(),
       missing: [],
       running?: false,
       current: nil,
       done: [],
       failed: []
     })}
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list content-workspace modules-workspace">
      <Workspace.header title={gettext("Block modules")}>
        <%!-- One way in to both: modules as files (DSL), and pasted module copies. --%>
        <details id="module-transfer-menu" class="workspace-menu">
          <summary class="workspace-button">
            {gettext("Import / export")} <.icon name="hero-chevron-down" />
          </summary>
          <div class="workspace-menu-items">
            <button
              type="button"
              phx-click={
                JS.push("open_module_files")
                |> close_transfer_menu()
                |> show_modal("#module-files-modal")
              }
            >
              {gettext("Modules as files")}
              <small>{gettext("Export and import module definitions (DSL)")}</small>
            </button>
            <button
              type="button"
              phx-click={close_transfer_menu() |> show_modal("#module-import-modal")}
            >
              {gettext("Paste encoded modules")}
              <small>{gettext("Import copies of modules from another site")}</small>
            </button>
          </div>
        </details>
        <button
          :if={@sketches.available? and BrandoAdmin.Authorization.allowed?(:update, @schema)}
          type="button"
          class="workspace-button"
          phx-click={JS.push("open_sketches") |> show_modal("#module-sketches-modal")}
        >
          <.icon name="hero-sparkles" /> {gettext("Sketches with AI")}
        </button>
        <button
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          class="workspace-button primary"
          phx-click={JS.push("create_module")}
        >
          {gettext("Create new")}
        </button>
      </Workspace.header>

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={@params}
        listing={:default}
        hidden_filters={[:parent_id]}
        empty_title={gettext("No modules in this view")}
        empty_description={gettext("Adjust your search or create a new entry.")}
      />
    </div>

    <.live_component
      module={BrandoAdmin.Components.ModuleFiles}
      id="module-files"
      current_user={@current_user}
      scope_label={module_files_scope(assigns)}
    />

    <Content.modal title={gettext("Exported modules")} id="module-export-modal">
      <textarea rows="15" style="width: 100%; font-size: 11px; font-family: Mono"><%= @base64_modules %></textarea>
    </Content.modal>

    <Content.modal title={gettext("Sketches with AI")} id="module-sketches-modal" medium>
      <.sketches sketches={@sketches} />
    </Content.modal>

    <Content.modal
      title={gettext("Import modules")}
      id="module-import-modal"
      close={JS.push("reset_import_vars") |> hide_modal("#module-import-modal")}
    >
      <p>
        {gettext(
          "This imports independent module copies with new identities. Use Content transfer in Configuration to move saved content while preserving module lineage."
        )}
      </p>
      <div :if={@imported_modules} class="imported-modules">
        <p>
          {Enum.count(@imported_modules)} {gettext("encoded modules found.")}
        </p>
        <div class="imported-modules mt-2">
          <div :for={m <- @imported_modules} :key={m.id} class="imported-module">
            <.i18n map={m.name} /> — <.i18n map={m.namespace} />
            <div class="module-info">
              <span :if={m.vars != []}>(+{length(m.vars)} {gettext("variables")})</span>
              <span :if={m.refs != []}>(+{length(m.refs)} {gettext("references")})</span>
              <div :for={c <- m.children} :key={c.id} class="module-info-child">
                <.i18n map={c.name} /> — <.i18n map={c.namespace} />
                <div class="module-info-child-info">
                  <span :if={c.vars != []}>(+{length(c.vars)} {gettext("variables")})</span>
                  <span :if={c.refs != []}>(+{length(c.refs)} {gettext("references")})</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <button class="primary mt-2" type="button" phx-click={JS.push("import_modules") |> hide_modal("#module-import-modal")}>
          {gettext("Import modules")}
        </button>
      </div>

      <form :if={!@imported_modules} id="module-import-form" phx-change="validate_module_import">
        <textarea name="encoded_modules" rows="15" style="width: 100%; font-size: 11px; font-family: Mono"></textarea>
      </form>
    </Content.modal>
    """
  end

  # Draw a sketch for every module without one. They are drawn one at a time
  # and each is saved as it arrives, so the list fills in as it goes and an
  # interruption keeps what was drawn.
  def handle_event("open_sketches", _, %{assigns: %{sketches: %{running?: true}}} = socket), do: {:noreply, socket}

  def handle_event("open_sketches", _, socket) do
    {:ok, modules} = Brando.Content.list_modules(%{preload: [:refs, :vars]})
    missing = Enum.filter(modules, &(&1.svg in [nil, ""]))

    {:noreply, update(socket, :sketches, &%{&1 | missing: missing, done: [], failed: [], current: nil})}
  end

  def handle_event("start_sketches", _, %{assigns: %{sketches: %{running?: true}}} = socket), do: {:noreply, socket}

  def handle_event("start_sketches", _, socket) do
    lv = self()
    modules = socket.assigns.sketches.missing

    socket
    |> update(:sketches, &%{&1 | running?: true, done: [], failed: []})
    |> start_async(:sketches, fn ->
      Enum.each(modules, fn module ->
        send(lv, {:sketch_started, module.id})

        result =
          with {:ok, svg} <- Brando.Content.ModuleSketch.generate(module),
               {:ok, _} <- Brando.Content.ModuleSketch.save(module, svg),
               do: :ok

        send(lv, {:sketch_done, module.id, result})
      end)
    end)
    |> then(&{:noreply, &1})
  end

  def handle_event("focus", _, socket), do: {:noreply, socket}
  def handle_event("blur", _, socket), do: {:noreply, socket}

  def handle_event("open_module_files", _, socket) do
    send_update(BrandoAdmin.Components.ModuleFiles, id: "module-files", selected_ids: nil)
    {:noreply, socket}
  end

  def handle_event("export_module_files", %{"ids" => encoded}, socket) do
    ids =
      case if(is_binary(encoded), do: Jason.decode(encoded), else: :error) do
        {:ok, ids} when is_list(ids) and length(ids) <= 500 ->
          Enum.flat_map(ids, fn id ->
            case if(is_integer(id) or is_binary(id), do: Integer.parse(to_string(id)), else: :error) do
              {id, ""} when id > 0 -> [id]
              _ -> []
            end
          end)
          |> Enum.uniq()

        _ ->
          []
      end

    send_update(BrandoAdmin.Components.ModuleFiles, id: "module-files", selected_ids: ids)
    {:noreply, socket}
  end

  def handle_event("validate_module_import", %{"encoded_modules" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_module_import", %{"encoded_modules" => encoded_modules}, socket) do
    imported_modules = Brando.Content.deserialize_modules(encoded_modules)

    {:noreply, assign(socket, :imported_modules, imported_modules)}
  end

  def handle_event("import_modules", _, socket) do
    current_user = socket.assigns.current_user

    # Import modules in a transaction to ensure atomicity
    case import_modules_in_transaction(socket.assigns.imported_modules, current_user) do
      {:ok, _} ->
        send(self(), {:toast, gettext("Modules imported")})
        BrandoAdmin.LiveView.Listing.update_list_entries(socket.assigns.schema)

        {:noreply,
         socket
         |> assign(:imported_modules, nil)
         |> assign(:base64_modules, nil)}

      {:error, reason} ->
        send(self(), {:toast, gettext("Failed to import modules: %{reason}", reason: inspect(reason))})
        {:noreply, socket}
    end
  end

  def handle_event("reset_import_vars", _, socket) do
    {:noreply,
     socket
     |> assign(:imported_modules, nil)
     |> assign(:base64_modules, nil)}
  end

  def handle_event("create_module", _, %{assigns: %{current_user: user}} = socket) do
    params = %{
      name: "New module",
      class: "module new",
      namespace: "general",
      help_text: "Help text",
      code:
        ~s(<article b-tpl="{{ block.class }}">\n  <div class="inner">\n) <>
          "    <!-- \n    (!) reference refs by using {% ref refs.ref_name %} \n" <>
          "    (!) reference vars by using {{ var_name }}\n    -->\n" <>
          "  </div>\n</article>"
    }

    {:ok, new_module} = Brando.Content.create_module(params, user)

    new_module_route =
      Brando.routes().admin_module_form_path(
        socket,
        :update,
        new_module.id
      )

    {:noreply, push_navigate(socket, to: new_module_route)}
  end

  def handle_event("export_modules", %{"ids" => ids_string}, socket) do
    module_ids = Jason.decode!(ids_string)
    current_user = socket.assigns.current_user

    base64_modules =
      %{
        filter: %{ids: module_ids},
        preload: [:vars, :refs, table_template: [:vars], children: [:vars, :refs, table_template: [:vars]]]
      }
      |> then(fn query ->
        Brando.Authorization.Boundary.with_query_action(:export, Brando.Content.Module, fn ->
          Brando.Content.list_modules!(query)
        end)
      end)
      |> Brando.Content.prepare_modules_for_export(current_user.id)
      |> Brando.Content.serialize_modules()

    {:noreply, assign(socket, :base64_modules, base64_modules)}
  end

  defp module_files_scope(assigns) do
    case {assigns[:current_site], assigns[:current_environment]} do
      {%{name: site}, %{name: environment}} -> "#{site} · #{environment}"
      {%{name: site}, %{key: environment}} -> "#{site} · #{environment}"
      _ -> gettext("Current workspace")
    end
  end

  defp import_modules_in_transaction(modules, current_user) do
    Brando.Repo.transaction(fn ->
      for mod <- modules do
        Brando.Content.import_module_with_children(mod, current_user)
      end
    end)
  end

  # "Block modules" as in the menu, not the schema's plural ("Modules").
  @doc false
  def page_title, do: gettext("Block modules")

  # Closes the menu and puts focus on its button first, so a dialog opened
  # from the menu gives focus back to something still on screen.
  defp close_transfer_menu(js \\ %JS{}) do
    js
    |> JS.remove_attribute("open", to: "#module-transfer-menu")
    |> JS.focus(to: "#module-transfer-menu > summary")
  end

  def handle_async(:sketches, _result, socket),
    do: {:noreply, update(socket, :sketches, &%{&1 | running?: false, current: nil})}

  def handle_info({:sketch_started, id}, socket), do: {:noreply, update(socket, :sketches, &%{&1 | current: id})}

  def handle_info({:sketch_done, id, :ok}, socket) do
    BrandoAdmin.LiveView.Listing.update_list_entries(socket.assigns.schema)
    {:noreply, update(socket, :sketches, &%{&1 | done: &1.done ++ [id]})}
  end

  def handle_info({:sketch_done, id, {:error, reason}}, socket) do
    message = if is_atom(reason), do: Brando.AI.error_message(reason), else: gettext("Could not save the sketch")
    {:noreply, update(socket, :sketches, &%{&1 | failed: &1.failed ++ [{id, message}]})}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  attr :sketches, :map, required: true

  defp sketches(assigns) do
    assigns =
      assign(assigns,
        total: length(assigns.sketches.missing),
        finished: length(assigns.sketches.done) + length(assigns.sketches.failed),
        failed: Map.new(assigns.sketches.failed)
      )

    ~H"""
    <div class="module-sketches">
      <p :if={@total == 0}>{gettext("Every module has a sketch.")}</p>
      <%= if @total > 0 do %>
        <p>
          {ngettext(
            "One module has no sketch. The AI draws it from its template, references and variables, and it is saved at once. You can redraw or edit it in the module afterwards.",
            "%{count} modules have no sketch. The AI draws each from its template, references and variables, one at a time, and each is saved as it arrives. You can redraw or edit any of them in the module afterwards.",
            @total
          )}
        </p>
        <ol class="module-sketches-list">
          <li
            :for={module <- @sketches.missing}
            :key={module.id}
            class={[
              module.id == @sketches.current && "is-current",
              module.id in @sketches.done && "is-done",
              Map.has_key?(@failed, module.id) && "is-failed"
            ]}
          >
            <span class="state">
              <.icon :if={module.id in @sketches.done} name="hero-check" />
              <.icon :if={Map.has_key?(@failed, module.id)} name="hero-x-mark" />
              <.icon :if={module.id == @sketches.current} name="hero-arrow-path" />
            </span>
            <span class="name"><.i18n map={module.name} /></span>
            <span :if={@failed[module.id]} class="error">{@failed[module.id]}</span>
          </li>
        </ol>
        <p :if={@sketches.running?} class="module-sketches-progress">
          {gettext("Drawing %{done} of %{total}…", done: @finished + 1, total: @total)}
        </p>
        <p :if={!@sketches.running? and @finished == @total} class="module-sketches-progress">
          {gettext("Done: %{ok} drawn, %{failed} failed.", ok: length(@sketches.done), failed: length(@sketches.failed))}
        </p>
      <% end %>
    </div>
    <div :if={@total > 0 and @finished < @total} class="module-sketches-actions">
      <button type="button" class="primary" phx-click="start_sketches" disabled={@sketches.running?}>
        {ngettext("Draw one sketch", "Draw %{count} sketches", @total)}
      </button>
    </div>
    """
  end
end
