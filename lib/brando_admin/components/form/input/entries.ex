defmodule BrandoAdmin.Components.Form.Input.Entries do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Identifier
  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.HiddenInput

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop placeholder, :string
  prop instructions, :string
  prop class, :string
  prop disabled, :boolean
  prop debounce, :integer

  data available_schemas, :list
  data identifiers, :list
  data selected_identifiers, :list

  def mount(socket) do
    {:ok, assign(socket, identifiers: [])}
  end

  def update(%{blueprint: blueprint, input: %{name: name, opts: opts}} = assigns, socket) do
    translations = get_in(blueprint.translations, [:fields, name]) || []
    placeholder = Keyword.get(translations, :placeholder, assigns[:placeholder])
    value = assigns[:value]

    selected_identifiers =
      assigns.form
      |> input_value(name)
      |> Enum.map(fn
        %Brando.Content.Identifier{} = identifier ->
          require Logger
          Logger.error("==> identifier: #{inspect(identifier, pretty: true)}")
          identifier

        %Ecto.Changeset{action: :replace} = changeset ->
          nil

        %Ecto.Changeset{} = changeset ->
          require Logger
          Logger.error("==> changeset: #{inspect(changeset, pretty: true)}")
          Ecto.Changeset.apply_changes(changeset)
      end)
      |> Enum.reject(&(&1 == nil))

    selected_identifiers_forms = inputs_for(assigns.form, name)

    require Logger
    Logger.error("== selected_identifiers ==")
    Logger.error(inspect(selected_identifiers, pretty: true))

    wanted_schemas = Keyword.get(opts, :for)

    if !wanted_schemas do
      raise Brando.Exception.BlueprintError,
        message: """
        Missing `for` option for `:entries` field `#{inspect(name)}`

            input :related_entries, :entries, for: [
              {MyApp.Projects.Project, %{preload: [:category]}},
              {Brando.Pages.Page, %{}}
            ]

        """
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_identifiers, selected_identifiers)
     |> assign(:selected_identifiers_forms, selected_identifiers_forms)
     |> assign_available_schemas(wanted_schemas)
     |> assign_selected_schema()
     |> assign(
       placeholder: placeholder,
       value: value
     )}
  end

  def update(assigns, socket) do
    value = assigns[:value]

    {:ok,
     socket
     |> assign(assigns)
     |> assign(value: value)}
  end

  def assign_available_schemas(socket, wanted_schemas) do
    assign_new(socket, :available_schemas, fn ->
      Brando.Blueprint.Identifier.get_entry_types(wanted_schemas)
      |> IO.inspect()
    end)
  end

  def assign_selected_schema(%{assigns: %{available_schemas: available_schemas}} = socket)
      when length(available_schemas) == 1 do
    assign_new(socket, :selected_schema, fn -> List.first(available_schemas) end)
  end

  def assign_selected_schema(socket) do
    assign_new(socket, :selected_schema, fn -> nil end)
  end

  def render(%{blueprint: _, input: %{name: name, opts: _opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      form={@form}>
      {#if Enum.empty?(@selected_identifiers)}
        <div class="empty-list">
          {gettext("No selected entries")}
        </div>
      {/if}

      <Inputs
        form={@form}
        for={name}>
        <HiddenInput field={:id} />
        <HiddenInput field={:schema} />
        <HiddenInput field={:status} />
        <HiddenInput field={:title} />
        <HiddenInput field={:cover} />
        <HiddenInput field={:type} />
        <HiddenInput field={:absolute_url} />
      </Inputs>

      {#for {selected_identifier, idx} <- Enum.with_index(@selected_identifiers)}
        <Identifier
          identifier={selected_identifier}
          remove="remove_identifier"
          param={idx}
        />
      {/for}

      <button type="button" class="add-entry-button" :on-click="show_modal" phx-value-id={"#{@form.id}-#{name}-select-entries"}>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z" fill="rgba(252,245,243,1)"/></svg>
        {gettext("Select entries")}
      </button>

      <Modal title="Select entries" id={"#{@form.id}-#{name}-select-entries"} narrow>
        <h2 class="titlecase">{gettext("Select content type")}</h2>
        <div class="button-group-vertical">
        {#for {label, schema, _} <- @available_schemas}
          <button type="button" class="secondary" :on-click="select_schema" phx-value-schema={schema}>
            {label}
          </button>
        {/for}
        </div>
        {#if !Enum.empty?(@identifiers)}
          <h2 class="titlecase">{gettext("Available entries")}</h2>
          {#for {identifier, idx} <- Enum.with_index(@identifiers)}
            <Identifier
              identifier={identifier}
              select="select_identifier"
              selected_identifiers={@selected_identifiers}
              param={idx}
            />
          {/for}
        {/if}
      </Modal>
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      label={@label}
      placeholder={@placeholder}
      instructions={@instructions}
      field={@field}
      form={@form}>
    </FieldBase>
    """
  end

  def handle_event(
        "select_identifier",
        %{"param" => idx},
        %{
          assigns: %{
            input: %{name: field_name},
            form: %{source: changeset} = form,
            identifiers: identifiers,
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    selected_identifier = Enum.at(identifiers, String.to_integer(idx))

    require Logger
    Logger.error(inspect(selected_identifier, pretty: true))
    Logger.error(inspect(selected_identifiers, pretty: true))

    updated_identifiers =
      case Enum.find(selected_identifiers, &(&1 == selected_identifier)) do
        nil -> selected_identifiers ++ List.wrap(selected_identifier)
        _ -> Enum.reject(selected_identifiers, &(&1 == selected_identifier))
      end

    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, updated_identifiers)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "remove_identifier",
        %{"param" => idx},
        %{
          assigns: %{
            input: %{name: field_name},
            form: %{source: changeset} = form,
            selected_identifiers: selected_identifiers
          }
        } = socket
      ) do
    {_, new_list} = List.pop_at(selected_identifiers, String.to_integer(idx))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, new_list)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("show_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)

    {:noreply, socket}
  end

  def handle_event(
        "select_schema",
        %{"schema" => schema},
        %{assigns: %{available_schemas: available_schemas}} = socket
      ) do
    schema_module = Module.concat([schema])
    {_, _, list_opts} = get_list_opts(schema_module, available_schemas)
    {:ok, identifiers} = Brando.Blueprint.Identifier.list_entries_for(schema_module, list_opts)
    {:noreply, assign(socket, :identifiers, identifiers)}
  end

  defp get_list_opts(schema_module, available_schemas) do
    Enum.find(available_schemas, &(elem(&1, 1) == schema_module))
  end
end
