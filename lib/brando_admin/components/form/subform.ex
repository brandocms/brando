defmodule BrandoAdmin.Components.Form.Subform do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Subform

  use Gettext, backend: Brando.Gettext

  # prop subform, :any
  # prop form, :any
  # prop blueprint, :any
  # prop parent_uploads, :any
  # prop current_user, :map
  # prop label, :string
  # prop instructions, :string
  # prop placeholder, :string

  def update(
        %{action: :update_changeset, index: index, updated_changeset: updated_changeset},
        socket
      ) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    related_entries =
      changeset
      |> Ecto.Changeset.get_field(field_name)
      |> List.replace_at(index, updated_changeset)

    updated_master_changeset =
      if socket.assigns.embeds? do
        Ecto.Changeset.put_embed(changeset, field_name, related_entries)
      else
        Ecto.Changeset.put_assoc(changeset, field_name, related_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_master_changeset,
      force_validation: false
    )

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> prepare_subform_component()
      |> assign_new(:open_entries, fn -> [] end)
      |> assign_new(:sequenced?, fn ->
        # can we sequence the subform? we can if it
        #   - is an embed
        #   - has a :sequenced trait
        parent_schema = assigns.field.form.data.__struct__

        case Brando.Blueprint.Relations.__relation__(parent_schema, assigns.subform.name) do
          %Brando.Blueprint.Relations.Relation{type: :has_many, opts: %{module: rel_module}} ->
            rel_module.has_trait(Brando.Trait.Sequenced)

          %Brando.Blueprint.Relations.Relation{type: :embeds_many} ->
            true

          _ ->
            false
        end
      end)
      |> assign_new(:embeds?, fn ->
        parent_schema = assigns.field.form.data.__struct__

        case Brando.Blueprint.Relations.__relation__(parent_schema, assigns.subform.name) do
          %Brando.Blueprint.Relations.Relation{type: :embeds_many} -> true
          _ -> false
        end
      end)
      |> assign(:empty_subform_fields, assigns.field == [])
      |> assign(:path, List.wrap(assigns.subform.name))
      |> assign_new(:parent_form_id, fn ->
        parent_schema = assigns.field.form.data.__struct__
        "#{parent_schema.__naming__().singular}_form"
      end)

    {:ok, socket}
  end

  def render(%{subform: %{style: {:transformer, transform_field}}} = assigns) do
    upload_key = :"#{assigns.subform.name}|#{transform_field}|transformer"
    _ = :"#{assigns.subform.name}|#{transform_field}_id"
    upload_field = Map.get(assigns.parent_uploads, upload_key)

    assigns =
      assigns
      |> assign(:upload_field, upload_field)
      |> assign(:transform_field, transform_field)

    ~H"""
    <fieldset>
      <Form.field_base
        :if={@subform.cardinality == :many}
        field={@field}
        label={@label}
        instructions={@instructions}
        class="subform"
        meta_top
      >
        <div
          id={"#{@field.id}-sortable"}
          data-embeds={@embeds?}
          phx-hook={@sequenced? && "Brando.SortableEmbeds"}
        >
          <.empty_subform :if={@empty_subform_fields} field={@field} />
          <.inputs_for :let={sub_form} field={@field} skip_hidden>
            <div
              class={[
                "subform-entry",
                "group",
                sub_form.index not in @open_entries && "listing"
              ]}
              data-id={sub_form.index}
            >
              <input type="hidden" name={sub_form[:id].name} value={sub_form[:id].value} />
              <input type="hidden" name={sub_form[:_persistent_id].name} value={sub_form.index} />
              <input
                type="hidden"
                name={"#{@field.form.name}[sort_#{@field.field}_ids][]"}
                value={sub_form.index}
              />
              <div class="subform-tools">
                <.subentry_edit
                  on_click={
                    JS.push("edit_subentry", value: %{index: sub_form.index}, target: @myself)
                  }
                  open={sub_form.index in @open_entries}
                />
                <.subentry_sequence :if={@sequenced?} />
                <.subentry_remove
                  name={"#{@field.form.name}[drop_#{@field.field}_ids][]"}
                  index={sub_form.index}
                />
              </div>
              <.listing subform={sub_form} subform_config={@subform} />
              <div class="subform-fields">
                <Input.hidden
                  :if={@sequenced? and !@embeds?}
                  field={sub_form[:sequence]}
                  value={sub_form.index}
                />
                <Subform.Field.render
                  :for={input <- @subform.sub_fields}
                  cardinality={:many}
                  sub_form={sub_form}
                  input={input}
                  path={@path ++ [sub_form.index]}
                  parent_uploads={@parent_uploads}
                  parent_form_id={@parent_form_id}
                  subform_id={@myself}
                  current_user={@current_user}
                />
              </div>
            </div>
          </.inputs_for>
        </div>
        <div class="actions">
          <.subentry_add on_click={JS.push("add_subentry", target: @myself)} />
          <.transformer_upload upload_field={@upload_field} />
          <.sort_by_filename on_click={
            JS.push("sort_by_filename", value: %{transform_field: @transform_field}, target: @myself)
          } />
        </div>
      </Form.field_base>
    </fieldset>
    """
  end

  # inline
  def render(%{subform: _} = assigns) do
    ~H"""
    <fieldset>
      <Form.field_base
        :if={@subform.cardinality == :one}
        field={@field}
        label={@label}
        instructions={@instructions}
        class="subform"
        meta_top
      >
        <.inputs_for :let={sub_form} field={@field} skip_hidden>
          <div class="subform-entry">
            <Input.input type={:hidden} field={sub_form[:id]} />
            <Input.input type={:hidden} field={sub_form[:_persistent_id]} value={sub_form.index} />
            <Subform.Field.render
              :for={input <- @subform.sub_fields}
              cardinality={:one}
              sub_form={sub_form}
              label={@label}
              instructions={@instructions}
              placeholder={@placeholder}
              input={input}
              path={@path}
              parent_uploads={@parent_uploads}
              parent_form_id={@parent_form_id}
              subform_id={@myself}
              current_user={@current_user}
            />
          </div>
        </.inputs_for>
      </Form.field_base>
      <Form.field_base
        :if={@subform.cardinality == :many}
        field={@field}
        label={@label}
        instructions={@instructions}
        class="subform"
        meta_top
      >
        <div
          id={"#{@field.id}-sortable"}
          data-embeds={@embeds?}
          phx-hook="Brando.SortableEmbeds"
          data-sortable-handle=".subform-handle"
          data-sortable-id={"#{@field.name}-sortable"}
          data-sortable-selector=".subform-entry"
        >
          <.empty_subform :if={@empty_subform_fields} field={@field} />
          <.inputs_for :let={sub_form} field={@field}>
            <div class={["subform-entry", @subform.style == :inline && "inline"]}>
              <input
                type="hidden"
                name={"#{@field.form.name}[sort_#{@field.field}_ids][]"}
                value={sub_form.index}
              />
              <div class="subform-tools">
                <.subentry_sequence :if={@sequenced?} />
                <.subentry_remove
                  name={"#{@field.form.name}[drop_#{@field.field}_ids][]"}
                  index={sub_form.index}
                />
              </div>

              <div class="subform-fields">
                <Subform.Field.render
                  :for={input <- @subform.sub_fields}
                  cardinality={:many}
                  sub_form={sub_form}
                  input={input}
                  path={@path ++ [sub_form.index]}
                  parent_uploads={@parent_uploads}
                  parent_form_id={@parent_form_id}
                  subform_id={@myself}
                  current_user={@current_user}
                />
              </div>
            </div>
          </.inputs_for>
          <input type="hidden" name={"#{@field.form.name}[drop_#{@field.field}_ids][]"} />
        </div>
        <.subentry_add on_click={JS.push("add_subentry", target: @myself)} />
      </Form.field_base>
    </fieldset>
    """
  end

  def transformer_upload(assigns) do
    ~H"""
    <label class="upload-button">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        width="16"
        height="16"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="w-6 h-6"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
      </svg>
      {gettext("Pick files")}
      <.live_file_input upload={@upload_field} />
    </label>
    """
  end

  def subentry_add(assigns) do
    ~H"""
    <button type="button" class="add-entry-button" phx-click={@on_click} phx-page-loading>
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16">
        <path fill="none" d="M0 0h24v24H0z" /><path
          d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z"
          fill="rgba(252,245,243,1)"
        />
      </svg>
      {gettext("Add entry")}
    </button>
    """
  end

  def sort_by_filename(assigns) do
    ~H"""
    <button type="button" class="add-entry-button" phx-click={@on_click} phx-page-loading>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        width="16"
        height="16"
        stroke-width="1.5"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M19.5 12c0-1.232-.046-2.453-.138-3.662a4.006 4.006 0 00-3.7-3.7 48.678 48.678 0 00-7.324 0 4.006 4.006 0 00-3.7 3.7c-.017.22-.032.441-.046.662M19.5 12l3-3m-3 3l-3-3m-12 3c0 1.232.046 2.453.138 3.662a4.006 4.006 0 003.7 3.7 48.656 48.656 0 007.324 0 4.006 4.006 0 003.7-3.7c.017-.22.032-.441.046-.662M4.5 12l3 3m-3-3l-3 3"
        />
      </svg>
      {gettext("Sort by filename")}
    </button>
    """
  end

  def subentry_sequence(assigns) do
    ~H"""
    <button type="button" class="subform-handle">
      <.icon name="hero-arrows-up-down" />
    </button>
    """
  end

  def subentry_edit(assigns) do
    ~H"""
    <button class="subform-edit" type="button" phx-click={@on_click} phx-page-loading>
      <svg
        :if={!@open}
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        width="16"
        height="16"
        stroke-width="1.5"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10"
        />
      </svg>
      <svg
        :if={@open}
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        width="16"
        height="16"
        stroke-width="1.5"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
    </button>
    """
  end

  attr :name, :string, required: true
  attr :index, :integer, required: true

  def subentry_remove(assigns) do
    ~H"""
    <button
      name={@name}
      type="button"
      value={@index}
      phx-click={JS.dispatch("change")}
      class="subform-delete"
    >
      <.icon name="hero-x-mark" />
    </button>
    """
  end

  attr :field, Phoenix.HTML.FormField

  def empty_subform(assigns) do
    ~H"""
    <input type="hidden" name={@field.name} value="" />
    <div class="subform-empty">&rarr; {gettext("No associated entries")}</div>
    """
  end

  def listing(assigns) do
    {:transformer, image_field_atom} = assigns.subform_config.style

    assigns =
      assigns
      |> assign(:image_field, assigns.subform[image_field_atom])
      |> assign(:entry, Ecto.Changeset.apply_changes(assigns.subform.source))

    ~H"""
    <div class="subform-listing">
      <.live_component
        module={Input.Image}
        id={"#{@subform.id}-image_field"}
        field={@image_field}
        parent_uploads={[]}
        form={@subform}
        label={:hidden}
        editable={false}
        square
      />
      <div class="subform-listing-row">
        {Phoenix.LiveView.TagEngine.component(
          @subform_config.listing,
          [entry: @entry],
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        )}
      </div>
    </div>
    """
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("edit_subentry", %{"index" => index}, socket) do
    open_entries = socket.assigns.open_entries

    if index in open_entries do
      {:noreply, assign(socket, :open_entries, Enum.reject(open_entries, &(&1 == index)))}
    else
      {:noreply, update(socket, :open_entries, &(&1 ++ [index]))}
    end
  end

  def handle_event("add_subentry", _, socket) do
    changeset = socket.assigns.field.form.source
    entry = Ecto.Changeset.apply_changes(changeset)

    default =
      case socket.assigns.subform.default do
        fun when is_function(fun) -> fun.(entry, nil)
        struct -> struct
      end

    field_name = socket.assigns.subform.name

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_field =
      changeset
      |> Ecto.Changeset.get_field(field_name)
      |> Kernel.++([default])

    updated_changeset =
      case Enum.find(socket.assigns.relations, &(&1.name == field_name)) do
        %{type: :has_many} ->
          # assoc
          Ecto.Changeset.put_assoc(changeset, field_name, updated_field)

        _ ->
          # embed
          Ecto.Changeset.put_embed(changeset, field_name, updated_field)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  def handle_event("remove_subentry", %{"index" => index}, socket) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    related_entries =
      changeset
      |> Ecto.Changeset.get_field(field_name)
      |> List.delete_at(index)

    updated_changeset =
      if socket.assigns.embeds? do
        Ecto.Changeset.put_embed(changeset, field_name, related_entries)
      else
        Ecto.Changeset.put_assoc(changeset, field_name, related_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: false
    )

    {:noreply, socket}
  end

  def handle_event("force_validate", _, socket) do
    {:noreply, push_event(socket, "b:validate", %{})}
  end

  def handle_event("sort_by_filename", %{"transform_field" => transform_field}, socket) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    %{type: rel_type} = Brando.Blueprint.Relations.__relation__(module, field_name)
    form_id = "#{module.__naming__().singular}_form"

    # TODO: change to Ecto.Changeset.get_assoc(changeset, field_name)
    # then we can skip the .change in extract_path too maybe?
    related_entries = get_change_or_field(changeset, field_name)

    order_indices =
      related_entries
      |> Enum.map(&extract_path(&1, transform_field))
      |> Enum.with_index()
      |> Enum.sort()
      |> Enum.map(fn {_, idx} -> idx end)

    sorted_related_entries =
      order_indices
      |> Enum.map(&Enum.at(related_entries, &1))
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} -> Ecto.Changeset.change(entry, %{sequence: idx}) end)

    updated_changeset =
      if rel_type == :embeds_many do
        Ecto.Changeset.put_embed(changeset, field_name, sorted_related_entries)
      else
        Ecto.Changeset.put_assoc(changeset, field_name, sorted_related_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: false
    )

    {:noreply, socket}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices} = event_params, socket) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"
    embed? = event_params["embeds"]

    related_entries = get_change_or_field(changeset, field_name)

    sorted_related_entries =
      order_indices
      |> Enum.map(&Enum.at(related_entries, &1))
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        if embed? do
          entry
        else
          Ecto.Changeset.change(entry, %{sequence: idx})
        end
      end)

    updated_changeset =
      if embed? do
        Ecto.Changeset.put_embed(changeset, field_name, sorted_related_entries)
      else
        Ecto.Changeset.put_assoc(changeset, field_name, sorted_related_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  defp get_change_or_field(changeset, field) do
    with nil <- Ecto.Changeset.get_change(changeset, field) do
      Ecto.Changeset.get_field(changeset, field, [])
    end
  end

  defp extract_path(entry, transform_field) do
    field_map =
      entry
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.get_field(String.to_existing_atom(transform_field), %{path: ""})

    (is_map(field_map) && Brando.Utils.try_path(field_map, [:path])) || ""
  end
end
