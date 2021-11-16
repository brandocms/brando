defmodule BrandoAdmin.Components.Form do
  use BrandoAdmin, :live_component
  use BrandoAdmin.Translator, "forms"

  import Brando.Gettext
  import Ecto.Changeset
  import Phoenix.HTML.Form
  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 3]

  alias Brando.Villain

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.MetaDrawer
  alias BrandoAdmin.Components.Form.RevisionsDrawer
  alias BrandoAdmin.Components.Form.ScheduledPublishingDrawer
  alias BrandoAdmin.Components.Form.Input.Blocks.Utils

  def mount(socket) do
    {:ok,
     socket
     |> assign(:edit_image, %{path: [], field: nil, relation_field: nil})
     |> assign(:image_changeset, nil)
     |> assign(:initial_update, true)
     |> assign(:has_meta?, false)
     |> assign(:status_revisions, :closed)
     |> assign(:processing, false)
     |> assign(:live_preview_active?, false)
     |> assign(:live_preview_cache_key, nil)}
  end

  def update(
        %{updated_entry: updated_entry},
        %{assigns: %{schema: schema, current_user: current_user}} = socket
      ) do
    new_changeset = schema.changeset(updated_entry, %{}, current_user, skip_villain: true)

    {:ok,
     socket
     |> assign(:changeset, new_changeset)
     |> force_svelte_remounts()}
  end

  def update(%{updated_changeset: updated_changeset}, socket) do
    {:ok, assign(socket, :changeset, updated_changeset)}
  end

  def update(%{edit_image: %{image: nil} = edit_image}, socket) do
    image_changeset = Ecto.Changeset.change(%Brando.Images.Image{})

    {:ok,
     socket
     |> assign(:edit_image, edit_image)
     |> assign(:image_changeset, image_changeset)}
  end

  def update(%{edit_image: %{image: image} = edit_image}, socket) do
    image_changeset = Ecto.Changeset.change(image)

    {:ok,
     socket
     |> assign(:edit_image, edit_image)
     |> assign(:image_changeset, image_changeset)}
  end

  def update(
        %{updated_gallery_image: %{path: path} = updated_gallery_image, key: key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    images =
      changeset
      |> Ecto.Changeset.get_field(key)
      |> Enum.map(fn
        %{path: ^path} -> updated_gallery_image
        img -> img
      end)

    updated_changeset = Ecto.Changeset.put_change(changeset, key, images)

    {:ok,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:processing, false)}
  end

  def update(assigns, socket) do
    form_name = assigns[:name] || :default

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:entry_id, fn -> nil end)
     |> assign_new(:blueprint, fn -> assigns.schema.__blueprint__() end)
     |> assign_new(:singular, fn -> assigns.schema.__naming__().singular end)
     |> assign_new(:context, fn -> assigns.schema.__modules__().context end)
     |> assign_new(:form, fn ->
       case assigns.schema.__form__(form_name) do
         nil ->
           raise Brando.Exception.BlueprintError,
             message: "Missing `#{form_name}` form declaration for `#{inspect(assigns.schema)}`"

         form ->
           form
       end
     end)
     |> assign_entry()
     |> assign_addon_statuses()
     |> assign_default_params()
     |> extract_tab_names()
     |> assign_changeset()
     |> maybe_assign_uploads()}
  end

  defp assign_entry(%{assigns: %{entry_id: nil}} = socket) do
    assign_new(socket, :entry, fn -> nil end)
  end

  defp assign_entry(
         %{
           assigns: %{
             schema: schema,
             entry_id: entry_id,
             singular: singular,
             context: context,
             form: form
           }
         } = socket
       ) do
    query_params =
      entry_id
      |> form.query.()
      |> add_preloads(schema)

    assign_new(socket, :entry, fn -> apply(context, :"get_#{singular}!", [query_params]) end)
  end

  defp maybe_assign_uploads(socket) do
    if connected?(socket) && socket.assigns[:initial_update] do
      socket
      |> assign(:initial_update, false)
      |> allow_uploads()
    else
      socket
    end
  end

  defp add_preloads(%{preload: preloads} = query_params, schema) do
    image_preloads = schema.__assets__ |> Enum.filter(&(&1.type == :image)) |> Enum.map(& &1.name)
    Map.put(query_params, :preload, image_preloads ++ preloads)
  end

  defp add_preloads(query_params, schema) do
    image_preloads = schema.__assets__ |> Enum.filter(&(&1.type == :image)) |> Enum.map(& &1.name)
    Map.put(query_params, :preload, image_preloads)
  end

  defp assign_addon_statuses(%{assigns: %{schema: schema}} = socket) do
    assign(socket,
      has_meta?: schema.has_trait(Brando.Trait.Meta),
      has_revisioning?: schema.has_trait(Brando.Trait.Revisioned),
      has_scheduled_publishing?: schema.has_trait(Brando.Trait.ScheduledPublishing),
      has_live_preview?: check_live_preview(schema)
    )
  end

  defp check_live_preview(schema) do
    function_exported?(Brando.live_preview(), :__info__, 1) &&
      {:render, 3} in Brando.live_preview().__info__(:functions) &&
      Brando.live_preview().has_preview_target(schema)
  end

  defp assign_default_params(%{assigns: %{initial_params: initial_params}} = socket)
       when not is_nil(initial_params) and map_size(initial_params) > 0 do
    assign_new(socket, :default_params, fn -> initial_params end)
  end

  defp assign_default_params(%{assigns: %{form: %{default_params: %{}}}} = socket) do
    assign_new(socket, :default_params, fn -> %{} end)
  end

  defp assign_default_params(%{assigns: %{form: %{default_params: default_params}}} = socket) do
    assign_new(socket, :default_params, fn ->
      default_params
      |> Code.eval_quoted()
      |> elem(0)
    end)
  end

  defp assign_default_params(%{assigns: %{name: name, schema: schema}}) do
    raise Brando.Exception.BlueprintError,
      message: "Missing form `#{inspect(name)}` for `#{inspect(schema)}`"
  end

  defp force_svelte_remounts(socket) do
    push_event(socket, "b:component:remount", %{})
  end

  defp extract_tab_names(%{assigns: %{form: %{tabs: tabs}}} = socket) do
    first_tab = List.first(tabs)

    socket
    |> assign_new(:active_tab, fn -> Map.get(first_tab, :name) end)
    |> assign_new(:tabs, fn -> Enum.map(tabs, & &1.name) end)
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}-el"}
      class="brando-form b-rendered"
      data-moonwalk-run="brandoForm"
      phx-hook="Brando.Form">

      <!-- TODO: extract to Form.Tabs. How do we handle the open_meta_drawers etc? :builtins slot? -->
      <div class="form-tabs">
        <div class="form-tab-customs">
          <%= for tab <- @tabs do %>
            <button
              type="button"
              class={render_classes([active: @active_tab == tab])}
              phx-click={JS.push("select_tab", target: @myself)}
              phx-value-name={tab}>
              <%= g(@schema, tab) %>
            </button>
          <% end %>
        </div>

        <div class="form-tab-builtins">
          <%= if @has_meta? do %>
            <button
              phx-click={toggle_drawer("##{@id}-meta-drawer")}
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.9 2.1l9.899 1.415 1.414 9.9-9.192 9.192a1 1 0 0 1-1.414 0l-9.9-9.9a1 1 0 0 1 0-1.414L10.9 2.1zm.707 2.122L3.828 12l8.486 8.485 7.778-7.778-1.06-7.425-7.425-1.06zm2.12 6.364a2 2 0 1 1 2.83-2.829 2 2 0 0 1-2.83 2.829z"/></svg>
              <span class="tab-text">Meta</span>
            </button>
          <% end %>
          <%= if @has_revisioning? do %>
            <button
              phx-click={JS.push("toggle_revisions_drawer_status", target: @myself) |> toggle_drawer("##{@id}-revisions-drawer")}
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M7.105 15.21A3.001 3.001 0 1 1 5 15.17V8.83a3.001 3.001 0 1 1 2 0V12c.836-.628 1.874-1 3-1h4a3.001 3.001 0 0 0 2.895-2.21 3.001 3.001 0 1 1 2.032.064A5.001 5.001 0 0 1 14 13h-4a3.001 3.001 0 0 0-2.895 2.21zM6 17a1 1 0 1 0 0 2 1 1 0 0 0 0-2zM6 5a1 1 0 1 0 0 2 1 1 0 0 0 0-2zm12 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2z"/></svg>
              <span class="tab-text"><%= gettext "Revisions" %></span>
            </button>
          <% end %>
          <%= if @has_scheduled_publishing? do %>
            <button
              phx-click={toggle_drawer("##{@id}-scheduled-publishing-drawer")}
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M17 3h4a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h4V1h2v2h6V1h2v2zm-2 2H9v2H7V5H4v4h16V5h-3v2h-2V5zm5 6H4v8h16v-8zM6 14h2v2H6v-2zm4 0h8v2h-8v-2z"/></svg>
              <span class="tab-text"><%= gettext "Scheduled publishing" %></span>
            </button>
          <% end %>
          <%= if @has_live_preview? do %>
            <button
              phx-click={JS.push("open_live_preview", target: @myself)}
              class={render_classes([active: @live_preview_active?])}
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 3c5.392 0 9.878 3.88 10.819 9-.94 5.12-5.427 9-10.819 9-5.392 0-9.878-3.88-10.819-9C2.121 6.88 6.608 3 12 3zm0 16a9.005 9.005 0 0 0 8.777-7 9.005 9.005 0 0 0-17.554 0A9.005 9.005 0 0 0 12 19zm0-2.5a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9zm0-2a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/></svg>
            </button>
            <button
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M11 2.05v2.012A8.001 8.001 0 0 0 12 20a8.001 8.001 0 0 0 7.938-7h2.013c-.502 5.053-4.766 9-9.951 9-5.523 0-10-4.477-10-10 0-5.185 3.947-9.449 9-9.95zm9 3.364l-8 8L10.586 12l8-8H14V2h8v8h-2V5.414z"/></svg>
            </button>
          <% end %>
          <button
            phx-click={JS.push("push_submit_event", target: @myself)}
            type="button">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M7 19v-6h10v6h2V7.828L16.172 5H5v14h2zM4 3h13l4 4v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm5 12v4h6v-4H9z"/></svg>
            <span class="tab-text">(⌘S)</span>
          </button>
        </div>
      </div>

      <.image_picker
        id={"image-picker"}
        schema={@schema}
        path={@edit_image.path}
        field={@edit_image.field}
        select_image={JS.push("select_image", target: @myself) |> toggle_drawer("#image-picker")} />

      <.image_drawer {assigns} />

      <.form
        for={@changeset}
        let={f}
        phx-target={@myself}
        phx-submit={JS.push("save", target: @myself)}
        phx-change={JS.push("validate", target: @myself)}>

        <%= if @has_meta? do %>
          <MetaDrawer.render
            id={"#{@id}-meta-drawer"}
            form={f}
            uploads={@uploads}
            close={toggle_drawer("##{@id}-meta-drawer")} />
        <% end %>

        <%= if @has_revisioning? do %>
          <.live_component module={RevisionsDrawer}
            id={"#{@id}-revisions-drawer"}
            current_user={@current_user}
            form={f}
            status={@status_revisions}
            close={JS.push("toggle_revisions_drawer_status", target: @myself) |> toggle_drawer("##{@id}-revisions-drawer")} />
        <% end %>

        <%= if @has_scheduled_publishing? do %>
          <ScheduledPublishingDrawer.render
            id={"#{@id}-scheduled-publishing-drawer"}
            form={f}
            close={toggle_drawer("##{@id}-scheduled-publishing-drawer")} />
        <% end %>

        <%= for {tab, _tab_idx} <- Enum.with_index(@form.tabs) do %>
          <div
            class={render_classes(["form-tab", active: @active_tab == tab.name])}
            data-tab-name={tab.name}>
            <div class="row">
              <%= for {fieldset, fs_idx} <- Enum.with_index(tab.fields) do %>
                <Fieldset.render
                  id={"#{f.id}-fieldset-#{tab.name}-#{fs_idx}"}
                  translations={@schema.__translations__}
                  relations={@schema.__relations__}
                  form={f}
                  fieldset={fieldset}
                  uploads={@uploads}
                  current_user={@current_user} />
              <% end %>
            </div>
          </div>
        <% end %>

        <.submit_button
          processing={@processing}
          form_id={@id}
          label={gettext("Save (⌘S)")}
          class="primary submit-button" />
      </.form>
    </div>
    """
  end

  def image_drawer(assigns) do
    ~H"""
    <Content.drawer id={"image-drawer"} title={"Image"} close={close_image()} z={1001} narrow>
      <%= if @image_changeset do %>
        <.form
          id="image-drawer-form"
          for={@image_changeset}
          let={image_form}
          phx-submit={JS.push("save_image", target: @myself)}
          phx-change={JS.push("validate_image", target: @myself)}
          phx-target={@myself}>
          <div
            class="image-drawer-preview"
            phx-drop-target={@uploads[@edit_image.field].ref}>
            <%= if @edit_image.image do %>
            <figure class="grid-overlay">
              <%#
              <.live_component
                module={FocalPoint}
                id="image-drawer-focal"
                form={@form}
                field_name={@field}
                focal={@focal} />
              %>
              <img
                width={@edit_image.image.width}
                height={@edit_image.image.height}
                src={Brando.Utils.img_url(@edit_image.image, :original, prefix: Brando.Utils.media_url())} />
            </figure>
            <% else %>
            <div class="img-placeholder">
              <div class="placeholder-wrapper">
                <div class="svg-wrapper">
                  <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                    <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none"/>
                    <polygon class="plus" points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"/>
                    <path d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z" transform="translate(0 0)"/>
                    <circle cx="8" cy="9" r="2"/>
                  </svg>
                </div>
              </div>
            </div>
            <% end %>
          </div>

          <div class="button-group vertical">
            <div class="file-input-button">
              <span class="label">
                <%= gettext "Upload image" %>
              </span>
              <%= live_file_input @uploads[@edit_image.field] %>
            </div>
            <button
              class="secondary"
              type="button"
              phx-click={toggle_drawer("#image-picker")}>
              <%= gettext "Select existing image" %>
            </button>

            <button
              class="secondary"
              type="button"
              phx-click={reset_image_field(@myself)}>
              <%= gettext "Reset image field" %>
            </button>
          </div>
          <%= if @edit_image.image do %>
            <div class="brando-input">
              <Input.Text.render field={:title} form={image_form} />
            </div>

            <div class="brando-input">
              <Input.Text.render field={:credits} form={image_form} />
            </div>

            <div class="brando-input">
              <Input.Text.render field={:alt} form={image_form} />
            </div>
          <% end %>
        </.form>
      <% end %>
    </Content.drawer>
    """
  end

  def reset_image_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_image_field", target: target)
    |> toggle_drawer("#image-drawer")
  end

  def image_picker(assigns) do
    resolved_path = Enum.join(assigns.path ++ [assigns.field], ".")

    assigns =
      assign_new(assigns, :images, fn ->
        {:ok, images} =
          Brando.Images.list_images(%{
            filter: %{config_target: {assigns.schema, resolved_path}},
            order: "desc id"
          })

        images
      end)

    ~H"""
    <Content.drawer id={@id} title={gettext "Select image"} close={toggle_drawer("##{@id}")} z={1002} dark>
      <:info>
        <%= gettext "Select similarly typed image from library" %>
      </:info>
      <div class="image-picker">
        <%= for image <- @images do %>
        <div class="image-picker__image" phx-click={@select_image} phx-value-id={image.id}>
          <img
            width="25"
            height="25"
            src={"#{Brando.Utils.img_url(image, :original, prefix: Brando.Utils.media_url())}"} />
        </div>
        <% end %>
      </div>
    </Content.drawer>
    """
  end

  def allow_uploads(socket) do
    image_fields = socket.assigns.schema.__image_fields__()
    gallery_fields = socket.assigns.schema.__gallery_fields__()

    socket_with_image_uploads =
      Enum.reduce(image_fields, socket, fn img_field, updated_socket ->
        allow_upload(updated_socket, img_field.name,
          accept: :any,
          auto_upload: true,
          progress: &__MODULE__.handle_image_progress/3
        )
      end)

    socket_with_gallery_uploads =
      Enum.reduce(gallery_fields, socket_with_image_uploads, fn gallery_field, updated_socket ->
        allow_upload(updated_socket, gallery_field.name,
          # TODO: Read max_entries from gallery config!
          max_entries: 10,
          accept: :any,
          auto_upload: true,
          progress: &__MODULE__.handle_gallery_progress/3
        )
      end)

    # fallback to nil if no uploads
    assign_new(socket_with_gallery_uploads, :uploads, fn -> nil end)
  end

  def close_image(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#image-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#image-drawer")
  end

  # this.$form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))

  def handle_event(
        "reset_image_field",
        _,
        %{
          assigns: %{
            changeset: changeset,
            edit_image: %{path: path, relation_field: relation_field} = edit_image
          }
        } = socket
      ) do
    full_path = path ++ [relation_field]

    updated_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> nil end)

    updated_edit_image = Map.put(edit_image, :image, nil)

    {:noreply,
     socket
     |> assign(:image_changeset, nil)
     |> assign(:edit_image, updated_edit_image)
     |> assign(:changeset, updated_changeset)}
  end

  def handle_event(
        "select_image",
        %{"id" => selected_image_id},
        %{
          assigns: %{
            changeset: changeset,
            edit_image: %{path: path, relation_field: relation_field} = edit_image
          }
        } = socket
      ) do
    {:ok, image} = Brando.Images.get_image(selected_image_id)

    full_path = path ++ [relation_field]

    updated_changeset =
      EctoNestedChangeset.update_at(changeset, full_path, fn _ -> selected_image_id end)

    updated_edit_image = Map.put(edit_image, :image, image)
    image_changeset = Ecto.Changeset.change(image)

    {:noreply,
     socket
     |> assign(:edit_image, updated_edit_image)
     |> assign(:image_changeset, image_changeset)
     |> assign(:changeset, updated_changeset)}
  end

  def handle_event(
        "validate_image",
        %{"image" => image_params},
        %{assigns: %{edit_image: %{image: image}, current_user: current_user}} = socket
      ) do
    validated_changeset =
      image
      |> Brando.Images.Image.changeset(image_params, current_user)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, image_changeset: validated_changeset)}
  end

  def handle_event("validate_image", _, socket) do
    require Logger
    Logger.error("Validate image with no image param!")
    {:noreply, socket}
  end

  def handle_event(
        "save_image",
        %{"image" => image_params},
        %{
          assigns: %{
            id: form_id,
            changeset: changeset,
            edit_image:
              %{
                image: image,
                path: path,
                relation_field: relation_field
              } = edit_image,
            current_user: current_user
          }
        } = socket
      ) do
    validated_changeset =
      image
      |> Brando.Images.Image.changeset(image_params, current_user)
      |> Map.put(:action, :update)

    {:ok, updated_image} = Brando.Images.update_image(validated_changeset, current_user)
    edit_image = Map.put(edit_image, :image, updated_image)

    full_path = path ++ [relation_field]

    nilled_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> nil end)
    updated_changeset = EctoNestedChangeset.update_at(changeset, full_path, fn _ -> image.id end)

    send_update_after(
      __MODULE__,
      [id: form_id, updated_changeset: updated_changeset],
      1000
    )

    {:noreply,
     assign(socket,
       changeset: nilled_changeset,
       image_changeset: validated_changeset,
       edit_image: edit_image
     )}
  end

  # without image in params
  def handle_event("save_image", _, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "open_live_preview",
        _,
        %{assigns: %{changeset: changeset, schema: schema}} = socket
      ) do
    # initialize
    case Brando.LivePreview.initialize(schema, changeset) do
      {:ok, cache_key} ->
        {:noreply,
         socket
         |> assign(:live_preview_active?, true)
         |> assign(:live_preview_cache_key, cache_key)
         |> push_event("b:live_preview", %{cache_key: cache_key})}

      {:error, err} ->
        {:noreply,
         socket |> push_event("b:alert", %{title: "Live Preview error", message: inspect(err)})}
    end
  end

  def handle_event("push_submit_event", _, socket) do
    {:noreply, push_event(socket, "b:submit", %{})}
  end

  def handle_event("toggle_revisions_drawer_status", _, socket) do
    if Ecto.Changeset.get_field(socket.assigns.changeset, :id) do
      {:noreply,
       socket
       |> assign(
         :status_revisions,
         (socket.assigns.status_revisions == :open && :closed) || :open
       )}
    else
      error_title = "Notice"

      error_msg =
        "To create and administrate revisions, the entry must be saved at least one time first."

      {:noreply, push_event(socket, "b:alert", %{title: error_title, message: error_msg})}
    end
  end

  def handle_event("select_tab", %{"name" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event(
        "validate",
        params,
        %{
          assigns: %{
            schema: schema,
            entry: entry,
            current_user: current_user,
            singular: singular,
            live_preview_active?: live_preview_active?,
            live_preview_cache_key: live_preview_cache_key
          }
        } = socket
      ) do
    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset =
      entry_or_default
      |> schema.changeset(entry_params, current_user, skip_villain: true)
      |> Map.put(:action, :validate)

    if live_preview_active? do
      Brando.LivePreview.update(schema, changeset, live_preview_cache_key)
    end

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event(
        "save",
        params,
        %{
          assigns: %{
            schema: schema,
            entry: entry,
            current_user: current_user,
            singular: singular,
            form: form
          }
        } = socket
      ) do
    entry_params = Map.get(params, singular)
    entry_or_default = entry || struct(schema)

    changeset =
      entry_or_default
      |> schema.changeset(entry_params, current_user)
      |> Map.put(:action, :update)

    # clear out deleted villain blocks
    # one day i will figure out why this is neccessary...
    new_changeset = Villain.reject_blocks_marked_as_deleted(schema, changeset)

    case new_changeset.valid? do
      true ->
        send(self(), {:save, new_changeset, form})
        {:noreply, socket}

      false ->
        {:noreply,
         socket
         |> assign(changeset: new_changeset)
         |> push_errors(new_changeset, form)}
    end
  end

  defp push_errors(socket, changeset, form) do
    error_title = gettext("Error")
    error_notice = gettext("Error while saving form. Please correct marked fields and resubmit")

    traversed_errors =
      traverse_errors(changeset, fn
        {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
        msg -> msg
      end)

    error_keys = Map.keys(traversed_errors)

    tab_with_first_error =
      error_keys
      |> List.first()
      |> Brando.Blueprint.Form.get_tab_for_field(form)

    error_msg = """
    #{error_notice}<br>
    <br>
    Fields marked invalid:<br><br>
    #{inspect(error_keys, pretty: true)}
    """

    socket
    |> assign(:active_tab, tab_with_first_error)
    |> push_event("b:alert", %{title: error_title, message: error_msg})
    |> push_event("b:scroll_to_first_error", %{})
  end

  def handle_gallery_progress(
        key,
        upload_entry,
        %{
          assigns: %{
            changeset: changeset,
            schema: schema,
            current_user: current_user,
            id: form_id
          }
        } = socket
      ) do
    if upload_entry.done? do
      %{cfg: cfg} = schema.__asset_opts__(key)

      {:ok, image_struct} =
        consume_uploaded_entry(
          socket,
          upload_entry,
          fn meta ->
            Brando.Upload.handle_upload(meta, upload_entry, cfg, current_user)
          end
        )

      pid = self()

      Task.start_link(fn ->
        {:ok, image_struct} = Brando.Upload.process_upload(image_struct, cfg, current_user)

        send_update(pid, __MODULE__,
          id: form_id,
          key: key,
          updated_gallery_image: image_struct
        )
      end)

      existing_images = get_field(changeset, key)

      {:noreply,
       socket
       |> update_changeset(key, [image_struct | existing_images])}
    else
      {:noreply, socket}
    end
  end

  def handle_image_progress(
        key,
        upload_entry,
        %{
          assigns: %{
            schema: schema,
            edit_image: edit_image,
            current_user: current_user
          }
        } = socket
      ) do
    if upload_entry.done? do
      relation_key = String.to_existing_atom("#{key}_id")
      %{cfg: cfg} = schema.__asset_opts__(key)
      config_target = "image:#{inspect(schema)}:#{key}"

      {:ok, image} =
        consume_uploaded_entry(
          socket,
          upload_entry,
          fn meta ->
            Brando.Upload.handle_upload(
              Map.put(meta, :config_target, config_target),
              upload_entry,
              cfg,
              current_user
            )
          end
        )

      Brando.Images.Processing.queue_processing(image, current_user)

      image_changeset = Ecto.Changeset.change(image)
      edit_image = Map.put(edit_image, :image, image)

      {:noreply,
       socket
       |> update_changeset(relation_key, image.id)
       |> assign(:edit_image, edit_image)
       |> assign(:image_changeset, image_changeset)}
    else
      {:noreply, socket}
    end
  end

  def assign_changeset(
        %{
          assigns: %{
            default_params: default_params,
            entry: nil,
            schema: schema,
            current_user: current_user
          }
        } = socket
      ) do
    assign_new(socket, :changeset, fn ->
      # this is the initial assignment of changeset with an empty entry,
      # so we add default_params here
      schema.changeset(struct(schema), default_params, current_user, skip_villain: true)
    end)
  end

  def assign_changeset(
        %{assigns: %{entry: entry, schema: schema, current_user: current_user}} = socket
      ) do
    assign_new(socket, :changeset, fn ->
      schema.changeset(entry, %{}, current_user, skip_villain: true)
    end)
  end

  def update_changeset(%{assigns: %{changeset: changeset}} = socket, key, list)
      when is_list(list) do
    new_changeset = put_change(changeset, key, Enum.map(list, &Map.from_struct/1))
    assign(socket, :changeset, new_changeset)
  end

  def update_changeset(%{assigns: %{changeset: changeset}} = socket, key, value)
      when is_map(value) do
    new_changeset = put_change(changeset, key, Map.from_struct(value))
    assign(socket, :changeset, new_changeset)
  end

  def update_changeset(%{assigns: %{changeset: changeset}} = socket, key, value) do
    new_changeset = put_change(changeset, key, value)
    assign(socket, :changeset, new_changeset)
  end

  ##
  ## Function components

  def inputs(assigns) do
    assigns = assign_new(assigns, :opts, fn -> [] end)

    ~H"""
    <%= for {form, index} <- Enum.with_index(inputs_for(@form, @for, @opts)) do %>
      <%= render_slot(@inner_block, %{form: form, index: index}) %>
    <% end %>
    """
  end

  def map_inputs(assigns) do
    subform = Utils.form_for_map(assigns.form, assigns.for)
    input_value = input_value(assigns.form, assigns.for)

    assigns =
      assigns
      |> assign(:subform, subform)
      |> assign(:input_value, input_value)

    ~H"""
    <%= if @input_value do %>
      <%= for {map_key, map_value} <- @input_value do %>
        <%= render_slot @inner_block, %{
          name: "#{@form.name}[#{@for}][#{map_key}]",
          key: map_key,
          value: map_value,
          subform: @subform
        } %>
      <% end %>
    <% end %>
    """
  end

  def map_value_inputs(assigns) do
    subform = Utils.form_for_map_value(assigns.form, assigns.for)
    input_value = subform.data

    assigns =
      assigns
      |> assign(:subform, subform)
      |> assign(:input_value, input_value)

    ~H"""
    <%= for {map_key, map_value} <- @input_value do %>
      <%= render_slot @inner_block, %{
        name: "#{@subform.name}[#{map_key}]",
        key: map_key,
        value: map_value,
        subform: @subform
      } %>
    <% end %>
    """
  end

  def poly_inputs(assigns) do
    assigns =
      assigns
      |> assign(:input_value, input_value(assigns.form, assigns.for))
      |> assign_new(:opts, fn -> [] end)

    ~H"""
    <%= for {f, index} <- Enum.with_index(inputs_for_poly(@form, @for, @opts)) do %>
      <%= render_slot @inner_block, %{
        form: f,
        index: index
      } %>
    <% end %>
    """
  end

  def array_inputs(assigns) do
    assigns = assign(assigns, :input_value, input_value(assigns.form, assigns.for))

    ~H"""
    <%= if @input_value do %>
      <%= for {array_value, array_index} <- Enum.with_index(@input_value) do %>
        <%= render_slot @inner_block, %{
          name: "#{@form.name}[#{@for}][]",
          index: array_index,
          value: array_value} %>
      <% end %>
    <% end %>
    """
  end

  def array_inputs_from_data(assigns) do
    checked_values = input_value(assigns.form, assigns.for) || []
    assigns = assign(assigns, :checked_values, Enum.map(checked_values, &to_string(&1)))

    ~H"""
    <%= for {option, idx} <- Enum.with_index(@options) do %>
      <%= render_slot @inner_block, %{
        name: "#{@form.name}[#{@for}][]",
        id: "#{@form.id}-#{@for}-#{idx}",
        index: idx,
        value: option.value,
        label: option.label,
        checked: option.value in @checked_values
      } %>
    <% end %>
    """
  end

  def submit_button(assigns) do
    ~H"""
    <button
      id={"#{@form_id}-submit"}
      type="button"
      disabled={@processing}
      data-processing={@processing}
      data-form-id={@form_id}
      class={@class}
      phx-hook="Brando.Submit">
      <%= if @processing do %>
        <div class="processing">
          <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z"/></svg>
          Processing image(s)
        </div>
      <% else %>
        <%= @label %>
      <% end %>
    </button>
    """
  end

  def label(assigns) do
    assigns = assign(assigns, input_id: Phoenix.HTML.Form.input_id(assigns.form, assigns.field))

    ~H"""
    <label class={@class} for={@input_id}>
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  # def input(assigns) do
  #   translations = get_in(assigns.blueprint.translations, [:fields, assigns.input.name]) || []

  #   label = Keyword.get(translations, :label)

  #   instructions =
  #     case Keyword.get(translations, :instructions) do
  #       nil -> nil
  #       val -> raw(val)
  #     end

  #   assigns =
  #     assigns
  #     |> assign(:component_id, fn ->
  #       Enum.join(
  #         [assigns.form.id, assigns.input.name],
  #         "-"
  #       )
  #     end)
  #     |> assign(:component_module, fn ->
  #       case assigns.input.type do
  #         {:component, module} ->
  #           module

  #         type ->
  #           input_type = type |> to_string |> Recase.to_pascal()
  #           Module.concat([__MODULE__, input_type])
  #       end
  #     end)
  #     |> assign(:input_opts, assigns.input.opts)
  #     |> assign(:label, label)
  #     |> assign(:instructions, instructions)
  #     |> assign(:placeholder, placeholder)
  #     |> assign(:field, assigns.input.name)

  #   ~H"""
  #   <div class="brando-input">
  #     <.live_component
  #       module={@component_module}
  #       id={@component_id}
  #       form={@form}
  #       field={@field}
  #       label={@label}
  #       placeholder={@placeholder}
  #       instructions={@instructions}
  #       opts={@input_opts}
  #       current_user={@current_user}
  #     />
  #   </div>
  #   """
  # end
end
