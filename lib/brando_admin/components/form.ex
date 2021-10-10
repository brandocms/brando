defmodule BrandoAdmin.Components.Form do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext
  import Ecto.Changeset

  alias Brando.Villain

  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Form.MetaDrawer
  alias BrandoAdmin.Components.Form.RevisionsDrawer
  alias BrandoAdmin.Components.Form.ScheduledPublishingDrawer
  alias BrandoAdmin.Components.Form.Submit

  alias Surface.Components.Form

  prop uploads, :any
  prop current_user, :any
  prop entry_id, :any
  prop schema, :any
  prop name, :atom, default: :default
  prop initial_params, :map

  data entry, :any
  data blueprint, :any
  data form, :any
  data changeset, :any
  data singular, :string
  data tabs, :list
  data active_tab, :string
  data processing, :boolean
  data initial_update, :boolean

  data status_meta, :atom
  data status_scheduled, :atom
  data status_revisions, :atom

  data has_meta?, :boolean
  data has_revisioning?, :boolean
  data has_scheduled_publishing?, :boolean
  data has_live_preview?, :boolean

  data live_preview_active?, :boolean
  data live_preview_cache_key, :string

  def mount(socket) do
    {:ok,
     socket
     |> assign(:has_meta?, false)
     |> assign(:status_meta, :closed)
     |> assign(:status_scheduled, :closed)
     |> assign(:status_revisions, :closed)
     |> assign(:live_preview_active?, false)
     |> assign(:processing, false)
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

  def update(
        %{updated_image: %{path: _} = updated_image, key: key},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    updated_changeset = Ecto.Changeset.put_change(changeset, key, updated_image)

    {:ok,
     socket
     |> assign(:changeset, updated_changeset)
     |> assign(:processing, false)
     |> push_event("b:validate", %{})}
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
    form_name = assigns.name

    {:ok,
     socket
     |> assign(assigns)
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

  defp maybe_assign_uploads(socket) do
    if connected?(socket) && !socket.assigns[:initial_update] do
      socket
      |> assign(:initial_update, true)
      |> allow_uploads()
    else
      socket
    end
  end

  defp assign_entry(%{assigns: %{entry_id: nil}} = socket) do
    assign_new(socket, :entry, fn -> nil end)
  end

  defp assign_entry(
         %{
           assigns: %{
             entry_id: entry_id,
             singular: singular,
             context: context,
             form: form
           }
         } = socket
       ) do
    query_params = form.query.(entry_id)
    assign_new(socket, :entry, fn -> apply(context, :"get_#{singular}!", [query_params]) end)
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
    socket
    |> assign_new(:active_tab, fn -> "Content" end)
    |> assign_new(:tabs, fn -> Enum.map(tabs, & &1.name) end)
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@id}-el"}
      class="brando-form b-rendered"
      data-moonwalk-run="brandoForm"
      phx-hook="Brando.Form">

      {!-- TODO: extract to Form.Tabs. How do we handle the open_meta_drawers etc? :builtins slot? --}
      <div class="form-tabs">
        <div class="form-tab-customs">
          {#for tab <- @tabs}
            <button
              type="button" class={active: @active_tab == tab}
              :on-click="select_tab"
              phx-value-name={tab}>
              {tab}
            </button>
          {/for}
        </div>

        <div class="form-tab-builtins">
          {#if @has_meta?}
            <button
              :on-click="open_meta_drawer"
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.9 2.1l9.899 1.415 1.414 9.9-9.192 9.192a1 1 0 0 1-1.414 0l-9.9-9.9a1 1 0 0 1 0-1.414L10.9 2.1zm.707 2.122L3.828 12l8.486 8.485 7.778-7.778-1.06-7.425-7.425-1.06zm2.12 6.364a2 2 0 1 1 2.83-2.829 2 2 0 0 1-2.83 2.829z"/></svg>
              <span class="tab-text">Meta</span>
            </button>
          {/if}
          {#if @has_revisioning?}
            <button
              :on-click="open_revisions_drawer"
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M7.105 15.21A3.001 3.001 0 1 1 5 15.17V8.83a3.001 3.001 0 1 1 2 0V12c.836-.628 1.874-1 3-1h4a3.001 3.001 0 0 0 2.895-2.21 3.001 3.001 0 1 1 2.032.064A5.001 5.001 0 0 1 14 13h-4a3.001 3.001 0 0 0-2.895 2.21zM6 17a1 1 0 1 0 0 2 1 1 0 0 0 0-2zM6 5a1 1 0 1 0 0 2 1 1 0 0 0 0-2zm12 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2z"/></svg>
              <span class="tab-text">Revisions</span>
            </button>
          {/if}
          {#if @has_scheduled_publishing?}
            <button
              :on-click="open_scheduled_publishing_drawer"
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M17 3h4a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h4V1h2v2h6V1h2v2zm-2 2H9v2H7V5H4v4h16V5h-3v2h-2V5zm5 6H4v8h16v-8zM6 14h2v2H6v-2zm4 0h8v2h-8v-2z"/></svg>
              <span class="tab-text">Scheduled publishing</span>
            </button>
          {/if}
          {#if @has_live_preview?}
            <button
              :on-click="open_live_preview"
              class={active: @live_preview_active?}
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 3c5.392 0 9.878 3.88 10.819 9-.94 5.12-5.427 9-10.819 9-5.392 0-9.878-3.88-10.819-9C2.121 6.88 6.608 3 12 3zm0 16a9.005 9.005 0 0 0 8.777-7 9.005 9.005 0 0 0-17.554 0A9.005 9.005 0 0 0 12 19zm0-2.5a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9zm0-2a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/></svg>
            </button>
            <button
              type="button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M11 2.05v2.012A8.001 8.001 0 0 0 12 20a8.001 8.001 0 0 0 7.938-7h2.013c-.502 5.053-4.766 9-9.951 9-5.523 0-10-4.477-10-10 0-5.185 3.947-9.449 9-9.95zm9 3.364l-8 8L10.586 12l8-8H14V2h8v8h-2V5.414z"/></svg>
            </button>
            {/if}
          <button
            :on-click="push_submit_event"
            type="button">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M7 19v-6h10v6h2V7.828L16.172 5H5v14h2zM4 3h13l4 4v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm5 12v4h6v-4H9z"/></svg>
            <span class="tab-text">(⌘S)</span>
          </button>
        </div>
      </div>

      <Form
        for={@changeset}
        submit={"save", target: :live_view}
        change="validate"
        :let={form: f}>

        {#if @has_meta?}
          <MetaDrawer
            id={"#{@id}-meta-drawer"}
            blueprint={@blueprint}
            uploads={@uploads}
            form={f}
            status={@status_meta}
            close="close_meta_drawer" />
        {/if}

        {#if @has_revisioning?}
          <RevisionsDrawer
            id={"#{@id}-revisions-drawer"}
            current_user={@current_user}
            blueprint={@blueprint}
            form={f}
            status={@status_revisions}
            close="close_revisions_drawer" />
        {/if}

        {#if @has_scheduled_publishing?}
          <ScheduledPublishingDrawer
            id={"#{@id}-scheduled-publishing-drawer"}
            blueprint={@blueprint}
            form={f}
            status={@status_scheduled}
            close="close_scheduled_publishing_drawer" />
        {/if}

        {#for {tab, _tab_idx} <- Enum.with_index(@form.tabs)}
          <div
            class={"form-tab", active: @active_tab == tab.name}
            data-tab-name={tab.name}>
            <div class="row">
              {#for {fieldset, fs_idx} <- Enum.with_index(tab.fields)}
                <Fieldset
                  id={"#{f.id}-fieldset-#{tab.name}-#{fs_idx}"}
                  blueprint={@blueprint}
                  form={f}
                  uploads={@uploads}
                  fieldset={fieldset}
                  current_user={@current_user} />
              {/for}
            </div>
          </div>
        {/for}

        <Submit
          processing={@processing}
          form_id={@id}
          label={gettext("Save (⌘S)")}
          class="primary submit-button" />
      </Form>
    </div>
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

    Enum.reduce(gallery_fields, socket_with_image_uploads, fn gallery_field, updated_socket ->
      allow_upload(updated_socket, gallery_field.name,
        # TODO: Read max_entries from gallery config!
        max_entries: 10,
        accept: :any,
        auto_upload: true,
        progress: &__MODULE__.handle_gallery_progress/3
      )
    end)
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

  def handle_event("open_scheduled_publishing_drawer", _, socket) do
    {:noreply, push_event(socket, "b:drawer:open", %{id: ".scheduled-publishing-drawer"})}
  end

  def handle_event("close_scheduled_publishing_drawer", _, socket) do
    {:noreply, push_event(socket, "b:drawer:close", %{id: ".scheduled-publishing-drawer"})}
  end

  def handle_event("open_meta_drawer", _, socket) do
    {:noreply, push_event(socket, "b:drawer:open", %{id: ".meta-drawer"})}
  end

  def handle_event("close_meta_drawer", _, socket) do
    {:noreply, push_event(socket, "b:drawer:close", %{id: ".meta-drawer"})}
  end

  def handle_event("open_revisions_drawer", _, socket) do
    if Ecto.Changeset.get_field(socket.assigns.changeset, :id) do
      {:noreply,
       socket
       |> assign(:status_revisions, :open)
       |> push_event("b:drawer:open", %{id: ".revisions-drawer"})}
    else
      error_title = "Notice"

      error_msg =
        "To create and administrate revisions, the entry must be saved at least one time first."

      {:noreply, push_event(socket, "b:alert", %{title: error_title, message: error_msg})}
    end
  end

  def handle_event("close_revisions_drawer", _, socket) do
    {:noreply,
     socket
     |> assign(:status_revisions, :closed)
     |> push_event("b:drawer:close", %{id: ".revisions-drawer"})}
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
            Brando.Upload.handle_upload(meta, upload_entry, cfg)
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
       |> update_changeset(key, [image_struct | existing_images])
       |> assign(:processing, true)}
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
            entry: entry,
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
            Brando.Upload.handle_upload(meta, upload_entry, cfg)
          end
        )

      pid = self()

      Task.start_link(fn ->
        {:ok, image_struct} = Brando.Upload.process_upload(image_struct, cfg, current_user)

        send_update(pid, __MODULE__,
          id: form_id,
          key: key,
          updated_image: image_struct
        )
      end)

      image_struct =
        if entry && is_map(Map.get(entry, key)) do
          # keep the :alt, :title and :credits field and set a default focal point
          Map.merge(
            image_struct,
            Map.take(Map.get(entry, key), [:alt, :title, :credits])
          )
        else
          image_struct
        end

      {:noreply,
       socket
       |> update_changeset(key, image_struct)
       |> assign(:processing, true)}
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

  def update_changeset(%{assigns: %{changeset: changeset}} = socket, key, value) do
    new_changeset = put_change(changeset, key, Map.from_struct(value))
    assign(socket, :changeset, new_changeset)
  end
end
