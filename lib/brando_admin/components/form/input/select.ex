defmodule BrandoAdmin.Components.Form.Input.Select do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Fieldset
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Toast
  alias Surface.Components.Form

  prop blueprint, :any
  prop form, :form
  prop field, :any
  prop label, :string
  prop instructions, :string
  prop class, :string
  prop options, :any
  prop current_user, :any

  # props for non blueprint
  prop narrow, :boolean, default: false
  prop resetable, :boolean, default: false
  prop show_filter, :boolean, default: true
  prop changeset_fun, :fun
  prop default_entry, :any
  prop entry_form, :any

  data open, :boolean
  data selected_option, :any
  data input_options, :list
  data select_form, :form
  data select_changeset, :any
  data filter_string, :string
  data modal_id, :string

  slot default

  import Brando.Gettext

  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:filter_string, "")}
  end

  def update(%{input: %{opts: opts}, blueprint: _} = assigns, socket) do
    selected_option = get_selected_option(assigns.form, assigns.input.name)

    show_filter = Keyword.get(opts, :filter, true)
    narrow = Keyword.get(opts, :narrow)
    resetable = Keyword.get(opts, :resetable)

    changeset_fun = Keyword.get(opts, :changeset_fun)
    default = Keyword.get(opts, :default)
    entry_form = Keyword.get(opts, :form)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_option, selected_option)
     |> assign_input_options()
     |> assign_label()
     |> assign(:narrow, narrow)
     |> assign(:resetable, resetable)
     |> assign(:show_filter, show_filter)
     |> assign(:changeset_fun, changeset_fun)
     |> assign(:default, default)
     |> assign(:entry_form, entry_form)
     |> maybe_assign_select_changeset()
     |> maybe_assign_select_form()
     |> assign_new(:modal_id, fn ->
       "select-#{assigns.form.id}-#{assigns.input.name}-modal"
     end)}
  end

  def update(assigns, socket) do
    selected_option = get_selected_option(assigns.form, assigns.field)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:default, assigns.default_entry)
     |> assign(:selected_option, selected_option)
     |> assign_input_options()
     |> assign_label()
     |> maybe_assign_select_changeset()
     |> maybe_assign_select_form()
     |> assign_new(:modal_id, fn ->
       "select-#{assigns.form.id}-#{assigns.field}-modal"
     end)}
  end

  def assign_input_options(%{assigns: %{form: form, input: %{opts: opts}}} = socket) do
    assign_new(socket, :input_options, fn -> get_input_options(form, opts) end)
  end

  def assign_input_options(%{assigns: %{form: _, options: options}} = socket) do
    assign_new(socket, :input_options, fn ->
      Enum.map(options, &ensure_string_values/1)
    end)
  end

  def update_input_options(%{assigns: %{form: form, input: %{opts: opts}}} = socket) do
    require Logger
    Logger.error("update_input_options!?")
    assign(socket, :input_options, get_input_options(form, opts))
  end

  def update_input_options(%{assigns: %{form: _form, options: options}} = socket) do
    require Logger
    Logger.error("update_input_options!?")
    assign(socket, :input_options, Enum.map(options, &ensure_string_values/1))
  end

  defp get_selected_option(form, field) do
    case input_value(form, field) do
      "" -> ""
      nil -> nil
      res when is_atom(res) -> to_string(res)
      res when is_integer(res) -> to_string(res)
      res -> res
    end
  end

  defp get_input_options(form, opts) do
    case Keyword.get(opts, :options) do
      :languages ->
        languages = Brando.config(:languages)
        Enum.map(languages, fn [{:value, val}, {:text, text}] -> %{label: text, value: val} end)

      nil ->
        # schema = blueprint.modules.schema
        []

      options_fun when is_function(options_fun) ->
        options_fun.(form, opts)
    end
    |> Enum.map(&ensure_string_values/1)
  end

  defp ensure_string_values(%{label: label, value: value}) when not is_binary(value) do
    %{label: label, value: to_string(value)}
  end

  defp ensure_string_values(map), do: map

  def assign_label(
        %{assigns: %{input_options: input_options, selected_option: selected_option}} = socket
      ) do
    assign(socket, :label, get_label(input_options, selected_option))
  end

  def maybe_assign_select_form(%{assigns: %{entry_form: {target_module, form_name}}} = socket) do
    select_form = target_module.__form__(form_name)
    assign(socket, :select_form, select_form)
  end

  def maybe_assign_select_form(socket) do
    assign(socket, :select_form, nil)
  end

  def maybe_assign_select_changeset(%{assigns: %{changeset_fun: nil}} = socket) do
    socket
    |> assign(:select_changeset, nil)
  end

  def maybe_assign_select_changeset(
        %{assigns: %{changeset_fun: changeset_fun, default: default, current_user: current_user}} =
          socket
      ) do
    select_changeset = changeset_fun.(default, %{}, current_user, [])
    module = select_changeset.data.__struct__
    singular = module.__naming__.singular

    socket
    |> assign(:select_changeset, select_changeset)
    |> assign(:singular, singular)
    |> assign(:module, module)
  end

  def render(%{input: %{name: name, opts: opts}, blueprint: _blueprint} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      class={opts[:class]}
      field={name}>

      {hidden_input @form, name, value: @selected_option}

      <div class="multiselect">
        <div>
          <span>
            {#if slot_assigned?(:default)}
              <#slot />
            {#else}
              {#if @selected_option}
                {@label |> raw}
              {#else}
                No selection
              {/if}
            {/if}
          </span>
        </div>
        <button
          type="button"
          class="button-edit"
          :on-click="toggle"
          phx-value-id={@modal_id}>
          {#if @open}
            Close
          {#else}
            Select
          {/if}
        </button>
        <Modal title="Select option" id={@modal_id} narrow={@narrow}>
          <div class="select-modal">
            {#if @show_filter && !Enum.empty?(@input_options)}
              <div class="select-filter" id={"#{@form.id}-#{name}-select-modal-filter"} phx-hook="Brando.SelectFilter">
                <div class="field-wrapper">
                  <div class="label-wrapper">
                    <label for="select-modal-search" class="control-label">
                      <span>Filter options</span>
                    </label>
                  </div>
                  <div class="field-base">
                    <input class="text" name="select-modal-search" type="text" value={@filter_string}>
                  </div>
                </div>
              </div>
            {/if}

            <div class="options">
              <h2 class="titlecase">Available options</h2>
              {#if Enum.empty?(@input_options)}
                No options found
              {/if}
              {#for opt <- @input_options}
                <button
                  type="button"
                  class={"options-option", "option-selected": opt.value == @selected_option}
                  data-label={opt.label}
                  value={opt.value}
                  :on-click="select_option">
                  {opt.label |> raw}
                </button>
              {/for}
            </div>

            {#if @select_form}
              <Form
                for={@select_changeset}
                change="validate_new_entry"
                :let={form: entry_form}>
                Create entry

                <code style="font-family: monospace; font-size: 11px"><pre>
                {inspect @select_changeset, pretty: true}
                </pre></code>
                <br>
                {#for {tab, _tab_idx} <- Enum.with_index(@select_form.tabs)}
                  <div
                    class={"form-tab", active: true}
                    data-tab-name={tab.name}>
                    <div class="row">
                      {#for {fieldset, fs_idx} <- Enum.with_index(tab.fields)}
                        <Fieldset
                          id={"#{entry_form.id}-fieldset-#{tab.name}-#{fs_idx}"}
                          blueprint={@blueprint}
                          form={entry_form}
                          uploads={[]}
                          fieldset={fieldset} />
                      {/for}
                    </div>
                  </div>
                {/for}
                <button
                  :on-click="save_new_entry"
                  type="button" class="primary">
                  Save
                </button>
              </Form>
            {/if}

            {#if @resetable}
              <div class="reset">
                <button
                  type="button"
                  class="secondary"
                  :on-click="reset">
                  Reset value
                </button>
              </div>
            {/if}
          </div>
        </Modal>
      </div>
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      form={@form}
      field={@field}>

      {hidden_input @form, @field, value: @selected_option}

      <div class="multiselect">
        <div>
          <span>
            {#if slot_assigned?(:default)}
              <#slot />
            {#else}
              {#if @selected_option}
                {@label}
              {#else}
                No selection
              {/if}
            {/if}
          </span>
        </div>
        <button
          type="button"
          class="button-edit"
          :on-click="toggle"
          phx-value-id={@modal_id}>
          {#if @open}
            Close
          {#else}
            Select
          {/if}
        </button>
        <Modal title="Select option" id={@modal_id} narrow={@narrow}>
          <div class="select-modal">
            {#if @show_filter && !Enum.empty?(@input_options)}
              <div class="select-filter" id={"#{@form.id}-#{@field}-select-modal-filter"} phx-hook="Brando.SelectFilter">
                <div class="field-wrapper">
                  <div class="label-wrapper">
                    <label for="select-modal-search" class="control-label">
                      <span>Filter options</span>
                    </label>
                  </div>
                  <div class="field-base">
                    <input class="text" name="select-modal-search" type="text" value={@filter_string}>
                  </div>
                </div>
              </div>
            {/if}

            <div class="options">
              <h2 class="titlecase">Available options</h2>
              {#if Enum.empty?(@input_options)}
                No options found
              {/if}
              {#for opt <- @input_options}
                <button
                  type="button"
                  class={"options-option", "option-selected": opt.value == @selected_option}
                  data-label={opt.label}
                  value={opt.value}
                  :on-click="select_option">
                  {opt.label |> raw}
                </button>
              {/for}
            </div>

            {#if @select_form}
              <Form
                for={@select_changeset}
                change="validate_new_entry"
                :let={form: entry_form}>
                Create entry

                <code style="font-family: monospace; font-size: 11px"><pre>
                {inspect @select_changeset, pretty: true}
                </pre></code>
                <br>
                {#for {tab, _tab_idx} <- Enum.with_index(@select_form.tabs)}
                  <div
                    class={"form-tab", active: true}
                    data-tab-name={tab.name}>
                    <div class="row">
                      {#for {fieldset, fs_idx} <- Enum.with_index(tab.fields)}
                        <Fieldset
                          id={"#{entry_form.id}-fieldset-#{tab.name}-#{fs_idx}"}
                          blueprint={@blueprint}
                          form={entry_form}
                          uploads={[]}
                          fieldset={fieldset} />
                      {/for}
                    </div>
                  </div>
                {/for}
                <button
                  :on-click="save_new_entry"
                  type="button" class="primary">
                  Save
                </button>
              </Form>
            {/if}

            {#if @resetable}
              <div class="reset">
                <button
                  type="button"
                  class="secondary"
                  :on-click="reset">
                  Reset value
                </button>
              </div>
            {/if}
          </div>
        </Modal>
      </div>
    </FieldBase>
    """
  end

  defp get_label(input_options, selected_option) do
    case Enum.find(input_options, &(&1.value == selected_option)) do
      nil -> "<No value>"
      %{label: label} -> label
    end
  end

  def handle_event(
        "save_new_entry",
        _,
        %{
          assigns: %{
            select_changeset: select_changeset,
            module: module,
            singular: singular,
            current_user: current_user
          }
        } = socket
      ) do
    context = module.__modules__.context

    select_changeset =
      select_changeset
      |> Map.put(:action, :create)

    case apply(context, :"create_#{singular}", [select_changeset, current_user]) do
      {:ok, _} ->
        Toast.send_delayed("#{String.capitalize(singular)} created")

        {:noreply,
         socket
         |> assign(select_changeset: select_changeset)
         |> assign_input_options()}

      {:error, %Ecto.Changeset{} = select_changeset} ->
        {:noreply, assign(socket, select_changeset: select_changeset)}
    end
  end

  def handle_event(
        "validate_new_entry",
        params,
        %{
          assigns: %{
            singular: singular,
            changeset_fun: changeset_fun,
            current_user: current_user,
            default: default
          }
        } = socket
      ) do
    entry_params = Map.get(params, singular)

    select_changeset =
      default
      |> changeset_fun.(entry_params, current_user, skip_villain: true)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, select_changeset: select_changeset)}
  end

  def handle_event(
        "select_option",
        %{"value" => value},
        %{assigns: %{input_options: input_options, modal_id: modal_id}} = socket
      ) do
    label = get_label(input_options, value)

    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:selected_option, value)
     |> assign(:label, label)
     |> push_event("b:validate", %{})}
  end

  def handle_event(
        "reset",
        _,
        %{assigns: %{input_options: input_options, modal_id: modal_id}} = socket
      ) do
    label = get_label(input_options, "")

    Modal.hide(modal_id)

    {:noreply,
     socket
     |> assign(:selected_option, "")
     |> assign(:label, label)}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    Modal.show(id)
    {:noreply, socket}
  end
end
