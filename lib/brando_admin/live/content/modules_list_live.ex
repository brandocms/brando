defmodule BrandoAdmin.Content.ModuleListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Content.Module
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.JS

  def mount(_, _session, socket) do
    {:ok,
     socket
     |> assign(:base64_modules, nil)
     |> assign(:imported_modules, nil)}
  end

  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Content Modules")} subtitle={gettext("Overview")}>
      <button class="stealth" phx-click={show_modal("#module-import-modal")}>
        {gettext("Import modules")}
      </button>
      <button class="primary" phx-click={JS.push("create_module")}>
        {gettext("Create new")}
      </button>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />

    <Content.modal title={gettext("Exported modules")} id="module-export-modal">
      <textarea rows="15" style="width: 100%; font-size: 11px; font-family: Mono"><%= @base64_modules %></textarea>
    </Content.modal>

    <Content.modal
      title={gettext("Import modules")}
      id="module-import-modal"
      close={JS.push("reset_import_vars") |> hide_modal("#module-import-modal")}
    >
      <div :if={@imported_modules} class="imported-modules">
        <p>
          {Enum.count(@imported_modules)} {gettext("encoded modules found.")}
        </p>
        <div class="imported-modules mt-2">
          <div :for={m <- @imported_modules} class="imported-module">
            <.i18n map={m.name} /> — <.i18n map={m.namespace} />
            <div class="module-info">
              <span :if={m.vars != []}>(+{length(m.vars)} {gettext("variables")})</span>
              <span :if={m.refs != []}>(+{length(m.refs)} {gettext("references")})</span>
              <div :for={c <- m.children} class="module-info-child">
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

  def handle_event("validate_module_import", %{"encoded_modules" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_module_import", %{"encoded_modules" => encoded_modules}, socket) do
    imported_modules = Brando.Content.deserialize_modules(encoded_modules)

    {:noreply, assign(socket, :imported_modules, imported_modules)}
  end

  def handle_event("import_modules", _, socket) do
    # Import modules in a transaction to ensure atomicity
    case Brando.Repo.transaction(fn ->
           for mod <- socket.assigns.imported_modules do
             Brando.Content.import_module_with_children(mod)
           end
         end) do
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
      %{filter: %{ids: module_ids}, preload: [:vars, children: [:vars]]}
      |> Brando.Content.list_modules!()
      |> Brando.Content.prepare_modules_for_export(current_user.id)
      |> Brando.Content.serialize_modules()

    {:noreply, assign(socket, :base64_modules, base64_modules)}
  end
end
